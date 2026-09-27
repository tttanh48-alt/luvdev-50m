// ============================================================
// esp.mm — Part 1/8
// Header + extern + forward decl + globals
// ============================================================

#import "esp.h"
#import "ESPPrefs.h"
#import "GameOffsets.h"
#import "../DSMemory.h"
#import "../../app/KernelBoot.h"
#import "../../remote/SpringBoardOverlay.h"
#import "GameLogic.h"

#import <QuartzCore/QuartzCore.h>
#import <mach/mach_time.h>
#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import <notify.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <string>
#include <vector>
#include <cmath>
#include <float.h>
#import <mach/mach.h>
#include <mutex>
#include <atomic>
#include <thread>
#include <chrono>

#ifdef __cplusplus
extern "C" {
#endif
    kern_return_t mach_vm_region(
        vm_map_t target_task,
        mach_vm_address_t *address,
        mach_vm_size_t *size,
        vm_region_flavor_t flavor,
        vm_region_info_t info,
        mach_msg_type_number_t *infoCnt,
        mach_port_t *object_name
    );
    kern_return_t mach_vm_read_overwrite(
        vm_map_t target_task,
        mach_vm_address_t address,
        mach_vm_size_t size,
        mach_vm_address_t data,
        mach_vm_size_t *outsize
    );
    kern_return_t mach_vm_write(
        vm_map_t target_task,
        mach_vm_address_t address,
        vm_offset_t data,
        mach_msg_type_number_t dataCnt
    );
    kern_return_t mach_vm_allocate(
        vm_map_t target,
        mach_vm_address_t *address,
        mach_vm_size_t size,
        int flags
    );
#ifdef __cplusplus
}
#endif

extern int GetGameProcesspid(char *name);

// ---------- Forward declarations ----------
void ClearProBoxScreenForPawn(uint64_t pawn);

static inline bool IsZeroVec(const Vector3 &v);
Vector3 GetAimTargetPosMode(uint64_t pawn, int posMode, float distance);
Quaternion GetRotationToLocation(Vector3 targetLocation, float y_bias, Vector3 myLoc);
void update_aim_assist_legit_tuning(bool enable);
static void write_aim_rotations(uint64_t player, const Quaternion &out);
static Vector3 AimTrackAndLead(uint64_t pawn, Vector3 bodyPos, float distanceMeters, bool lockYToBody);
static Vector3 AimTrackAndLeadEx(uint64_t pawn, Vector3 bodyPos, float distanceMeters, bool lockYToBody, bool bulletLead);
static inline Vector3 AimCameraOrigin(uint64_t localPawn, const Vector3 &fallback);
static inline Vector3 ResolveHeadWorldPosTracked(uint64_t pawn);
static inline Vector3 ReadPlayerRootTransform(uint64_t pawn);
static inline bool looksLikeWorldPos(const Vector3 &p);
static float esp_aim_delta_time(void);
static inline int PosTrackSlot(uint64_t pawn);
bool get_IsBot(uint64_t player);
bool get_IsVisible(uint64_t player);
bool get_IsFPPVisible(uint64_t player);
static inline uint32_t get_VisibleFlags(uint64_t player);

// ---------- Silent aim state ----------
bool isAimBehindWall = NO;

static void SilentAimClearTarget(void);
static uint64_t gAimLockTarget = 0;
static int gAimLockLostFrames = 0;
static int s_lockHoldFrames = 0;
static uint64_t s_lastAimPawn = 0;

static int g_aimVisSampled = 0;
static int g_aimVisNonZero = 0;
static int g_aimVisCameraTrue = 0;
static int g_aimVisPvsTrue = 0;

static inline bool AimBehindWallNow(void) { return isAimBehindWall; }
static inline bool AimThroughAnyCoverNow(void) { return isAimBehindWall; }

extern "C" void ESPSetAimBehindWallLive(bool behindWall) {
    if (isAimBehindWall != behindWall) {
        gAimLockTarget = 0;
        gAimLockLostFrames = 0;
        SilentAimClearTarget();
    }
    isAimBehindWall = behindWall;
}

static inline void AimVisFrameBegin(void) {
    g_aimVisSampled = 0;
    g_aimVisNonZero = 0;
    g_aimVisCameraTrue = 0;
    g_aimVisPvsTrue = 0;
}

// ---------- Constants ----------
static const uint64_t kGmpHitPointOff  = 0x28;
static const uint64_t kGmpOriginOff    = 0x4C;
static const uint64_t kSilentDirOff    = 0x40;
static const uint64_t kSilentOriginOff = 0x4C;

static inline uint64_t kLastAimingTargetFromWeaponOff(void) {
    uint64_t off = kLastAimingTargetFromWeapon;
    return off ? off : (GameTargetIsMax() ? 0xDE8ull : 0xDE0ull);
}

// ---------- Weapon raycast ----------
struct GameWeaponRaycast {
    bool valid = false;
    Vector3 origin{};
    Vector3 hit{};
};

// ============================================================
// esp.mm — Part 2/8
// Raycast + wall check + visibility helpers
// ============================================================

static inline GameWeaponRaycast SampleLocalWeaponRaycast(uint64_t localPawn, const Vector3 &fallbackOrigin) {
    GameWeaponRaycast out;
    if (!isVaildPtr(localPawn)) return out;
    const uint64_t slots[2] = { (uint64_t)kHitObjectInfo, (uint64_t)kHitObjectInfoAlt };
    for (int i = 0; i < 2; i++) {
        if (!slots[i]) continue;
        uint64_t info = ReadAddr<uint64_t>(localPawn + slots[i]);
        if (!isVaildPtr(info)) continue;
        Vector3 hit = ReadAddr<Vector3>(info + kGmpHitPointOff);
        Vector3 origin = ReadAddr<Vector3>(info + kGmpOriginOff);
        if (!looksLikeWorldPos(hit)) continue;
        if (!looksLikeWorldPos(origin)) origin = fallbackOrigin;
        if (!looksLikeWorldPos(origin)) continue;
        if (fabsf(hit.x) < 0.05f && fabsf(hit.y) < 0.05f && fabsf(hit.z) < 0.05f) continue;
        out.valid = true;
        out.origin = origin;
        out.hit = hit;
        return out;
    }
    return out;
}

static inline bool RaycastHitNearTarget(const GameWeaponRaycast &rc, const Vector3 &targetPos) {
    if (!rc.valid || !looksLikeWorldPos(targetPos)) return false;
    const float hitToEnemy = Vector3::Distance(rc.hit, targetPos);
    const float distEnemy = Vector3::Distance(rc.origin, targetPos);
    const float distHit = Vector3::Distance(rc.origin, rc.hit);
    if (distEnemy > 0.60f && distHit + 0.70f < distEnemy) return false;
    if (hitToEnemy <= 1.45f) return true;
    if (distHit + 0.20f >= distEnemy && hitToEnemy <= 1.85f) return true;
    if (distEnemy < 0.45f && hitToEnemy <= 1.50f) return true;
    return false;
}

static inline bool AimAssistObjectHasEnemy(uint64_t aa, uint64_t enemy) {
    if (!isVaildPtr(aa) || !isVaildPtr(enemy)) return false;
    const uint64_t candOffs[2] = { 0x10, 0x18 };
    for (uint64_t co : candOffs) {
        uint64_t cand = ReadAddr<uint64_t>(aa + co);
        if (!isVaildPtr(cand)) continue;
        uint64_t tgt = ReadAddr<uint64_t>(cand + 0x18);
        if (tgt == enemy) return true;
    }
    uint64_t list = ReadAddr<uint64_t>(aa + 0x20);
    if (isVaildPtr(list)) {
        int n = ReadAddr<int>(list + 0x18);
        uint64_t items = ReadAddr<uint64_t>(list + 0x10);
        if (isVaildPtr(items) && n > 0 && n < 32) {
            for (int i = 0; i < n; i++) {
                uint64_t cand = ReadAddr<uint64_t>(items + 0x20 + (uint64_t)i * 8);
                if (!isVaildPtr(cand)) continue;
                uint64_t tgt = ReadAddr<uint64_t>(cand + 0x18);
                if (tgt == enemy) return true;
            }
        }
    }
    return false;
}

static inline bool AimAssistTargetIsEnemy(uint64_t localPawn, uint64_t enemy) {
    if (!isVaildPtr(localPawn) || !isVaildPtr(enemy)) return false;
    return AimAssistObjectHasEnemy(ReadAddr<uint64_t>(localPawn + kAimAssistPtr), enemy);
}

static inline bool IceWallAimAssistTargetIsEnemy(uint64_t localPawn, uint64_t enemy) {
    if (!isVaildPtr(localPawn) || !isVaildPtr(enemy)) return false;
    uint64_t iceAa = ReadAddr<uint64_t>(localPawn + kAimAssistIceWallPtr);
    return AimAssistObjectHasEnemy(iceAa, enemy);
}

static inline bool LastWeaponTargetIsEnemy(uint64_t localPawn, uint64_t enemy) {
    if (!isVaildPtr(localPawn) || !isVaildPtr(enemy)) return false;
    uint64_t t = ReadAddr<uint64_t>(localPawn + kLastAimingTargetFromWeaponOff());
    return isVaildPtr(t) && t == enemy;
}

static GameWeaponRaycast g_frameWeaponRaycast;
static uint64_t g_frameWeaponRaycastLocal = 0;

static inline void AimWallOffFrameBegin(uint64_t localPawn, const Vector3 &localOrigin) {
    g_frameWeaponRaycast = SampleLocalWeaponRaycast(localPawn, localOrigin);
    g_frameWeaponRaycastLocal = localPawn;
    g_aimVisSampled = 0;
    g_aimVisNonZero = 0;
    g_aimVisCameraTrue = 0;
    g_aimVisPvsTrue = 0;
}

static inline bool GameClearLosToEnemy(uint64_t localPawn, uint64_t enemy, const Vector3 &enemyPos) {
    if (AimThroughAnyCoverNow()) return true;
    if (!isVaildPtr(localPawn) || !isVaildPtr(enemy) || !looksLikeWorldPos(enemyPos)) return false;
    GameWeaponRaycast rc = g_frameWeaponRaycast;
    if (g_frameWeaponRaycastLocal != localPawn) {
        rc = SampleLocalWeaponRaycast(localPawn, enemyPos);
    }
    if (RaycastHitNearTarget(rc, enemyPos)) return true;
    if (rc.valid && looksLikeWorldPos(rc.origin) && looksLikeWorldPos(rc.hit)) {
        const float dxE = enemyPos.x - rc.origin.x;
        const float dyE = enemyPos.y - rc.origin.y;
        const float dzE = enemyPos.z - rc.origin.z;
        const float dxH = rc.hit.x - rc.origin.x;
        const float dyH = rc.hit.y - rc.origin.y;
        const float dzH = rc.hit.z - rc.origin.z;
        const float distEnemy = sqrtf(dxE * dxE + dyE * dyE + dzE * dzE);
        const float distHit = sqrtf(dxH * dxH + dyH * dyH + dzH * dzH);
        if (distEnemy > 1.35f && distHit > 0.30f && distHit + 1.10f < distEnemy) {
            const float invE = 1.0f / distEnemy;
            const float invH = 1.0f / distHit;
            const float dot = (dxE * invE) * (dxH * invH)
                            + (dyE * invE) * (dyH * invH)
                            + (dzE * invE) * (dzH * invH);
            if (dot > 0.87f) return false;
        }
    }
    if (IceWallAimAssistTargetIsEnemy(localPawn, enemy)) return false;
    if (LastWeaponTargetIsEnemy(localPawn, enemy)) return true;
    return true;
}

static inline bool AimHasPositiveLos(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    const uint32_t f = get_VisibleFlags(player);
    g_aimVisSampled++;
    if (f != 0) g_aimVisNonZero++;
    if (f & (uint32_t)kISVisibleCamera) g_aimVisCameraTrue++;
    if (f & (uint32_t)kISVisibleDynamicPVS) g_aimVisPvsTrue++;
    return true;
}

static inline bool AimVisFlagsAliveThisFrame(void) { return g_aimVisNonZero > 0; }
static inline bool AimVisPvsAliveThisFrame(void) { return g_aimVisPvsTrue > 0; }

static inline bool AimTargetVisibleForWallOff(uint64_t player) {
    if (AimThroughAnyCoverNow()) return true;
    if (!isVaildPtr(player) || !isVaildPtr(g_frameWeaponRaycastLocal)) return false;
    if (IceWallAimAssistTargetIsEnemy(g_frameWeaponRaycastLocal, player)) return false;
    if (LastWeaponTargetIsEnemy(g_frameWeaponRaycastLocal, player)) return true;
    return true;
}

// Silent luôn cho phép, độc lập wall
static inline bool AimTargetVisibleStrictForSilent(uint64_t player) {
    (void)player;
    return true;
}

// ============================================================
// esp.mm — Part 3/8
// Position resolve helpers
// ============================================================

static inline Vector3 tryTransformPos(uint64_t nodeOrTf) {
    if (!isVaildPtr(nodeOrTf)) return Vector3{0, 0, 0};
    Vector3 p = getPositionExt(nodeOrTf);
    if (!IsZeroVec(p)) return p;
    uint64_t inner = ReadAddr<uint64_t>(nodeOrTf + kBodyPartTransNode);
    if (isVaildPtr(inner) && inner != nodeOrTf) {
        p = getPositionExt(inner);
        if (!IsZeroVec(p)) return p;
    }
    return Vector3{0, 0, 0};
}

static inline bool looksLikeWorldPos(const Vector3 &p) {
    if (IsZeroVec(p)) return false;
    if (isnan(p.x) || isnan(p.y) || isnan(p.z)) return false;
    if (fabsf(p.x) > 20000.f || fabsf(p.y) > 20000.f || fabsf(p.z) > 20000.f) return false;
    return true;
}

static inline Vector3 tryComponentOrGoPos(uint64_t compOrGo) {
    if (!isVaildPtr(compOrGo)) return Vector3{0, 0, 0};
    Vector3 p = tryTransformPos(compOrGo);
    if (looksLikeWorldPos(p)) return p;
    const uint64_t offs[] = { 0x10, 0x30, 0x38, 0x48, 0x50, 0x60 };
    for (uint64_t off : offs) {
        uint64_t t = ReadAddr<uint64_t>(compOrGo + off);
        p = tryTransformPos(t);
        if (looksLikeWorldPos(p)) return p;
        if (isVaildPtr(t)) {
            p = tryTransformPos(ReadAddr<uint64_t>(t + 0x10));
            if (looksLikeWorldPos(p)) return p;
        }
    }
    return Vector3{0, 0, 0};
}

static inline Vector3 ResolveVehicleWorldPos(uint64_t vehicle) {
    if (!isVaildPtr(vehicle)) return Vector3{0, 0, 0};
    uint64_t driverSeat = ReadAddr<uint64_t>(vehicle + 0x140);
    Vector3 p = tryComponentOrGoPos(driverSeat);
    if (looksLikeWorldPos(p)) return p;
    uint64_t passArr = ReadAddr<uint64_t>(vehicle + 0x148);
    if (isVaildPtr(passArr)) {
        int n = ReadAddr<int>(passArr + 0x18);
        if (n > 0 && n < 8) {
            for (int i = 0; i < n; i++) {
                uint64_t seatGo = ReadAddr<uint64_t>(passArr + 0x20 + (uint64_t)i * 8);
                p = tryComponentOrGoPos(seatGo);
                if (looksLikeWorldPos(p)) return p;
            }
        }
    }
    const uint64_t posOffs[] = {
        kVehicleCachedPosA, kVehicleCachedPosB, kVehicleCachedPosC,
        0x238, 0x250, 0x25C
    };
    for (uint64_t off : posOffs) {
        Vector3 v = ReadAddr<Vector3>(vehicle + off);
        if (looksLikeWorldPos(v)) return v;
    }
    p = tryComponentOrGoPos(ReadAddr<uint64_t>(vehicle + kVehicleRigidBody));
    if (looksLikeWorldPos(p)) return p;
    p = tryComponentOrGoPos(ReadAddr<uint64_t>(vehicle + kVehicleLevelVehicle));
    if (looksLikeWorldPos(p)) return p;
    p = tryTransformPos(ReadAddr<uint64_t>(vehicle + 0x168));
    if (looksLikeWorldPos(p)) return p;
    p = tryTransformPos(ReadAddr<uint64_t>(vehicle + 0x330));
    if (looksLikeWorldPos(p)) return p;
    const uint64_t tfProbe[] = { 0x10, 0x30, 0x38, 0x60, 0x70, 0x98, 0xB8, 0xC0 };
    for (uint64_t off : tfProbe) {
        p = tryComponentOrGoPos(ReadAddr<uint64_t>(vehicle + off));
        if (looksLikeWorldPos(p)) return p;
    }
    return Vector3{0, 0, 0};
}

static inline Vector3 ResolveStropWorldPos(uint64_t strop) {
    if (!isVaildPtr(strop)) return Vector3{0, 0, 0};
    Vector3 a = tryTransformPos(ReadAddr<uint64_t>(strop + kLevelStropStartPoint));
    Vector3 b = tryTransformPos(ReadAddr<uint64_t>(strop + kLevelStropEndPoint));
    if (looksLikeWorldPos(a) && looksLikeWorldPos(b)) {
        return Vector3((a.x + b.x) * 0.5f, (a.y + b.y) * 0.5f + 0.8f, (a.z + b.z) * 0.5f);
    }
    if (looksLikeWorldPos(a)) { a.y += 0.8f; return a; }
    if (looksLikeWorldPos(b)) { b.y += 0.8f; return b; }
    Vector3 p = tryTransformPos(ReadAddr<uint64_t>(strop + kBaseLevelObjectGameObject));
    if (looksLikeWorldPos(p)) return p;
    const uint64_t tfProbe[] = { 0x10, 0x30 };
    for (uint64_t off : tfProbe) {
        p = tryTransformPos(ReadAddr<uint64_t>(strop + off));
        if (looksLikeWorldPos(p)) return p;
    }
    return Vector3{0, 0, 0};
}

static inline uint64_t ReadVehicleIAmIn(uint64_t pawn) {
    if (!isVaildPtr(pawn)) return 0;
    uint64_t primary = kVehicleIAmIn ? kVehicleIAmIn : 0x8A8;
    uint64_t v = ReadAddr<uint64_t>(pawn + primary);
    if (isVaildPtr(v) && v != pawn) return v;
    uint64_t alt = (primary == 0x8A8) ? 0x8B0 : 0x8A8;
    if (alt != primary) {
        v = ReadAddr<uint64_t>(pawn + alt);
        if (isVaildPtr(v) && v != pawn) return v;
    }
    return 0;
}

static inline uint64_t ReadStropIAmOn(uint64_t pawn) {
    if (!isVaildPtr(pawn)) return 0;
    uint64_t primary = kLevelStropIAmOn ? kLevelStropIAmOn : 0x8C0;
    uint64_t s = ReadAddr<uint64_t>(pawn + primary);
    if (isVaildPtr(s) && s != pawn) return s;
    uint64_t alt = (primary == 0x8C0) ? 0x8C8 : 0x8C0;
    if (alt != primary) {
        s = ReadAddr<uint64_t>(pawn + alt);
        if (isVaildPtr(s) && s != pawn) return s;
    }
    return 0;
}

static inline Vector3 ReadPlayerRootTransform(uint64_t pawn) {
    if (!isVaildPtr(pawn)) return Vector3{0, 0, 0};
    const uint64_t tfOffs[] = {
        kPlayerTransform ? kPlayerTransform : 0x698,
        0x698, 0x6A0
    };
    for (uint64_t off : tfOffs) {
        if (!off) continue;
        Vector3 p = tryTransformPos(ReadAddr<uint64_t>(pawn + off));
        if (looksLikeWorldPos(p)) return p;
    }
    return Vector3{0, 0, 0};
}

static inline bool IsActivelyMounted(uint64_t pawn, Vector3 *outMountPos = nullptr) {
    if (outMountPos) *outMountPos = Vector3{0, 0, 0};
    if (!isVaildPtr(pawn)) return false;
    Vector3 root = ReadPlayerRootTransform(pawn);
    Vector3 head = tryTransformPos(getHead(pawn));
    Vector3 hip  = tryTransformPos(getHip(pawn));
    Vector3 live = looksLikeWorldPos(root) ? root
                 : (looksLikeWorldPos(hip) ? hip
                 : (looksLikeWorldPos(head) ? head : Vector3{0, 0, 0}));
    const bool bonesDead = !looksLikeWorldPos(head) && !looksLikeWorldPos(hip);
    const bool bonesCollapsed = looksLikeWorldPos(head) && looksLikeWorldPos(hip) &&
                                Vector3::Distance(head, hip) < 0.22f;
    uint64_t vehicle = ReadVehicleIAmIn(pawn);
    if (vehicle) {
        Vector3 vp = ResolveVehicleWorldPos(vehicle);
        const bool haveVp = looksLikeWorldPos(vp);
        const bool haveLive = looksLikeWorldPos(live);
        if (haveLive && haveVp && !bonesDead && !bonesCollapsed) {
            float dx = live.x - vp.x, dy = live.y - vp.y, dz = live.z - vp.z;
            float d2 = dx*dx + dy*dy + dz*dz;
            if (d2 > 36.0f * 36.0f) return false;
        }
        if (haveLive && !bonesDead && !bonesCollapsed) {
            if (outMountPos) { Vector3 o = live; o.y += 0.75f; *outMountPos = o; }
            return true;
        }
        if (haveVp) {
            if (outMountPos) { Vector3 o = vp; o.y += 0.95f; *outMountPos = o; }
            return true;
        }
        if (haveLive && outMountPos) {
            Vector3 o = live;
            o.y += 0.75f;
            *outMountPos = o;
        }
        return true;
    }
    uint64_t strop = ReadStropIAmOn(pawn);
    if (strop) {
        Vector3 sp = ResolveStropWorldPos(strop);
        if (looksLikeWorldPos(live)) {
            if (!looksLikeWorldPos(sp)) {
                if (outMountPos) { Vector3 o = live; o.y += 0.75f; *outMountPos = o; }
                return true;
            }
            float dx = live.x - sp.x, dy = live.y - sp.y, dz = live.z - sp.z;
            float d2 = dx*dx + dy*dy + dz*dz;
            if (d2 <= 22.0f * 22.0f) {
                if (outMountPos) { Vector3 o = live; o.y += 0.75f; *outMountPos = o; }
                return true;
            }
            return false;
        }
        if (looksLikeWorldPos(sp)) {
            if (outMountPos) *outMountPos = sp;
            return true;
        }
        return false;
    }
    return false;
}

static inline Vector3 ResolvePawnWorldPosAny(uint64_t pawn) {
    if (!isVaildPtr(pawn)) return Vector3{0, 0, 0};
    Vector3 p{};
    Vector3 mountPos{};
    const bool mounted = IsActivelyMounted(pawn, &mountPos);
    p = ReadPlayerRootTransform(pawn);
    if (looksLikeWorldPos(p)) return p;
    p = tryTransformPos(getHip(pawn));
    if (looksLikeWorldPos(p)) return p;
    p = tryTransformPos(getHead(pawn));
    if (looksLikeWorldPos(p)) return p;
    if (kRootNode) {
        p = tryTransformPos(ReadAddr<uint64_t>(pawn + kRootNode));
        if (looksLikeWorldPos(p)) return p;
    }
    p = tryTransformPos(getLeftShoulder(pawn));
    if (looksLikeWorldPos(p)) return p;
    p = tryTransformPos(getRightShoulder(pawn));
    if (looksLikeWorldPos(p)) return p;
    if (mounted && looksLikeWorldPos(mountPos)) return mountPos;
    {
        uint64_t capHuman = ReadAddr<uint64_t>(pawn + 0xAA8);
        p = tryComponentOrGoPos(capHuman);
        if (looksLikeWorldPos(p)) return p;
        if (isVaildPtr(capHuman)) {
            p = tryComponentOrGoPos(ReadAddr<uint64_t>(capHuman + 0x28));
            if (looksLikeWorldPos(p)) return p;
        }
        uint64_t capCol = ReadAddr<uint64_t>(pawn + 0xAB0);
        p = tryComponentOrGoPos(capCol);
        if (looksLikeWorldPos(p)) return p;
    }
    if (mounted && looksLikeWorldPos(mountPos)) return mountPos;
    {
        Vector3 mount2{};
        if (IsActivelyMounted(pawn, &mount2) && looksLikeWorldPos(mount2)) return mount2;
    }
    {
        uint64_t followCam = ReadAddr<uint64_t>(pawn + kFollowCameraObj);
        p = tryComponentOrGoPos(followCam);
        if (looksLikeWorldPos(p)) return p;
    }
    if (kMainCameraTransform) {
        p = tryTransformPos(ReadAddr<uint64_t>(pawn + kMainCameraTransform));
        if (looksLikeWorldPos(p)) return p;
    }
    return Vector3{0, 0, 0};
}

// ============================================================
// esp.mm — Part 4/8
// Head/hip resolve + AimLookAtHeadLive
// ============================================================

static inline Vector3 ResolveHeadWorldPosTracked(uint64_t pawn);
static inline Vector3 ResolveHipWorldPosTracked(uint64_t pawn);

Vector3 ResolvePawnWorldPosForESP(uint64_t pawn) {
    Vector3 hip = ResolveHipWorldPosTracked(pawn);
    if (looksLikeWorldPos(hip)) return hip;
    return ResolvePawnWorldPosAny(pawn);
}

static inline Vector3 ResolveHeadWorldPos(uint64_t pawn, bool /*unused*/ = false) {
    return ResolveHeadWorldPosTracked(pawn);
}

Vector3 ResolveHeadWorldPosForESP(uint64_t pawn) {
    return ResolveHeadWorldPosTracked(pawn);
}

static inline Vector3 ResolveAimHeadWorldPos(uint64_t pawn) {
    Vector3 tracked = ResolveHeadWorldPosTracked(pawn);
    if (looksLikeWorldPos(tracked)) return tracked;
    if (!isVaildPtr(pawn)) return Vector3{0, 0, 0};
    Vector3 head = getPositionExt(getHead(pawn));
    Vector3 hip = getPositionExt(getHip(pawn));
    if (!IsZeroVec(head)) {
        if (!IsZeroVec(hip)) {
            if (head.y < hip.y - 0.35f) {
            } else {
                float dx = head.x - hip.x, dy = head.y - hip.y, dz = head.z - hip.z;
                float distSq = dx * dx + dy * dy + dz * dz;
                if (distSq <= 4.5f * 4.5f) return head;
            }
        } else {
            return head;
        }
    }
    if (!IsZeroVec(hip)) {
        hip.y += 0.50f;
        return hip;
    }
    Vector3 any = ResolvePawnWorldPosAny(pawn);
    if (!IsZeroVec(any)) {
        any.y += 0.50f;
        return any;
    }
    return Vector3{0, 0, 0};
}

static inline void AimLookAtHead(uint64_t localPawn, const Vector3 &headPos, const Vector3 &fromLoc, int bursts = 2) {
    if (!isVaildPtr(localPawn) || IsZeroVec(headPos) || IsZeroVec(fromLoc)) return;
    Quaternion q = Quaternion::Normalized(GetRotationToLocation(headPos, 0.0f, fromLoc));
    if (isnan(q.x) || isnan(q.y) || isnan(q.z) || isnan(q.w)) return;
    update_aim_assist_legit_tuning(false);
    DisableGameDefaultAimAssist(localPawn, true);
    if (bursts < 2) bursts = 2;
    if (bursts > 48) bursts = 48;
    for (int i = 0; i < bursts; i++) {
        write_aim_rotations(localPawn, q);
    }
}

static inline Vector3 AimCameraOrigin(uint64_t localPawn, const Vector3 &fallback) {
    if (!isVaildPtr(localPawn)) return fallback;
    uint64_t camTf = ReadAddr<uint64_t>(localPawn + kMainCameraTransform);
    if (isVaildPtr(camTf)) {
        Vector3 p = getPositionExt(camTf);
        if (looksLikeWorldPos(p)) return p;
    }
    if (looksLikeWorldPos(fallback)) return fallback;
    Vector3 lh = tryTransformPos(getHead(localPawn));
    if (looksLikeWorldPos(lh)) return lh;
    return fallback;
}

// ---------- Silent aim thread-safe state ----------
static std::mutex        g_silentMtx;
static std::atomic<bool> g_silentKeepRunning{false};
static std::thread       g_silentThread;
static Vector3           g_silentTargetPos{0, 0, 0};
static Vector3           g_silentFromLoc{0, 0, 0};
static bool              g_silentHasTarget = false;
static uint64_t          g_silentLockedEnemy = 0;
static uint64_t          g_silentLocalPlayer = 0;
static int               g_silentAimPosMode = 0;
static uint64_t          g_lastAimingInfo = 0;
static uint64_t          g_silentCachedInfo = 0;

static inline void SilentFillPrimaryOnly(uint64_t *out, int *outCount) {
    out[0] = kHitObjectInfo;
    out[1] = kHitObjectInfoAlt;
    *outCount = 2;
}

static inline Vector3 ResolveSilentHeadWorldPos(uint64_t pawn) {
    if (!isVaildPtr(pawn)) return Vector3{0, 0, 0};
    Vector3 head = getPositionExt(getHead(pawn));
    if (looksLikeWorldPos(head) && !IsZeroVec(head)) {
        Vector3 hip = getPositionExt(getHip(pawn));
        if (looksLikeWorldPos(hip)) {
            float dx = head.x - hip.x, dy = head.y - hip.y, dz = head.z - hip.z;
            float d2 = dx*dx + dy*dy + dz*dz;
            if (d2 < 6.0f * 6.0f && head.y >= hip.y - 0.5f)
                return head;
        } else {
            return head;
        }
    }
    head = getPositionExt(getHead(pawn));
    if (looksLikeWorldPos(head) && !IsZeroVec(head)) return head;
    head = ResolveAimHeadWorldPos(pawn);
    if (looksLikeWorldPos(head) && !IsZeroVec(head)) return head;
    return Vector3{0, 0, 0};
}

static inline Vector3 ResolveSilentAimWorldPos(uint64_t pawn, int posMode) {
    if (!isVaildPtr(pawn)) return Vector3{0, 0, 0};
    if (posMode < 0) posMode = 0;
    if (posMode > 2) posMode = 2;
    if (posMode == 0) {
        return ResolveSilentHeadWorldPos(pawn);
    }
    Vector3 bone = GetAimTargetPosMode(pawn, posMode, 0.0f);
    if (!IsZeroVec(bone) && looksLikeWorldPos(bone)) return bone;
    Vector3 head = ResolveSilentHeadWorldPos(pawn);
    if (IsZeroVec(head) || !looksLikeWorldPos(head)) return Vector3{0, 0, 0};
    Vector3 hip = getPositionExt(getHip(pawn));
    if (looksLikeWorldPos(hip) && !IsZeroVec(hip)) {
        const float t = (posMode == 1) ? 0.22f : 0.52f;
        return Vector3(head.x + (hip.x - head.x) * t,
                       head.y + (hip.y - head.y) * t,
                       head.z + (hip.z - head.z) * t);
    }
    head.y -= (posMode == 1) ? 0.12f : 0.32f;
    return head;
}

static inline void ZeroWeaponScatterForAim(uint64_t localPawn) {
    if (!isVaildPtr(localPawn)) return;
    uint64_t weapon = ReadAddr<uint64_t>(localPawn + kActiveWeapon);
    if (!isVaildPtr(weapon)) {
        uint64_t inv = ReadAddr<uint64_t>(localPawn + kWeaponHolder);
        if (isVaildPtr(inv)) weapon = ReadAddr<uint64_t>(inv + kHolderActiveWeapon);
    }
    if (!isVaildPtr(weapon)) return;
    uint64_t rep = ReadAddr<uint64_t>(weapon + kWeaponRepItem);
    if (!isVaildPtr(rep)) return;
    WriteAddr<float>(rep + 0x194, 0.0f);
    WriteAddr<float>(rep + 0x198, 0.0f);
    WriteAddr<float>(rep + 0x1E0, 0.0f);
    WriteAddr<float>(rep + 0x1E4, 0.0f);
    WriteAddr<float>(rep + 0x1EC, 0.0f);
    WriteAddr<float>(rep + 0x190, 0.0f);
    WriteAddr<float>(rep + 0x19C, 0.0f);
    WriteAddr<float>(rep + 0x1E8, 0.0f);
}

static Vector3 g_silentLastLiveOrigin{0, 0, 0};

static inline bool SilentWriteAimingDir(uint64_t aimingInfo, const Vector3 &targetPos, const Vector3 & /*fromFallback*/) {
    if (!isVaildPtr(aimingInfo) || IsZeroVec(targetPos)) return false;
    Vector3 startPos = ReadAddr<Vector3>(aimingInfo + kSilentOriginOff);
    if (!IsZeroVec(startPos)) {
        g_silentLastLiveOrigin = startPos;
    } else if (!IsZeroVec(g_silentLastLiveOrigin)) {
        startPos = g_silentLastLiveOrigin;
    } else {
        return false;
    }
    Vector3 dir;
    dir.x = targetPos.x - startPos.x;
    dir.y = targetPos.y - startPos.y;
    dir.z = targetPos.z - startPos.z;
    float mag = sqrtf(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z);
    if (mag <= 0.0001f) return false;
    dir.x /= mag; dir.y /= mag; dir.z /= mag;
    WriteAddr<Vector3>(aimingInfo + kSilentDirOff, dir);
    Vector3 start2 = ReadAddr<Vector3>(aimingInfo + kSilentOriginOff);
    if (!IsZeroVec(start2)) {
        g_silentLastLiveOrigin = start2;
        if (fabsf(start2.x - startPos.x) > 0.0005f ||
            fabsf(start2.y - startPos.y) > 0.0005f ||
            fabsf(start2.z - startPos.z) > 0.0005f) {
            dir.x = targetPos.x - start2.x;
            dir.y = targetPos.y - start2.y;
            dir.z = targetPos.z - start2.z;
            mag = sqrtf(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z);
            if (mag > 0.0001f) {
                dir.x /= mag; dir.y /= mag; dir.z /= mag;
            }
        }
    }
    WriteAddr<Vector3>(aimingInfo + kSilentDirOff, dir);
    return true;
}

static inline int SilentForcePrimary(uint64_t localPawn, const Vector3 &fromLoc, const Vector3 &targetPos) {
    if (!isVaildPtr(localPawn) || IsZeroVec(targetPos)) return 0;
    int wrote = 0;
    if (isVaildPtr(g_silentCachedInfo)) {
        if (SilentWriteAimingDir(g_silentCachedInfo, targetPos, fromLoc)) {
            wrote++;
            g_lastAimingInfo = g_silentCachedInfo;
        } else if (!isVaildPtr(g_silentCachedInfo)) {
            g_silentCachedInfo = 0;
        }
    }
    uint64_t offs[2];
    int n = 0;
    SilentFillPrimaryOnly(offs, &n);
    for (int i = 0; i < n; i++) {
        uint64_t aimingInfo = ReadAddr<uint64_t>(localPawn + offs[i]);
        if (!isVaildPtr(aimingInfo)) continue;
        g_silentCachedInfo = aimingInfo;
        if (SilentWriteAimingDir(aimingInfo, targetPos, fromLoc)) {
            g_lastAimingInfo = aimingInfo;
            wrote++;
        }
    }
    return wrote;
}

static inline void AimSyncFireHit(uint64_t localPawn, const Vector3 &fromLoc, const Vector3 &targetPos) {
    (void)SilentForcePrimary(localPawn, fromLoc, targetPos);
}

// ---------- Silent thread — AN TOÀN, có sleep, có stop flag ----------
static void SilentAimThread(uint64_t localPlayer) {
    while (g_silentKeepRunning.load(std::memory_order_relaxed)) {
        bool hasTarget = false;
        Vector3 targetPos{0, 0, 0};
        Vector3 fromLoc{0, 0, 0};
        uint64_t lp = 0;
        uint64_t enemy = 0;
        int posMode = 0;
        {
            std::lock_guard<std::mutex> lk(g_silentMtx);
            hasTarget = g_silentHasTarget;
            targetPos = g_silentTargetPos;
            fromLoc = g_silentFromLoc;
            lp = g_silentLocalPlayer ? g_silentLocalPlayer : localPlayer;
            enemy = g_silentLockedEnemy;
            posMode = g_silentAimPosMode;
        }
        if (hasTarget && isVaildPtr(lp)) {
            if (isVaildPtr(enemy)) {
                Vector3 live = ResolveSilentAimWorldPos(enemy, posMode);
                if (!IsZeroVec(live)) {
                    targetPos = live;
                    std::lock_guard<std::mutex> lk(g_silentMtx);
                    g_silentTargetPos = live;
                }
            }
            if (!IsZeroVec(targetPos)) {
                // Giảm từ 10 → 2 để tránh write quá nhiều
                for (int i = 0; i < 2; i++) {
                    SilentForcePrimary(lp, fromLoc, targetPos);
                }
            }
        } else {
            g_lastAimingInfo = 0;
        }
        // Sleep 2ms — tránh CPU 100% → tránh tắt nguồn do nhiệt
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
}

static void SilentAimSetTarget(uint64_t localPlayer, uint64_t enemy, const Vector3 &bonePos, const Vector3 &fromLoc, int posMode) {
    if (!isVaildPtr(localPlayer) || IsZeroVec(bonePos)) return;
    if (posMode < 0) posMode = 0;
    if (posMode > 2) posMode = 2;
    {
        std::lock_guard<std::mutex> lk(g_silentMtx);
        g_silentTargetPos = bonePos;
        g_silentFromLoc = fromLoc;
        g_silentHasTarget = true;
        g_silentLockedEnemy = enemy;
        g_silentLocalPlayer = localPlayer;
        g_silentAimPosMode = posMode;
    }
    SilentForcePrimary(localPlayer, fromLoc, bonePos);
    if (!g_silentKeepRunning.load(std::memory_order_relaxed)) {
        g_silentKeepRunning = true;
        if (g_silentThread.joinable()) {
            try { g_silentThread.join(); } catch (...) {}
        }
        g_silentThread = std::thread(SilentAimThread, localPlayer);
    }
}

static void SilentAimClearTarget(void) {
    std::lock_guard<std::mutex> lk(g_silentMtx);
    g_silentHasTarget = false;
    g_silentLockedEnemy = 0;
    g_silentTargetPos = Vector3{0, 0, 0};
    g_silentFromLoc = Vector3{0, 0, 0};
    g_silentCachedInfo = 0;
    g_silentLastLiveOrigin = Vector3{0, 0, 0};
    g_silentAimPosMode = 0;
}

static void SilentAimStop(void) {
    g_silentKeepRunning = false;
    if (g_silentThread.joinable()) {
        try { g_silentThread.join(); } catch (...) {}
    }
    std::lock_guard<std::mutex> lk(g_silentMtx);
    g_silentHasTarget = false;
    g_silentLockedEnemy = 0;
    g_silentLocalPlayer = 0;
    g_silentTargetPos = Vector3{0, 0, 0};
    g_silentFromLoc = Vector3{0, 0, 0};
    g_lastAimingInfo = 0;
    g_silentCachedInfo = 0;
    g_silentLastLiveOrigin = Vector3{0, 0, 0};
    g_silentAimPosMode = 0;
}

// ---------- Aim lock thread ĐÃ BỎ HOÀN TOÀN ----------
// Ghi rotation chỉ trong updateFrame, không dùng thread riêng.
// => Giảm 1500 write/giây, tránh panic do VM pressure.
static void AimLockSetQuat(uint64_t localPlayer, const Quaternion &q) {
    (void)localPlayer; (void)q;
    // No-op — giữ API cho tương thích
}
static void AimLockSet(uint64_t localPlayer, uint64_t enemy, int posMode, float dist, const Vector3 &fromLoc) {
    (void)localPlayer; (void)enemy; (void)posMode; (void)dist; (void)fromLoc;
}
static void AimLockClear(void) {}
static void AimLockStop(void) {}

// ============================================================
// esp.mm — Part 5/8
// Mono string + prefs sync + geometry buffers
// ============================================================

task_t g_target_task = 0;

uint64_t AllocateMonoString(task_t task, uint64_t originalStrPtr, NSString *nsStr) {
    if (!task || !isVaildPtr(originalStrPtr) || !nsStr) return 0;
    uint64_t klass = ReadAddr<uint64_t>(originalStrPtr);
    if (!isVaildPtr(klass)) return 0;
    NSUInteger len = nsStr.length;
    // Guard: nickname dài quá → tránh alloc lớn → tránh panic
    if (len == 0 || len > 64) return 0;
    mach_vm_address_t newAlloc = 0;
    mach_vm_size_t size = 0x14 + (len * 2) + 2;
    if (mach_vm_allocate(task, &newAlloc, size, VM_FLAGS_ANYWHERE) != KERN_SUCCESS) return 0;
    if (!isVaildPtr((uint64_t)newAlloc)) return 0;
    WriteAddr<uint64_t>(newAlloc, klass);
    WriteAddr<uint64_t>(newAlloc + 0x8, 0);
    WriteAddr<int32_t>(newAlloc + 0x10, (int32_t)len);
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [nsStr characterAtIndex:i];
        WriteAddr<uint16_t>(newAlloc + 0x14 + (i * 2), (uint16_t)c);
    }
    WriteAddr<uint16_t>(newAlloc + 0x14 + (len * 2), 0);
    return newAlloc;
}

NSString* External_ReadNickname(uint64_t playerObj) {
    if (!isVaildPtr(playerObj)) return nil;
    uint64_t strPtr = ReadAddr<uint64_t>(playerObj + (uint64_t)kNickname);
    if (!isVaildPtr(strPtr)) return nil;
    int32_t length = ReadAddr<int32_t>(strPtr + 0x10);
    if (length <= 0 || length > 128) return nil;
    std::vector<uint16_t> buf(length);
    for (int i = 0; i < length; i++) {
        buf[i] = ReadAddr<uint16_t>(strPtr + 0x14 + (i * 2));
    }
    return [NSString stringWithCharacters:(const unichar*)buf.data() length:length];
}

NSString *GenerateRainbowString(NSString *baseStr, int tickOffset) {
    NSArray *hexColors = @[@"FFFF00", @"00FF00"];
    NSMutableString *result = [NSMutableString string];
    NSString *cleanBase = [baseStr stringByReplacingOccurrencesOfString:@"\\[.*?\\]" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, baseStr.length)];
    for (NSUInteger i = 0; i < cleanBase.length; i++) {
        unichar c = [cleanBase characterAtIndex:i];
        if (c == ' ') {
            [result appendFormat:@" "];
        } else {
            int colorIdx = (i + tickOffset) % hexColors.count;
            [result appendFormat:@"[%@]%C", hexColors[colorIdx], c];
        }
    }
    return result;
}

static inline bool IsZeroVec(const Vector3 &v) {
    return v.x == 0.0f && v.y == 0.0f && v.z == 0.0f;
}

// ---------- Motion track ----------
struct AimMotionTrack {
    uint64_t pawn = 0;
    Vector3 lastHip = {0, 0, 0};
    Vector3 lastHead = {0, 0, 0};
    Vector3 vel = {0, 0, 0};
    Vector3 smoothHead = {0, 0, 0};
    CFTimeInterval lastT = 0;
    bool valid = false;
};

static AimMotionTrack g_aimMotion[96];

static AimMotionTrack *AimMotionSlot(uint64_t pawn) {
    if (pawn == 0) return nullptr;
    int slotIdx = PosTrackSlot(pawn);
    AimMotionTrack *slot = &g_aimMotion[slotIdx];
    if (slot->pawn != pawn) {
        *slot = AimMotionTrack{};
        slot->pawn = pawn;
    }
    return slot;
}

static Vector3 AimTrackAndLeadEx(uint64_t pawn, Vector3 bodyPos, float distanceMeters, bool lockYToBody, bool bulletLead) {
    AimMotionTrack *tr = AimMotionSlot(pawn);
    if (!tr) return bodyPos;
    if (!looksLikeWorldPos(bodyPos)) return bodyPos;
    Vector3 hip = getPositionExt(getHip(pawn));
    Vector3 root = ReadPlayerRootTransform(pawn);
    Vector3 motionAnchor = bodyPos;
    if (looksLikeWorldPos(root) && !get_IsBot(pawn)) motionAnchor = root;
    else if (looksLikeWorldPos(hip) && !IsZeroVec(hip)) motionAnchor = hip;
    const CFTimeInterval now = CACurrentMediaTime();
    if (!tr->valid || tr->lastT <= 0.0) {
        tr->lastHip = motionAnchor;
        tr->lastHead = bodyPos;
        tr->smoothHead = bodyPos;
        tr->vel = {0, 0, 0};
        tr->lastT = now;
        tr->valid = true;
        return bodyPos;
    }
    float dt = (float)(now - tr->lastT);
    if (dt < 0.0005f) dt = 0.0005f;
    if (dt > 0.12f) {
        tr->lastHip = motionAnchor;
        tr->lastHead = bodyPos;
        tr->smoothHead = bodyPos;
        tr->vel = {0, 0, 0};
        tr->lastT = now;
        return bodyPos;
    }
    Vector3 instHip = {
        (motionAnchor.x - tr->lastHip.x) / dt,
        0.f,
        (motionAnchor.z - tr->lastHip.z) / dt
    };
    Vector3 instBody = {
        (bodyPos.x - tr->lastHead.x) / dt,
        0.f,
        (bodyPos.z - tr->lastHead.z) / dt
    };
    Vector3 inst = {
        instHip.x * 0.70f + instBody.x * 0.30f,
        0.f,
        instHip.z * 0.70f + instBody.z * 0.30f
    };
    static Vector3 s_instFilt[96] = {};
    int slot = (int)(pawn % 96);
    Vector3 &filt = s_instFilt[slot];
    if (filt.x == 0.f && filt.z == 0.f) {
        filt = inst;
    } else {
        float fa = 0.45f;
        filt.x = filt.x * (1.f - fa) + inst.x * fa;
        filt.z = filt.z * (1.f - fa) + inst.z * fa;
    }
    Vector3 instF = filt;
    float instSpeed = sqrtf(instF.x * instF.x + instF.z * instF.z);
    float alpha = bulletLead
        ? (0.55f + fminf(instSpeed, 12.f) * 0.035f)
        : (0.38f + fminf(instSpeed, 10.f) * 0.025f);
    if (alpha > (bulletLead ? 0.95f : 0.68f)) alpha = bulletLead ? 0.95f : 0.68f;
    tr->vel.x = tr->vel.x * (1.f - alpha) + instF.x * alpha;
    tr->vel.z = tr->vel.z * (1.f - alpha) + instF.z * alpha;
    tr->vel.y = 0.f;
    float speed = sqrtf(tr->vel.x * tr->vel.x + tr->vel.z * tr->vel.z);
    if (speed < (bulletLead ? 0.22f : 0.40f)) {
        tr->vel.x = 0.f;
        tr->vel.z = 0.f;
        speed = 0.f;
    }
    const float maxSpeed = bulletLead ? 14.0f : 11.0f;
    if (speed > maxSpeed) {
        float inv = maxSpeed / speed;
        tr->vel.x *= inv;
        tr->vel.z *= inv;
        speed = maxSpeed;
    }
    tr->smoothHead = bodyPos;
    tr->lastHip = motionAnchor;
    tr->lastHead = bodyPos;
    tr->lastT = now;
    float lead = 0.f;
    if (bulletLead) {
        if (speed > 2.5f) {
            lead = 0.010f + (speed / maxSpeed) * 0.025f;
            if (lead > 0.035f) lead = 0.035f;
        }
    } else if (speed > 1.5f) {
        lead = 0.008f + (speed / maxSpeed) * 0.018f;
        if (lead > 0.025f) lead = 0.025f;
    }
    (void)lockYToBody;
    if (lead <= 0.0001f) return bodyPos;
    Vector3 out = {
        bodyPos.x + tr->vel.x * lead,
        bodyPos.y,
        bodyPos.z + tr->vel.z * lead
    };
    return out;
}

static Vector3 AimTrackAndLead(uint64_t pawn, Vector3 bodyPos, float distanceMeters, bool lockYToBody) {
    return AimTrackAndLeadEx(pawn, bodyPos, distanceMeters, lockYToBody, false);
}

Vector3 GetAimTargetPosMode(uint64_t pawn, int posMode, float distance) {
    (void)distance;
    if (!isVaildPtr(pawn)) return Vector3{0,0,0};
    Vector3 liveHead = getPositionExt(getHead(pawn));
    Vector3 hip = getPositionExt(getHip(pawn));
    Vector3 root = ReadPlayerRootTransform(pawn);
    Vector3 head = liveHead;
    bool headOk = false;
    if (looksLikeWorldPos(liveHead)) {
        Vector3 anchor = looksLikeWorldPos(hip) ? hip : root;
        if (!looksLikeWorldPos(anchor)) {
            headOk = true;
        } else {
            float dx = liveHead.x - anchor.x, dy = liveHead.y - anchor.y, dz = liveHead.z - anchor.z;
            float d2 = dx*dx + dy*dy + dz*dz;
            if (d2 < 6.0f * 6.0f && liveHead.y >= anchor.y - 0.6f) headOk = true;
        }
    }
    if (!headOk) {
        head = getPositionExt(getHead(pawn));
        if (IsZeroVec(head) || !looksLikeWorldPos(head)) {
            Vector3 mount{};
            if (IsActivelyMounted(pawn, &mount) && looksLikeWorldPos(mount)) {
                head = mount;
            } else if (looksLikeWorldPos(root)) {
                head = root;
                head.y += 0.85f;
            } else if (looksLikeWorldPos(hip)) {
                head = hip;
                head.y += 0.55f;
            } else {
                return Vector3{0, 0, 0};
            }
        }
    }
    if (posMode == 0) {
        return head;
    }
    Vector3 hipPos = looksLikeWorldPos(hip) ? hip : Vector3{0, 0, 0};
    if (IsZeroVec(hipPos) || !looksLikeWorldPos(hipPos)) {
        if (looksLikeWorldPos(root)) {
            hipPos = root;
        } else {
            head.y -= (posMode == 1) ? 0.14f : 0.34f;
            return head;
        }
    }
    const float dx = hipPos.x - head.x;
    const float dy = hipPos.y - head.y;
    const float dz = hipPos.z - head.z;
    if (posMode == 1) {
        const float t = 0.22f;
        return Vector3(head.x + dx * t, head.y + dy * t, head.z + dz * t);
    }
    const float t = 0.52f;
    return Vector3(head.x + dx * t, head.y + dy * t, head.z + dz * t);
}

static inline Vector3 AimLookAtHeadLive(uint64_t localPawn, uint64_t targetPawn, int aimPosMode,
                                        float distanceMeters, Vector3 fromFallback, int bursts,
                                        Vector3 *outLastAim, bool freezeOrigin) {
    if (!isVaildPtr(localPawn) || !isVaildPtr(targetPawn)) return Vector3{0, 0, 0};
    (void)bursts;
    (void)freezeOrigin;
    update_aim_assist_legit_tuning(false);
    DisableGameDefaultAimAssist(localPawn, true);
    Vector3 bone = GetAimTargetPosMode(targetPawn, aimPosMode, distanceMeters);
    if (IsZeroVec(bone) || !looksLikeWorldPos(bone)) {
        Vector3 liveHead = getPositionExt(getHead(targetPawn));
        if (looksLikeWorldPos(liveHead)) bone = liveHead;
    }
    if (IsZeroVec(bone) || !looksLikeWorldPos(bone)) {
        if (outLastAim) *outLastAim = Vector3{0, 0, 0};
        return Vector3{0, 0, 0};
    }
    Vector3 aimed = AimTrackAndLeadEx(targetPawn, bone, distanceMeters, true, false);
    if (IsZeroVec(aimed) || !looksLikeWorldPos(aimed)) aimed = bone;
    Vector3 from = AimCameraOrigin(localPawn, fromFallback);
    if (IsZeroVec(from) || !looksLikeWorldPos(from)) from = fromFallback;
    if (IsZeroVec(from) || !looksLikeWorldPos(from)) {
        from = getPositionExt(getHead(localPawn));
    }
    if (IsZeroVec(from) || !looksLikeWorldPos(from)) {
        if (outLastAim) *outLastAim = aimed;
        return aimed;
    }
    Quaternion targetQ = Quaternion::Normalized(GetRotationToLocation(aimed, 0.0f, from));
    if (isnan(targetQ.x) || isnan(targetQ.y) || isnan(targetQ.z) || isnan(targetQ.w)) {
        if (outLastAim) *outLastAim = aimed;
        return aimed;
    }
    Quaternion cur = ReadAddr<Quaternion>(localPawn + kAimRotation);
    float n = cur.x*cur.x + cur.y*cur.y + cur.z*cur.z + cur.w*cur.w;
    Quaternion outQ = targetQ;
    if (isAimLegit && n > 0.0001f && !isnan(n)) {
        cur = Quaternion::Normalized(cur);
        float ang = Quaternion::Angle(cur, targetQ);
        const float kDeadzoneRad = 0.0035f;
        if (ang < kDeadzoneRad) {
            outQ = cur;
        } else {
            float dt = esp_aim_delta_time();
            float rate = 90.0f;
            if (ang > 0.25f)      rate = 240.0f;
            else if (ang > 0.10f) rate = 160.0f;
            else if (ang > 0.04f) rate = 110.0f;
            float alpha = 1.0f - expf(-rate * fmaxf(dt, 0.004f));
            alpha = fminf(alpha, 0.985f);
            outQ = Quaternion::Normalized(Quaternion::Slerp(cur, targetQ, alpha));
            if (isnan(outQ.x) || isnan(outQ.y) || isnan(outQ.z) || isnan(outQ.w)) outQ = targetQ;
        }
    }
    write_aim_rotations(localPawn, outQ);
    AimSyncFireHit(localPawn, from, aimed);
    if (outLastAim) *outLastAim = aimed;
    return aimed;
}

// ============================================================
// esp.mm — Part 6/8
// ESP_View interface + init + layers + dealloc
// ============================================================

@interface HTHESPSecureWrapper : UITextField
@end
@implementation HTHESPSecureWrapper
- (BOOL)canBecomeFirstResponder { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return NO; }
@end

@interface ESP_View ()
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) dispatch_source_t frameTimer;
@property (nonatomic, strong) HTHESPSecureWrapper *secureTextField;
@property (nonatomic, strong) UIView *secureCanvas;

@property (nonatomic, strong) CAShapeLayer *boxLayer;
@property (nonatomic, strong) CAShapeLayer *boxBotLayer;
@property (nonatomic, strong) CAShapeLayer *boxKnockedLayer;
@property (nonatomic, strong) CAShapeLayer *boneLayer;
@property (nonatomic, strong) CAShapeLayer *boneBotLayer;
@property (nonatomic, strong) CAShapeLayer *boneKnockedLayer;
@property (nonatomic, strong) CAShapeLayer *snaplineLayer;
@property (nonatomic, strong) CAShapeLayer *snaplineBotLayer;
@property (nonatomic, strong) CAShapeLayer *snaplineKnockedLayer;
@property (nonatomic, strong) CAShapeLayer *hpFillGreenLayer;
@property (nonatomic, strong) CAShapeLayer *hpFillOrangeLayer;
@property (nonatomic, strong) CAShapeLayer *hpFillRedLayer;
@property (nonatomic, strong) CAShapeLayer *bgFillBlackLayer;
@property (nonatomic, strong) CAShapeLayer *alertLayer;
@property (nonatomic, strong) CAShapeLayer *fovLayer;
@property (nonatomic, strong) CAShapeLayer *aimAssistLayer;

@property (nonatomic, strong) CAShapeLayer *alertNumBGLayer;
@property (nonatomic, strong) CAShapeLayer *alertNumGreenLayer;
@property (nonatomic, strong) CAShapeLayer *alertNumOrangeLayer;
@property (nonatomic, strong) CAShapeLayer *alertNumRedLayer;

@property (nonatomic, strong) NSMutableArray<CATextLayer *> *textLayerPool;
@property (nonatomic, assign) NSUInteger activeTextLayerCount;

@property (nonatomic, strong) NSMutableArray<CALayer *> *imageLayerPool;
@property (nonatomic, assign) NSUInteger activeImageLayerCount;

@property (nonatomic, strong) CATextLayer *statusLayer;
@property (nonatomic, copy) NSString *lastStatusString;

- (void)configureRenderingLayers;
- (void)resetReusableLayers;
- (void)clearAllContent;
- (void)addText:(NSString *)text frame:(CGRect)frame color:(UIColor *)color fontSize:(CGFloat)fontSize leftAligned:(BOOL)leftAligned;
- (void)addImage:(UIImage *)image frame:(CGRect)frame;
@end

@implementation ESP_View

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return NO; }

static void ESPViewAddTextCallback(void *context, NSString *string, CGRect frame, UIColor *color, CGFloat fontSize, BOOL leftAligned) {
    if (!context || !string) return;
    ESP_View *view = (__bridge ESP_View *)context;
    [view addText:string frame:frame color:color fontSize:fontSize leftAligned:leftAligned];
}

static void ESPViewAddImageCallback(void *context, UIImage *image, CGRect frame) {
    if (!context || !image) return;
    ESP_View *view = (__bridge ESP_View *)context;
    [view addImage:image frame:frame];
}

- (void)hideMenu {}
- (void)showMenu {}
- (void)handlePan:(UIPanGestureRecognizer *)gesture {}
- (void)centerMenu {}

- (void)clearAllContent {
    self.boxLayer.path = nil;
    self.boxBotLayer.path = nil; self.boxKnockedLayer.path = nil;
    self.boneLayer.path = nil;
    self.boneBotLayer.path = nil; self.boneKnockedLayer.path = nil;
    self.snaplineLayer.path = nil;
    self.snaplineBotLayer.path = nil; self.snaplineKnockedLayer.path = nil;
    self.hpFillGreenLayer.path = nil; self.hpFillOrangeLayer.path = nil;
    self.hpFillRedLayer.path = nil; self.alertLayer.path = nil; self.fovLayer.path = nil;
    self.bgFillBlackLayer.path = nil; self.aimAssistLayer.path = nil;
    self.alertNumBGLayer.path = nil; self.alertNumGreenLayer.path = nil;
    self.alertNumOrangeLayer.path = nil; self.alertNumRedLayer.path = nil;
    self.statusLayer.hidden = YES;
    [self resetReusableLayers];
}

static void *gEngine = (void *)1;
mach_port_t task;

// ---------- AN TOÀN: heartbeat log ----------
#define DIAG_EARLY(reason) do { \
    static CFTimeInterval s_lastDiagE = 0; \
    CFTimeInterval nowE = CACurrentMediaTime(); \
    if (nowE - s_lastDiagE > 5.0) { \
        s_lastDiagE = nowE; \
        kernel_boot_log_fn logFnE = kernelBootLog; \
        if (logFnE) { \
            NSString *lineE = [NSString stringWithFormat:@"[diag] stop: %@", reason]; \
            dispatch_async(dispatch_get_main_queue(), ^{ logFnE(lineE); }); \
        } \
    } \
} while (0)

static int g_hbLastReal = -1;
static int g_hbLastBot  = -1;

static void ESPDiagHeartbeat(void) {
    static CFTimeInterval s_hb = 0;
    CFTimeInterval nowH = CACurrentMediaTime();
    if (nowH - s_hb < 1.0) return;
    s_hb = nowH;
    const uint64_t base = Moudule_Base;
    const int attached  = ds_attached() ? 1 : 0;
    const int pid       = (int)ds_pid();
    uint64_t ti = 0, st = 0, mg = 0, cam = 0, mt = 0, pawn = 0;
    int   hp   = -1;
    float vp[16];
    int   vpOk = 0;
    memset(vp, 0, sizeof(vp));
    if (isVaildPtr(base)) {
        ti = ReadAddr<uint64_t>(base + (uint64_t)kGameFacadeTypeInfo);
        if (isVaildPtr(ti)) {
            st = ReadAddr<uint64_t>(ti + kTypeInfoStatics);
        }
        mg = getMatchGame(base);
        if (isVaildPtr(mg)) {
            cam = CameraMain(mg);
            mt  = getMatch(mg);
            if (isVaildPtr(mt)) {
                pawn = getLocalPlayer(mt);
                if (isVaildPtr(pawn)) hp = get_CurHP(pawn);
            }
        }
    }
    if (isVaildPtr(cam)) {
        vpOk = GetViewMatrixInto(cam, vp) ? 1 : 0;
    }
    NSLog(@"[HB] base=0x%llx pid=%d at=%d ti=0x%llx st=0x%llx mg=0x%llx cam=0x%llx "
          @"mt=0x%llx pawn=0x%llx hp=%d real=%d bot=%d VP{ok=%d m0=%.4f m3=%.4f m12=%.4f m15=%.4f}",
          (unsigned long long)base, pid, attached,
          (unsigned long long)ti, (unsigned long long)st,
          (unsigned long long)mg, (unsigned long long)cam,
          (unsigned long long)mt, (unsigned long long)pawn, hp,
          g_hbLastReal, g_hbLastBot,
          vpOk, vp[0], vp[3], vp[12], vp[15]);
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.textLayerPool = [NSMutableArray arrayWithCapacity:300];
        self.imageLayerPool = [NSMutableArray arrayWithCapacity:80];
        InitWeaponTextures();
        gEngine = (void *)1;
        _secureTextField = [[HTHESPSecureWrapper alloc] initWithFrame:self.bounds];
        _secureTextField.userInteractionEnabled = NO;
        _secureTextField.enabled = NO;
        _secureTextField.backgroundColor = [UIColor clearColor];
        _secureTextField.text = @"\u200B";
        _secureTextField.textColor = [UIColor clearColor];
        [self addSubview:_secureTextField];
        _secureTextField.secureTextEntry = ESPPrefsBool(@"StreamerMode", NO);
        [_secureTextField layoutIfNeeded];
        _secureCanvas = _secureTextField.subviews.firstObject ?: _secureTextField;
        _secureCanvas.userInteractionEnabled = NO;
        [self configureRenderingLayers];
        self.frameTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        if (self.frameTimer) {
            dispatch_source_set_timer(self.frameTimer,
                                      dispatch_time(DISPATCH_TIME_NOW, 16 * NSEC_PER_MSEC),
                                      16 * NSEC_PER_MSEC,
                                      2 * NSEC_PER_MSEC);
            __weak ESP_View *wself = self;
            dispatch_source_set_event_handler(self.frameTimer, ^{
                [wself updateFrame];
            });
            dispatch_resume(self.frameTimer);
        }
    }
    return self;
}

// ---------- FIX TẮT NGUỒN: dealloc dừng hết thread + release port ----------
- (void)dealloc {
    if (self.frameTimer) {
        dispatch_source_cancel(self.frameTimer);
        self.frameTimer = nil;
    }
    if (self.displayLink) {
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
    // Dừng thread silent — tránh truy cập mutex sau khi destroy
    SilentAimStop();
    AimLockStop();
    // Release port game nếu còn giữ
    if (g_target_task != 0) {
        mach_port_deallocate(mach_task_self(), g_target_task);
        g_target_task = 0;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _secureTextField.frame = self.bounds;
    _secureCanvas.frame = self.bounds;
}

- (CAShapeLayer *)buildShapeLayerWithStroke:(UIColor *)stroke fill:(UIColor *)fill lineWidth:(CGFloat)lineWidth zPos:(CGFloat)zPos {
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.strokeColor = stroke ? stroke.CGColor : nil;
    layer.fillColor = fill ? fill.CGColor : nil;
    layer.lineWidth = lineWidth;
    layer.lineJoin = kCALineJoinRound;
    layer.lineCap = kCALineCapRound;
    layer.opaque = NO;
    layer.contentsScale = UIScreen.mainScreen.scale;
    layer.zPosition = zPos;
    layer.actions = @{ @"path": NSNull.null, @"strokeColor": NSNull.null, @"fillColor": NSNull.null, @"lineWidth": NSNull.null };
    return layer;
}

- (void)configureRenderingLayers {
    CGFloat baseZ = 0;
    self.bgFillBlackLayer = [self buildShapeLayerWithStroke:nil fill:[UIColor colorWithWhite:0.0f alpha:0.65f] lineWidth:0 zPos:baseZ + 4];
    self.snaplineLayer = [self buildShapeLayerWithStroke:[UIColor cyanColor] fill:UIColor.clearColor lineWidth:0.6f zPos:baseZ + 1];
    self.boxLayer = [self buildShapeLayerWithStroke:[UIColor cyanColor] fill:UIColor.clearColor lineWidth:0.6f zPos:baseZ + 3];
    self.boneLayer = [self buildShapeLayerWithStroke:[UIColor cyanColor] fill:UIColor.clearColor lineWidth:0.7f zPos:baseZ + 2];
    self.snaplineBotLayer = [self buildShapeLayerWithStroke:[UIColor yellowColor] fill:UIColor.clearColor lineWidth:0.6f zPos:baseZ + 1];
    self.boxBotLayer = [self buildShapeLayerWithStroke:[UIColor yellowColor] fill:UIColor.clearColor lineWidth:0.6f zPos:baseZ + 3];
    self.boneBotLayer = [self buildShapeLayerWithStroke:[UIColor yellowColor] fill:UIColor.clearColor lineWidth:0.7f zPos:baseZ + 2];
    self.snaplineKnockedLayer = [self buildShapeLayerWithStroke:[UIColor redColor] fill:UIColor.clearColor lineWidth:0.6f zPos:baseZ + 1];
    self.boxKnockedLayer = [self buildShapeLayerWithStroke:[UIColor redColor] fill:UIColor.clearColor lineWidth:0.6f zPos:baseZ + 3];
    self.boneKnockedLayer = [self buildShapeLayerWithStroke:[UIColor redColor] fill:UIColor.clearColor lineWidth:0.7f zPos:baseZ + 2];
    self.fovLayer = [self buildShapeLayerWithStroke:[UIColor yellowColor] fill:UIColor.clearColor lineWidth:0.6f zPos:baseZ];
    self.aimAssistLayer = [self buildShapeLayerWithStroke:[UIColor cyanColor] fill:UIColor.clearColor lineWidth:1.5f zPos:baseZ + 6];
    self.hpFillGreenLayer = [self buildShapeLayerWithStroke:nil fill:[UIColor colorWithRed:0.0f green:1.0f blue:0.0f alpha:1.0f] lineWidth:0 zPos:baseZ + 5];
    self.hpFillOrangeLayer = [self buildShapeLayerWithStroke:nil fill:[UIColor orangeColor] lineWidth:0 zPos:baseZ + 5];
    self.hpFillRedLayer = [self buildShapeLayerWithStroke:nil fill:[UIColor redColor] lineWidth:0 zPos:baseZ + 5];
    self.alertLayer = [self buildShapeLayerWithStroke:nil fill:[UIColor colorWithRed:103.0f/255.0f green:194.0f/255.0f blue:42.0f/255.0f alpha:1.0f] lineWidth:0 zPos:baseZ + 5];
    self.alertNumBGLayer = [self buildShapeLayerWithStroke:nil fill:[UIColor colorWithWhite:0.0f alpha:0.65f] lineWidth:0 zPos:baseZ + 7];
    self.alertNumGreenLayer = [self buildShapeLayerWithStroke:[UIColor colorWithRed:0 green:1 blue:0 alpha:1.0f] fill:[UIColor clearColor] lineWidth:4.0f zPos:baseZ + 8];
    self.alertNumOrangeLayer = [self buildShapeLayerWithStroke:[UIColor orangeColor] fill:[UIColor clearColor] lineWidth:4.0f zPos:baseZ + 8];
    self.alertNumRedLayer = [self buildShapeLayerWithStroke:[UIColor redColor] fill:[UIColor clearColor] lineWidth:4.0f zPos:baseZ + 8];
    NSArray *layers = @[self.bgFillBlackLayer, self.fovLayer, self.snaplineLayer, self.snaplineBotLayer, self.snaplineKnockedLayer, self.boneLayer, self.boneBotLayer, self.boneKnockedLayer, self.boxLayer, self.boxBotLayer, self.boxKnockedLayer, self.hpFillGreenLayer, self.hpFillOrangeLayer, self.hpFillRedLayer, self.alertLayer, self.aimAssistLayer, self.alertNumBGLayer, self.alertNumGreenLayer, self.alertNumOrangeLayer, self.alertNumRedLayer];
    for (CAShapeLayer *layer in layers) {
        [_secureCanvas.layer addSublayer:layer];
    }
    self.statusLayer = [CATextLayer layer];
    self.statusLayer.alignmentMode = kCAAlignmentCenter;
    self.statusLayer.contentsScale = UIScreen.mainScreen.scale;
    self.statusLayer.zPosition = baseZ + 9;
    self.statusLayer.shadowColor = [UIColor blackColor].CGColor;
    self.statusLayer.shadowOffset = CGSizeMake(2.0, 2.0);
    self.statusLayer.shadowOpacity = 0.86f;
    self.statusLayer.shadowRadius = 0.0;
    self.statusLayer.actions = @{@"string": NSNull.null, @"hidden": NSNull.null, @"bounds": NSNull.null, @"position": NSNull.null, @"foregroundColor": NSNull.null};
    [_secureCanvas.layer addSublayer:self.statusLayer];
}

- (void)resetReusableLayers {
    for (NSUInteger i = 0; i < self.activeTextLayerCount; i++) {
        CATextLayer *layer = self.textLayerPool[i];
        if (!layer.hidden) layer.hidden = YES;
    }
    self.activeTextLayerCount = 0;
    for (NSUInteger i = 0; i < self.activeImageLayerCount; i++) {
        CALayer *layer = self.imageLayerPool[i];
        if (!layer.hidden) layer.hidden = YES;
    }
    self.activeImageLayerCount = 0;
}

- (CATextLayer *)dequeueTextLayer {
    if (self.activeTextLayerCount < self.textLayerPool.count) {
        CATextLayer *layer = self.textLayerPool[self.activeTextLayerCount];
        if (layer.hidden) layer.hidden = NO;
        self.activeTextLayerCount++;
        return layer;
    }
    if (self.textLayerPool.count < 300) {
        CATextLayer *layer = [CATextLayer layer];
        layer.contentsScale = UIScreen.mainScreen.scale;
        layer.allowsGroupOpacity = NO;
        layer.zPosition = 8.5;
        layer.alignmentMode = kCAAlignmentCenter;
        layer.shadowOpacity = 0.0;
        layer.actions = @{ @"position": NSNull.null, @"bounds": NSNull.null, @"string": NSNull.null, @"hidden": NSNull.null, @"foregroundColor": NSNull.null, @"fontSize": NSNull.null };
        [self.textLayerPool addObject:layer];
        [_secureCanvas.layer addSublayer:layer];
        self.activeTextLayerCount++;
        return layer;
    }
    return self.textLayerPool.lastObject;
}

- (CALayer *)dequeueImageLayer {
    if (self.activeImageLayerCount < self.imageLayerPool.count) {
        CALayer *layer = self.imageLayerPool[self.activeImageLayerCount];
        if (layer.hidden) layer.hidden = NO;
        self.activeImageLayerCount++;
        return layer;
    }
    if (self.imageLayerPool.count < 80) {
        CALayer *layer = [CALayer layer];
        layer.contentsScale = UIScreen.mainScreen.scale;
        layer.contentsGravity = kCAGravityResizeAspect;
        layer.zPosition = 15.0;
        layer.name = @"WeaponIconLayer";
        layer.actions = @{ @"position": NSNull.null, @"bounds": NSNull.null, @"contents": NSNull.null, @"hidden": NSNull.null };
        [self.imageLayerPool addObject:layer];
        [_secureCanvas.layer addSublayer:layer];
        self.activeImageLayerCount++;
        return layer;
    }
    return self.imageLayerPool.lastObject;
}

- (void)addText:(NSString *)text frame:(CGRect)frame color:(UIColor *)color fontSize:(CGFloat)fontSize leftAligned:(BOOL)leftAligned {
    if (text.length == 0) return;
    CATextLayer *layer = [self dequeueTextLayer];
    static NSString *fontNameStr = nil;
    if (!fontNameStr) {
        fontNameStr = LoadCountFont(10).fontName;
    }
    layer.font = (__bridge CFTypeRef)fontNameStr;
    if (![layer.string isEqualToString:text]) layer.string = text;
    if (!CGRectEqualToRect(layer.frame, frame)) layer.frame = frame;
    if (!CGColorEqualToColor(layer.foregroundColor, color.CGColor)) {
        layer.foregroundColor = color.CGColor;
    }
    if (layer.fontSize != fontSize) layer.fontSize = fontSize;
    NSString *align = leftAligned ? kCAAlignmentLeft : kCAAlignmentCenter;
    if (layer.alignmentMode != align) layer.alignmentMode = align;
}

- (void)addImage:(UIImage *)image frame:(CGRect)frame {
    if (!image) return;
    CALayer *layer = [self dequeueImageLayer];
    CGImageRef cgImg = image.CGImage;
    if (layer.contents != (__bridge id)cgImg) layer.contents = (__bridge id)cgImg;
    if (!CGRectEqualToRect(layer.frame, frame)) layer.frame = frame;
}

// ============================================================
// esp.mm — Part 7/8
// updateFrame — KHÔNG còn BRUTAL PATCH scan 2GB
// ============================================================

static inline uint64_t ESPPhaseNowUS(void) {
    static mach_timebase_info_data_t tb;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&tb); });
    return (mach_absolute_time() * tb.numer / tb.denom) / 1000ULL;
}

- (void)updateFrame {
    @autoreleasepool {
        static CFTimeInterval lastPrefSync = 0;
        CFTimeInterval now = CACurrentMediaTime();
        if (now - lastPrefSync > 1.0) {
            ESPSyncFromPrefs();
            lastPrefSync = now;
        }
        ESPDiagHeartbeat();
        {
            static CFTimeInterval s_lastColorPref = 0;
            static int s_liveBoxMode = 0, s_liveLineMode = 0, s_liveBoneMode = 0, s_liveFovMode = 0;
            static float s_liveBoxR = 0, s_liveBoxG = 1, s_liveBoxB = 1;
            static float s_liveLineR = 0, s_liveLineG = 1, s_liveLineB = 1;
            static float s_liveBoneR = 0, s_liveBoneG = 1, s_liveBoneB = 1;
            static float s_liveFovR = 1, s_liveFovG = 1, s_liveFovB = 0;
            const bool anyRainbow =
                (boxColorMode == 1) || (lineColorMode == 1) ||
                (boneColorMode == 1) || (fovColorMode == 1) ||
                (s_liveBoxMode == 1) || (s_liveLineMode == 1) ||
                (s_liveBoneMode == 1) || (s_liveFovMode == 1);
            const bool refreshColorPrefs =
                (s_lastColorPref <= 0.0) ||
                (now - s_lastColorPref > (anyRainbow ? 0.033 : 0.12));
            if (refreshColorPrefs) {
                s_lastColorPref = now;
                s_liveBoxMode  = (int)ESPPrefsFloat(@"BoxColorMode",  (float)boxColorMode);
                s_liveLineMode = (int)ESPPrefsFloat(@"LineColorMode", (float)lineColorMode);
                s_liveBoneMode = (int)ESPPrefsFloat(@"BoneColorMode", (float)boneColorMode);
                s_liveFovMode  = (int)ESPPrefsFloat(@"FovColorMode",  (float)fovColorMode);
                s_liveBoxR = ESPPrefsFloat(@"BoxColorR", boxR);
                s_liveBoxG = ESPPrefsFloat(@"BoxColorG", boxG);
                s_liveBoxB = ESPPrefsFloat(@"BoxColorB", boxB);
                s_liveLineR = ESPPrefsFloat(@"LineColorR", lineR);
                s_liveLineG = ESPPrefsFloat(@"LineColorG", lineG);
                s_liveLineB = ESPPrefsFloat(@"LineColorB", lineB);
                s_liveBoneR = ESPPrefsFloat(@"BoneColorR", boneR);
                s_liveBoneG = ESPPrefsFloat(@"BoneColorG", boneG);
                s_liveBoneB = ESPPrefsFloat(@"BoneColorB", boneB);
                s_liveFovR = ESPPrefsFloat(@"FovColorR", fovR);
                s_liveFovG = ESPPrefsFloat(@"FovColorG", fovG);
                s_liveFovB = ESPPrefsFloat(@"FovColorB", fovB);
            }
            if (isESP2) {
                self.boxLayer.lineWidth = 1.0f;
                self.boxLayer.strokeColor = [UIColor whiteColor].CGColor;
                self.snaplineLayer.lineWidth = 1.0f;
                self.snaplineLayer.strokeColor = [UIColor whiteColor].CGColor;
                self.fovLayer.lineWidth = 0.6f;
                self.fovLayer.strokeColor = [UIColor greenColor].CGColor;
            } else {
                float drawBoxR = s_liveBoxR, drawBoxG = s_liveBoxG, drawBoxB = s_liveBoxB;
                float drawLineR = s_liveLineR, drawLineG = s_liveLineG, drawLineB = s_liveLineB;
                float drawBoneR = s_liveBoneR, drawBoneG = s_liveBoneG, drawBoneB = s_liveBoneB;
                float drawFovR = s_liveFovR, drawFovG = s_liveFovG, drawFovB = s_liveFovB;
                ESPResolveDrawColor(s_liveBoxMode, s_liveBoxR, s_liveBoxG, s_liveBoxB, 0.00f, &drawBoxR, &drawBoxG, &drawBoxB);
                ESPResolveDrawColor(s_liveLineMode, s_liveLineR, s_liveLineG, s_liveLineB, 0.25f, &drawLineR, &drawLineG, &drawLineB);
                ESPResolveDrawColor(s_liveBoneMode, s_liveBoneR, s_liveBoneG, s_liveBoneB, 0.50f, &drawBoneR, &drawBoneG, &drawBoneB);
                ESPResolveDrawColor(s_liveFovMode, s_liveFovR, s_liveFovG, s_liveFovB, 0.75f, &drawFovR, &drawFovG, &drawFovB);
                self.boxLayer.lineWidth = boxThick;
                self.boxLayer.strokeColor = [UIColor colorWithRed:drawBoxR green:drawBoxG blue:drawBoxB alpha:1.0f].CGColor;
                self.boneLayer.lineWidth = boneThick;
                self.boneLayer.strokeColor = [UIColor colorWithRed:drawBoneR green:drawBoneG blue:drawBoneB alpha:1.0f].CGColor;
                self.snaplineLayer.lineWidth = lineThick;
                self.snaplineLayer.strokeColor = [UIColor colorWithRed:drawLineR green:drawLineG blue:drawLineB alpha:1.0f].CGColor;
                self.fovLayer.lineWidth = fovThick;
                self.fovLayer.strokeColor = [UIColor colorWithRed:drawFovR green:drawFovG blue:drawFovB alpha:1.0f].CGColor;
            }
        }
        self.aimAssistLayer.lineWidth = aimAssistThick;
        self.aimAssistLayer.strokeColor = [UIColor colorWithRed:aimAssistR green:aimAssistG blue:aimAssistB alpha:1.0f].CGColor;
        if (!isESP && !isESP2 && !isAimbot && !isAimAssist && !isAimSilent && !isSpeed && !isCamPC) {
            [self clearAllContent];
            if (!self.hidden) self.hidden = YES;
            return;
        } else {
            if (self.hidden) self.hidden = NO;
        }
        if (_secureTextField.secureTextEntry != isStreamerMode) {
            NSArray *sublayers = [NSArray arrayWithArray:_secureCanvas.layer.sublayers];
            for (CALayer *layer in sublayers) { [layer removeFromSuperlayer]; }
            _secureTextField.secureTextEntry = isStreamerMode;
            [_secureTextField setNeedsLayout];
            [_secureTextField layoutIfNeeded];
            _secureCanvas = _secureTextField.subviews.firstObject ?: _secureTextField;
            _secureCanvas.userInteractionEnabled = NO;
            NSArray *layers = @[self.bgFillBlackLayer, self.fovLayer, self.snaplineLayer, self.snaplineBotLayer, self.snaplineKnockedLayer, self.boneLayer, self.boneBotLayer, self.boneKnockedLayer, self.boxLayer, self.boxBotLayer, self.boxKnockedLayer, self.hpFillGreenLayer, self.hpFillOrangeLayer, self.hpFillRedLayer, self.alertLayer, self.aimAssistLayer, self.alertNumBGLayer, self.alertNumGreenLayer, self.alertNumOrangeLayer, self.alertNumRedLayer];
            for (CAShapeLayer *layer in layers) {
                [_secureCanvas.layer addSublayer:layer];
            }
            [_secureCanvas.layer addSublayer:self.statusLayer];
            for (CATextLayer *layer in self.textLayerPool) { [layer removeFromSuperlayer]; }
            [self.textLayerPool removeAllObjects];
            self.activeTextLayerCount = 0;
            for (CALayer *layer in self.imageLayerPool) { [layer removeFromSuperlayer]; }
            [self.imageLayerPool removeAllObjects];
            self.activeImageLayerCount = 0;
        }
        {
            static pid_t s_attachedPid = -1;
            static int s_reattachCooldown = 0;
            bool needAttach = (Moudule_Base == (uint64_t)-1 || Moudule_Base == 0 ||
                               !ds_attached() || ds_pid() != s_attachedPid);
            if (needAttach) {
                if (s_reattachCooldown > 0) {
                    s_reattachCooldown--;
                } else {
                    GameOffsetsReload();
                    uintptr_t base = (uintptr_t)GameTargetModuleBase();
                    if (base != 0 && ds_attached()) {
                        Moudule_Base = (uint64_t)base;
                        s_attachedPid = ds_pid();
                        gEngine = (void *)1;
                        // Release port cũ khi PID đổi
                        if (g_target_task != 0) {
                            mach_port_deallocate(mach_task_self(), g_target_task);
                            g_target_task = 0;
                        }
                        NSLog(@"[ESP] Attached to game PID=%d, Moudule_Base=0x%llx", ds_pid(), (unsigned long long)Moudule_Base);
                    } else {
                        // KHÔNG reset Moudule_Base về 0 — chỉ chờ thêm
                        s_attachedPid = -1;
                        s_reattachCooldown = 5;
                    }
                }
            }
        }
        [CATransaction begin];
        const uint64_t tPhase0 = ESPPhaseNowUS();
        [self resetReusableLayers];
        const CGFloat bw = self.bounds.size.width;
        const CGFloat bh = self.bounds.size.height;
        CGFloat viewWidth  = (bw > bh) ? bw : bh;
        CGFloat viewHeight = (bw > bh) ? bh : bw;
        CGFloat matrixVpW = viewWidth;
        CGFloat matrixVpH = viewHeight;
        if (matrixVpW < 1.0) matrixVpW = 1.0;
        if (matrixVpH < 1.0) matrixVpH = 1.0;
        float halfWidth = viewWidth * 0.5f;
        float halfHeight = viewHeight * 0.5f;
        CGPoint screenCenter = CGPointMake(halfWidth, halfHeight);
        ESPGeometryBuffers buffers = ESPGeometryBuffersCreate();
        g_PlayerDrawIndex = 1;
        ds_begin_read_transaction();
        ESPFrameStats stats = [self renderESPWithBuffers:&buffers viewWidth:viewWidth viewHeight:viewHeight matrixVpWidth:matrixVpW matrixVpHeight:matrixVpH screenCenter:screenCenter];
        const uint64_t tPhase1 = ESPPhaseNowUS();
        ds_end_read_transaction();
        g_hbLastReal = stats.realCount;
        g_hbLastBot  = stats.botCount;
        bool showVisuals = (isESP || isESP2);
        MenuViewApplyPath(self.bgFillBlackLayer, showVisuals ? buffers.bgFillBlackPath : nil, buffers.bgFillBlackDirty);
        MenuViewApplyPath(self.boxLayer, showVisuals ? buffers.boxPath : nil, buffers.boxDirty);
        MenuViewApplyPath(self.boxBotLayer, showVisuals ? buffers.boxBotPath : nil, buffers.boxBotDirty);
        MenuViewApplyPath(self.boxKnockedLayer, showVisuals ? buffers.boxKnockedPath : nil, buffers.boxKnockedDirty);
        MenuViewApplyPath(self.boneLayer, showVisuals ? buffers.bonePath : nil, buffers.boneDirty);
        MenuViewApplyPath(self.boneBotLayer, showVisuals ? buffers.boneBotPath : nil, buffers.boneBotDirty);
        MenuViewApplyPath(self.boneKnockedLayer, showVisuals ? buffers.boneKnockedPath : nil, buffers.boneKnockedDirty);
        MenuViewApplyPath(self.snaplineLayer, showVisuals ? buffers.snaplinePath : nil, buffers.snaplineDirty);
        MenuViewApplyPath(self.snaplineBotLayer, showVisuals ? buffers.snaplineBotPath : nil, buffers.snaplineBotDirty);
        MenuViewApplyPath(self.snaplineKnockedLayer, showVisuals ? buffers.snaplineKnockedPath : nil, buffers.snaplineKnockedDirty);
        MenuViewApplyPath(self.hpFillGreenLayer, showVisuals ? buffers.hpFillGreenPath : nil, buffers.hpFillGreenDirty);
        MenuViewApplyPath(self.hpFillOrangeLayer, showVisuals ? buffers.hpFillOrangePath : nil, buffers.hpFillOrangeDirty);
        MenuViewApplyPath(self.hpFillRedLayer, showVisuals ? buffers.hpFillRedPath : nil, buffers.hpFillRedDirty);
        MenuViewApplyPath(self.alertLayer, showVisuals ? buffers.alertPath : nil, buffers.alertDirty);

        // ============================================================
        // BRUTAL PATCH — ĐÃ BỎ HOÀN TOÀN.
        // Lý do: scan 2GB + malloc size lớn + detach thread + port leak
        // => nguyên nhân chính gây tắt nguồn / panic.
        // Nếu cần speed, dùng ToggleSpeedX50Safe() bên dưới.
        // ============================================================

        static int s_dirtyBox = 0, s_dirtyBone = 0, s_dirtySnap = 0, s_dirtyHpG = 0;
        s_dirtyBox = buffers.boxDirty;
        s_dirtyBone = buffers.boneDirty;
        s_dirtySnap = buffers.snaplineDirty;
        s_dirtyHpG  = buffers.hpFillGreenDirty;
        if (showVisuals && stats.aimAssistPath) {
            MenuViewApplyPath(self.aimAssistLayer, stats.aimAssistPath, YES);
            CGPathRelease(stats.aimAssistPath);
        } else {
            self.aimAssistLayer.path = nil;
        }
        ESPGeometryBuffersRelease(&buffers);
        CGMutablePathRef fovPath = CGPathCreateMutable();
        BOOL hasFov = RenderFOVCirclePath(fovPath, viewWidth, viewHeight,
                                          isAimbot && aimSphereMode == 0 && isShowFovCircle, aimFov);
        self.fovLayer.path = hasFov ? fovPath : nil;
        CGPathRelease(fovPath);
        if (isCount) {
            NSString *countText;
            UIColor *countColor;
            CGFloat fontSize;
            if (stats.realCount == 0 && stats.botCount == 0) {
                if (isESP2) {
                    countText = @"CLEAR";
                    countColor = [UIColor cyanColor];
                    fontSize = 20.0f;
                } else {
                    countText = @"CLEAR";
                    countColor = [UIColor colorWithRed:50.0f/255.0f green:255.0f/255.0f blue:80.0f/255.0f alpha:1.0f];
                    fontSize = 21.0f;
                }
            } else {
                if (isESP2) {
                    countText = [NSString stringWithFormat:@"%d", stats.realCount + stats.botCount];
                    countColor = [UIColor colorWithRed:50.0f/255.0f green:255.0f/255.0f blue:80.0f/255.0f alpha:1.0f];
                    fontSize = 25.0f;
                } else {
                    countText = [NSString stringWithFormat:@"PLAYER [%d] | BOT [%d]", stats.realCount, stats.botCount];
                    countColor = [UIColor colorWithRed:50.0f/255.0f green:255.0f/255.0f blue:80.0f/255.0f alpha:1.0f];
                    fontSize = 16.0f;
                }
            }
            if (![self.lastStatusString isEqualToString:countText]) {
                self.lastStatusString = countText;
                self.statusLayer.string = countText;
                self.statusLayer.foregroundColor = countColor.CGColor;
                self.statusLayer.fontSize = fontSize;
                self.statusLayer.font = (__bridge CFTypeRef)LoadCountFont(fontSize).fontName;
            }
            CGFloat countWidth = isESP2 ? 80.0f : 220.0f;
            CGFloat countHeight = fontSize + 8.0f;
            CGFloat yPos = isESP2 ? 30.0f : 25.0f;
            CGFloat xPos = halfWidth - (countWidth * 0.5f);
            CGRect newStatusFrame = CGRectMake(xPos, yPos, countWidth, countHeight);
            if (!CGRectEqualToRect(self.statusLayer.frame, newStatusFrame)) {
                self.statusLayer.frame = newStatusFrame;
            }
            self.statusLayer.masksToBounds = NO;
            if (self.statusLayer.hidden) self.statusLayer.hidden = NO;
        } else {
            if (!self.statusLayer.hidden) self.statusLayer.hidden = YES;
        }
        const uint64_t tPhase2 = ESPPhaseNowUS();
        [CATransaction commit];
        extern void SBRemotePushESPFrame(UIView *espView);
        SBRemotePushESPFrame(self);
        {
            const uint64_t tPhase3 = ESPPhaseNowUS();
            static uint64_t s_phUS = 0;
            static uint32_t s_phFrames = 0;
            static uint64_t s_phRender = 0, s_phLayer = 0, s_phPush = 0;
            s_phFrames++;
            s_phRender  += (tPhase1 - tPhase0);
            s_phLayer   += (tPhase2 - tPhase1);
            s_phPush    += (tPhase3 - tPhase2);
            if (tPhase3 > s_phUS + 1000000ULL) {
                const uint32_t n = s_phFrames ? s_phFrames : 1;
                NSLog(@"[PUSH-PHASE] fps=%u read=%.2fms layer=%.2fms push=%.2fms total=%.2fms",
                      (unsigned)s_phFrames,
                      (double)s_phRender / (double)n / 1000.0,
                      (double)s_phLayer / (double)n / 1000.0,
                      (double)s_phPush / (double)n / 1000.0,
                      (double)(s_phRender + s_phLayer + s_phPush) / (double)n / 1000.0);
                s_phUS = tPhase3;
                s_phFrames = 0;
                s_phRender = s_phLayer = s_phPush = 0;
            }
        }
    }
}

// ============================================================
// ToggleSpeedX50 SAFE — thay thế bản cũ scan 1.5GB
// Chunk 4MB, check malloc NULL, check mach_vm_write return
// ============================================================
extern "C" void ToggleSpeedX50Safe(bool enable) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        std::lock_guard<std::mutex> lk(g_patchedMtx);
        pid_t pid = (pid_t)GameTargetProcessPid();
        if (pid <= 0) return;
        task_t tk = 0;
        if (task_for_pid(mach_task_self(), pid, &tk) != KERN_SUCCESS) {
            NSLog(@"[HTH Cheat] LỖI: Không lấy được task_for_pid!");
            return;
        }
        uint64_t originalVal = 4397530849764387586ULL;
        uint64_t hackedVal   = 4397530849740000000ULL;
        const mach_vm_size_t kChunkMax = 4 * 1024 * 1024; // 4MB
        if (enable) {
            g_patchedAddresses.clear();
            mach_vm_address_t address = 0x100000000;
            mach_vm_size_t size = 0;
            vm_region_basic_info_data_64_t info;
            mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
            mach_port_t object_name;
            while (mach_vm_region(tk, &address, &size, VM_REGION_BASIC_INFO_64,
                                  (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS) {
                if (address > 0x160000000) break;
                if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE)) {
                    mach_vm_address_t chunkAddr = address;
                    mach_vm_size_t remain = size;
                    while (remain > 0) {
                        mach_vm_size_t chunk = remain > kChunkMax ? kChunkMax : remain;
                        uint8_t *buffer = (uint8_t *)malloc(chunk);
                        if (!buffer) { chunkAddr += chunk; remain -= chunk; continue; }
                        mach_vm_size_t bytesRead = 0;
                        kern_return_t rk = mach_vm_read_overwrite(tk, chunkAddr, chunk,
                                                                  (mach_vm_address_t)buffer, &bytesRead);
                        if (rk == KERN_SUCCESS) {
                            for (size_t i = 0; i + 8 <= bytesRead; i += 4) {
                                uint64_t currentValue = *(uint64_t *)(buffer + i);
                                if (currentValue == originalVal) {
                                    mach_vm_address_t exactWriteAddress = chunkAddr + i;
                                    kern_return_t wk = mach_vm_write(tk, exactWriteAddress,
                                                                     (vm_offset_t)&hackedVal, sizeof(hackedVal));
                                    if (wk == KERN_SUCCESS) {
                                        g_patchedAddresses.push_back(exactWriteAddress);
                                    }
                                }
                            }
                        }
                        free(buffer);
                        chunkAddr += chunk;
                        remain -= chunk;
                    }
                }
                address += size;
            }
        } else {
            if (!g_patchedAddresses.empty()) {
                for (mach_vm_address_t savedAddr : g_patchedAddresses) {
                    kern_return_t wk = mach_vm_write(tk, savedAddr,
                                                     (vm_offset_t)&originalVal, sizeof(originalVal));
                    (void)wk;
                }
                g_patchedAddresses.clear();
            }
        }
        mach_port_deallocate(mach_task_self(), tk);
    });
}

// ============================================================
// esp.mm — Part 8/8 (FULL)
// renderESPWithBuffers + aim + getters + prefs + end of file
// ============================================================

- (ESPFrameStats)renderESPWithBuffers:(ESPGeometryBuffers *)buffers
                            viewWidth:(CGFloat)viewWidth
                           viewHeight:(CGFloat)viewHeight
                        matrixVpWidth:(CGFloat)matrixVpWidth
                       matrixVpHeight:(CGFloat)matrixVpHeight
                         screenCenter:(CGPoint)screenCenter
{
    ESPFrameStats stats = {0, 0, false, NULL};
    stats.aimAssistPath = CGPathCreateMutable();
    g_cacheFrameCounter++;
    CGMutablePathRef aNumBGPath = CGPathCreateMutable();
    CGMutablePathRef aNumGPath  = CGPathCreateMutable();
    CGMutablePathRef aNumOPath  = CGPathCreateMutable();
    CGMutablePathRef aNumRPath  = CGPathCreateMutable();

    if (!buffers || Moudule_Base == 0 || Moudule_Base == (uint64_t)-1) {
        DIAG_EARLY(@"no-base");
        CGPathRelease(aNumBGPath); CGPathRelease(aNumGPath);
        CGPathRelease(aNumOPath);  CGPathRelease(aNumRPath);
        if (stats.aimAssistPath) { CGPathRelease(stats.aimAssistPath); stats.aimAssistPath = NULL; }
        return stats;
    }
    uint64_t matchGame = getMatchGame(Moudule_Base);
    if (!isVaildPtr(matchGame)) {
        static int s_lobbyLog = 0;
        if (++s_lobbyLog % 300 == 1) NSLog(@"[ESP] Lobby mode: waiting for match...");
        DIAG_EARLY(@"lobby");
        CGPathRelease(aNumBGPath); CGPathRelease(aNumGPath);
        CGPathRelease(aNumOPath);  CGPathRelease(aNumRPath);
        if (stats.aimAssistPath) { CGPathRelease(stats.aimAssistPath); stats.aimAssistPath = NULL; }
        return stats;
    }
    uint64_t camera = CameraMain(matchGame);
    uint64_t match = getMatch(matchGame);
    if (!isVaildPtr(camera) || !isVaildPtr(match)) {
        DIAG_EARLY(@"loading-match");
        CGPathRelease(aNumBGPath); CGPathRelease(aNumGPath);
        CGPathRelease(aNumOPath);  CGPathRelease(aNumRPath);
        if (stats.aimAssistPath) { CGPathRelease(stats.aimAssistPath); stats.aimAssistPath = NULL; }
        return stats;
    }
    static int s_okLog = 0;
    if (++s_okLog % 300 == 1) {
        NSLog(@"[ESP] >>> IN-MATCH ACTIVE: matchGame=0x%llx, match=0x%llx, camera=0x%llx <<<",
              (unsigned long long)matchGame, (unsigned long long)match, (unsigned long long)camera);
    }
    {
        static uint64_t s_lastMatchDiag = 0;
        if (match != s_lastMatchDiag) {
            bool firstMatch = (s_lastMatchDiag == 0 && match != 0);
            if (s_lastMatchDiag != 0 || firstMatch) {
                DSPageCacheDiag before = ds_page_cache_diag();
                ds_flush_page_cache();
                DSPageCacheDiag after = ds_page_cache_diag();
                NSLog(@"[PUSH-FLUSH] first=%d 0x%llx->0x%llx dropped live=%d stale=%d now live=%d",
                      (int)firstMatch, (unsigned long long)s_lastMatchDiag,
                      (unsigned long long)match,
                      before.liveSlots, before.staleGen, after.liveSlots);
                ds_cache_bump_generation();
            }
            s_lastMatchDiag = match;
        }
    }
    uint64_t myPawnObject = getLocalPlayer(match);
    int curHp = isVaildPtr(myPawnObject) ? get_CurHP(myPawnObject) : 0;
    bool iAmAlive = isVaildPtr(myPawnObject) && (curHp >= 0);
    if (isVaildPtr(myPawnObject)) {
        static int s_speedTick = 0;
        static float s_lastRunWrite = -1.0f;
        static uint64_t s_lastAttrs = 0;
        const uint64_t attrsOff = kPlayerAttributes;
        const uint64_t runOff   = kRunSpeedUpScale;
        const uint64_t fallOff  = 0x26C;
        const uint64_t forceOff = 0x340;
        const uint64_t weapOff  = 0x130;
        uint64_t PlayerAttributes = ReadAddr<uint64_t>(myPawnObject + attrsOff);
        if (isVaildPtr(PlayerAttributes) && PlayerAttributes != 0) {
            ++s_speedTick;
            if (PlayerAttributes != s_lastAttrs) {
                s_lastAttrs = PlayerAttributes;
                s_lastRunWrite = -1.0f;
            }
            float writeVal = speedvalue;
            if (!Norecoil && isSpeed && moveSpeedScale > 1.0f) {
                writeVal = moveSpeedScale;
                if (writeVal > 1.28f) writeVal = 1.28f;
            }
            if (writeVal <= 0.0f) writeVal = 1.0f;
            float cur = ReadAddr<float>(PlayerAttributes + runOff);
            const bool curBad = isnan(cur) || cur < 0.01f || cur > 80.0f;
            const float drift = (!curBad && s_lastRunWrite > 0.0f) ? fabsf(cur - writeVal) : 999.0f;
            const float reassertEps = Norecoil ? 0.04f : 0.015f;
            const bool needWrite =
                curBad ||
                s_lastRunWrite < 0.0f ||
                fabsf(s_lastRunWrite - writeVal) > 0.001f ||
                drift > reassertEps ||
                (!curBad && cur > (Norecoil ? 12.0f : 3.0f));
            const int cadence = Norecoil ? 3 : 1;
            if (needWrite && (Norecoil ? ((s_speedTick % cadence) == 0) : true)) {
                WriteAddr<float>(PlayerAttributes + runOff, writeVal);
                s_lastRunWrite = writeVal;
            }
            if ((s_speedTick % 16) == 0) {
                float force = ReadAddr<float>(PlayerAttributes + forceOff);
                if (!isnan(force) && fabsf(force) > 0.001f)
                    WriteAddr<float>(PlayerAttributes + forceOff, 0.0f);
                if (!Norecoil && writeVal <= 1.001f) {
                    float f = ReadAddr<float>(PlayerAttributes + fallOff);
                    if (!isnan(f) && f > 1.05f && f < 50.0f)
                        WriteAddr<float>(PlayerAttributes + fallOff, 1.0f);
                    float w = ReadAddr<float>(PlayerAttributes + weapOff);
                    if (!isnan(w) && w > 1.05f && w < 50.0f)
                        WriteAddr<float>(PlayerAttributes + weapOff, 1.0f);
                }
            }
        }
    }
    if (g_target_task == 0) {
        pid_t pid = (pid_t)GameTargetProcessPid();
        if (pid > 0) task_for_pid(mach_task_self(), pid, &g_target_task);
    }
    if (iAmAlive) {
        static uint64_t rainbowPtrs[7] = {0};
        static bool rainbowInit = false;
        static NSString *cachedCustomName = nil;
        if (s_setNameEnabledGlobal && g_target_task != 0) {
            if (!rainbowInit || ![s_customNameGlobal isEqualToString:cachedCustomName]) {
                uint64_t originalStrPtr = ReadAddr<uint64_t>(myPawnObject + kNickname);
                if (isVaildPtr(originalStrPtr)) {
                    for(int offset = 0; offset < 7; offset++) {
                        NSString *animatedName = GenerateRainbowString(s_customNameGlobal, offset);
                        rainbowPtrs[offset] = AllocateMonoString(g_target_task, originalStrPtr, animatedName);
                    }
                    cachedCustomName = s_customNameGlobal;
                    rainbowInit = true;
                }
            }
            static int colorTick = 0;
            static int colorIndex = 0;
            if (rainbowInit) {
                if (colorTick++ % 15 == 0) { colorIndex = (colorIndex + 1) % 7; }
                if (rainbowPtrs[colorIndex] != 0) {
                    WriteAddr<uint64_t>(myPawnObject + kNickname, rainbowPtrs[colorIndex]);
                    WriteAddr<uint64_t>(myPawnObject + kNicknameDisplay, rainbowPtrs[colorIndex]);
                }
            }
        }
        bool actualFastReload = isFastReload && (fastReloadSpeed > 1.0f);
        EnableFastReload(myPawnObject, actualFastReload, fastReloadSpeed);
        DisableGameDefaultAimAssist(myPawnObject, isAimbot || isAimAssist);
        EnableCamPC(myPawnObject, isCamPC, camPCValue);
    }
    stats.inMatch = true;
    Vector3 myLocation = {0, 0, 0};
    if (isVaildPtr(myPawnObject)) {
        uint64_t mainCameraTransform = ReadAddr<uint64_t>(myPawnObject + kMainCameraTransform);
        if (isVaildPtr(mainCameraTransform)) {
            myLocation = getPositionExt(mainCameraTransform);
        }
        if (!looksLikeWorldPos(myLocation)) {
            myLocation = ReadPlayerRootTransform(myPawnObject);
        }
        if (!looksLikeWorldPos(myLocation)) {
            Vector3 lh = tryTransformPos(getHead(myPawnObject));
            if (looksLikeWorldPos(lh)) myLocation = lh;
        }
        if (!looksLikeWorldPos(myLocation)) {
            myLocation = ResolvePawnWorldPosAny(myPawnObject);
        }
    }
    const bool haveLocalPos = looksLikeWorldPos(myLocation);
    const bool useLocalDistance = haveLocalPos;

    // ===== Dict walk =====
    uint64_t playerDict = 0;
    const uint64_t dictOffs[] = {
        (uint64_t)kMatchPlayerDict,
        0x148, 0x140, 0x138, 0x150, 0x130, 0x120, 0x118
    };
    for (size_t i = 0; i < sizeof(dictOffs)/sizeof(dictOffs[0]); i++) {
        uint64_t d = ReadAddr<uint64_t>(match + dictOffs[i]);
        if (!isVaildPtr(d)) continue;
        uint64_t e = ReadAddr<uint64_t>(d + kDictEntries);
        if (!isVaildPtr(e)) e = ReadAddr<uint64_t>(d + 0x18);
        if (!isVaildPtr(e)) e = ReadAddr<uint64_t>(d + 0x10);
        if (!isVaildPtr(e)) continue;
        int cap = ReadAddr<int>(e + kIl2CppArrayMaxLength);
        if (cap > 0 && cap < 4096) {
            playerDict = d;
            NSLog(@"[ESP] dict found @ match+0x%llx cap=%d",
                  (unsigned long long)dictOffs[i], cap);
            break;
        }
    }
    if (!isVaildPtr(playerDict)) {
        static int s_noDictLog = 0;
        if (++s_noDictLog % 60 == 1) NSLog(@"[ESP] NO DICT FOUND match=0x%llx",
                                           (unsigned long long)match);
        CGPathRelease(aNumBGPath); CGPathRelease(aNumGPath);
        CGPathRelease(aNumOPath);  CGPathRelease(aNumRPath);
        if (stats.aimAssistPath) { CGPathRelease(stats.aimAssistPath); stats.aimAssistPath = NULL; }
        return stats;
    }
    uint64_t entriesArr = ReadAddr<uint64_t>(playerDict + kDictEntries);
    if (!isVaildPtr(entriesArr)) entriesArr = ReadAddr<uint64_t>(playerDict + 0x18);
    if (!isVaildPtr(entriesArr)) entriesArr = ReadAddr<uint64_t>(playerDict + 0x10);
    if (!isVaildPtr(entriesArr)) {
        static int s_noEntLog = 0;
        if (++s_noEntLog % 60 == 1) NSLog(@"[ESP] NO ENTRIES dict=0x%llx", (unsigned long long)playerDict);
        CGPathRelease(aNumBGPath); CGPathRelease(aNumGPath);
        CGPathRelease(aNumOPath);  CGPathRelease(aNumRPath);
        if (stats.aimAssistPath) { CGPathRelease(stats.aimAssistPath); stats.aimAssistPath = NULL; }
        return stats;
    }
    int slotCap = ReadAddr<int>(entriesArr + kIl2CppArrayMaxLength);
    if (slotCap <= 0 || slotCap > 2048) {
        static int s_badCapLog = 0;
        if (++s_badCapLog % 60 == 1) NSLog(@"[ESP] BAD CAP=%d entries=0x%llx", slotCap, (unsigned long long)entriesArr);
        CGPathRelease(aNumBGPath); CGPathRelease(aNumGPath);
        CGPathRelease(aNumOPath);  CGPathRelease(aNumRPath);
        if (stats.aimAssistPath) { CGPathRelease(stats.aimAssistPath); stats.aimAssistPath = NULL; }
        return stats;
    }
    float matrixData[16];
    memset(matrixData, 0, sizeof(matrixData));
    EspPawnSnap snaps[128];
    int snapN = 0;
    uint64_t bestTarget = 0;
    Vector3 bestHeadPos;
    float bestScore = FLT_MAX;
    float bestDistance = FLT_MAX;
    bool isVis = false;
    uint64_t bestAnyTarget = 0, bestLosTarget = 0;
    Vector3 bestAnyHead{}, bestLosHead{};
    float bestAnyScore = FLT_MAX, bestLosScore = FLT_MAX;
    float bestAnyDist = FLT_MAX, bestLosDist = FLT_MAX;
    bool bestAnyVis = false, bestLosVis = false;
    (void)bestLosVis;
    isAimBehindWall = AimBehindWallNow();
    AimWallOffFrameBegin(myPawnObject, myLocation);
    const bool useAssist = isAimAssist;
    const bool useAssistOnly = isAimAssist && !isAimbot;
    bool useSilent = isAimSilent;
    bool useAim = (isAimbot || useAssist || useSilent);
    const bool useAim180 = isAimbot && aimSphereMode == 1;
    const bool useAim360 = isAimbot && aimSphereMode == 2 && AimThroughAnyCoverNow();
    const bool useSphereAim = useAim180 || useAim360;
    const bool silentSphereOnly = useSilent && !isAimbot && !useAssist;
    const float aimFovSq = (isAimbot && !useSphereAim) ? (aimFov * aimFov) : 0.0f;
    const float assistRadius = fminf(fmaxf(viewHeight * 0.12f, 48.f), 140.f);
    const float assistRadiusSq = assistRadius * assistRadius;
    const float safeAimDistance = fmaxf(aimDistance, 1.0f);
    const float safeAimFovSq = fmaxf(aimFovSq, 1.0f);
    const float maxPossibleDistance = fmaxf(espDistanceLimit, aimDistance) + 5.0f;
    const uint64_t entriesBase = entriesArr + kIl2CppArrayItems;
    uint64_t entryStride = kDictEntryStrideBytePlayer ? kDictEntryStrideBytePlayer : 0x18;
    uint64_t entryValueOff = kDictEntryValueOffByte ? kDictEntryValueOffByte : 0x10;
    {
        struct { uint64_t stride, voff; } combos[] = {
            { 0x18, 0x10 },
            { 0x28, 0x20 },
            { 0x20, 0x18 },
        };
        bool found = false;
        for (int c = 0; c < 3 && !found; c++) {
            for (int i = 0; i < 16 && !found; i++) {
                uint64_t ent = entriesBase + combos[c].stride * (uint64_t)i;
                int hc = ReadAddr<int>(ent);
                if (hc == 0 || hc == -1) continue;
                uint64_t p = ReadAddr<uint64_t>(ent + combos[c].voff);
                if (!isVaildPtr(p)) continue;
                uint64_t hn = ReadAddr<uint64_t>(p + kHeadNode);
                if (isVaildPtr(hn)) {
                    entryStride = combos[c].stride;
                    entryValueOff = combos[c].voff;
                    found = true;
                    NSLog(@"[ESP] dict stride auto-detect: stride=0x%llx voff=0x%llx",
                          (unsigned long long)entryStride,
                          (unsigned long long)entryValueOff);
                }
            }
        }
    }
    int loopCount = slotCap;
    if (loopCount > 512) loopCount = 512;
    for (int i = 0; i < loopCount; i++) {
        uint64_t ent = entriesBase + entryStride * (uint64_t)i;
        int hc = ReadAddr<int>(ent);
        if (hc == 0 || hc == -1) continue;
        uint64_t PawnObject = ReadAddr<uint64_t>(ent + entryValueOff);
        if (!isVaildPtr(PawnObject)) {
            const uint64_t vOffs[] = { 0x10, 0x18, 0x20, 0x28 };
            for (size_t vo = 0; vo < 4; vo++) {
                uint64_t cand = ReadAddr<uint64_t>(ent + vOffs[vo]);
                if (isVaildPtr(cand)) {
                    PawnObject = cand;
                    break;
                }
            }
        }
        if (!isVaildPtr(PawnObject)) continue;
        if (isSamePlayerAsLocal(myPawnObject, PawnObject)) continue;
        if (isVaildPtr(myPawnObject) && isLocalTeamMate(myPawnObject, PawnObject)) continue;
        PlayerCache &c = g_playerCache[PlayerCacheSlot(PawnObject)];
        const bool cacheMiss = (c.pawn != PawnObject);
        if (cacheMiss) {
            c.pawn = PawnObject;
            c.isBot = get_IsBot(PawnObject);
            c.isTrueVis = false;
            c.isCamVis = false;
            c.isPvsVis = false;
            c.visGoodFrames = 0;
        } else if ((g_cacheFrameCounter & 7) == 0) {
            c.isBot = get_IsBot(PawnObject);
        }
        c.isKnocked = get_IsKnockedDown(PawnObject);
        c.curHP     = get_CurHP(PawnObject);
        c.maxHP     = get_MaxHP(PawnObject);
        c.frame     = g_cacheFrameCounter;
        if (isEspCheckVisible && (cacheMiss || (g_cacheFrameCounter & 1) == 0)) {
            const uint32_t vflags = get_VisibleFlags(PawnObject);
            c.isCamVis = (vflags & kISVisibleCamera) != 0;
            c.isPvsVis = (vflags & kISVisibleDynamicPVS) != 0;
            c.isFPP = (vflags & kISVisibleFPPMask) == kISVisibleFPPMask;
            c.isTrueVis = c.isFPP;
            c.visGoodFrames = c.isTrueVis ? 1 : 0;
        }
        bool isBot     = c.isBot;
        bool isKnocked = c.isKnocked;
        int CurHP      = c.curHP;
        int MaxHP      = c.maxHP;
        bool isFPP     = c.isFPP;
        bool isCamVis  = c.isCamVis;
        bool isTrueVis = c.isTrueVis;
        (void)isCamVis; (void)isTrueVis;
        static uint64_t s_deadPawn[96] = {};
        static int s_deadUntilFrame[96] = {};
        const int deadSlot = (int)(PawnObject % 96ull);
        if (s_deadPawn[deadSlot] == PawnObject && g_cacheFrameCounter < s_deadUntilFrame[deadSlot]) {
            continue;
        }
        auto markGhostDead = [&](int holdFrames) {
            PosTrack &trDead = g_posTrack[PosTrackSlot(PawnObject)];
            trDead.pawn = PawnObject;
            trDead.deadUntilFrame = g_cacheFrameCounter + holdFrames;
            trDead.headSmoothed = trDead.hipSmoothed = Vector3{};
            trDead.lastHeadRaw = trDead.lastHipRaw = Vector3{};
            trDead.headVel = trDead.hipVel = Vector3{};
            trDead.lastHeadT = trDead.lastHipT = 0;
            trDead.headSrc = trDead.hipSrc = 0;
            trDead.headSrcHold = trDead.hipSrcHold = 0;
            trDead.hasHead = trDead.hasHip = false;
            trDead.frame = g_cacheFrameCounter;
            trDead.bodyLenHold = 0;
            s_deadPawn[deadSlot] = PawnObject;
            s_deadUntilFrame[deadSlot] = g_cacheFrameCounter + holdFrames;
            if (gAimLockTarget == PawnObject) {
                gAimLockTarget = 0;
                gAimLockLostFrames = 0;
            }
            ClearBoxScreenForPawn(PawnObject);
            ClearProBoxScreenForPawn(PawnObject);
        };
        Vector3 liveHead = getPositionExt(getHead(PawnObject));
        Vector3 liveHip  = getPositionExt(getHip(PawnObject));
        const bool hasLiveBone = looksLikeWorldPos(liveHead) || looksLikeWorldPos(liveHip);
        if (hasLiveBone) {
            if (CurHP <= 0 && MaxHP <= 0) {
                CurHP = 200;
                MaxHP = 200;
            } else if (MaxHP <= 0) {
                MaxHP = 200;
                if (CurHP <= 0) CurHP = 200;
            }
        }
        const bool hpUnreadable = (CurHP == 0 && MaxHP == 0);
        const bool hpGarbage = (MaxHP < 0 || MaxHP > 2000 || CurHP > 2000 ||
                                (MaxHP > 0 && CurHP > MaxHP + 50));
        const bool fullyDead = (!hasLiveBone && !hpUnreadable && CurHP <= 0);
        if (!hasLiveBone && (hpGarbage || hpUnreadable || fullyDead || MaxHP <= 0)) {
            markGhostDead((fullyDead || hpUnreadable || MaxHP <= 0) ? 120 : 45);
            continue;
        }
        {
            uint64_t uid = ReadAddr<uint64_t>(PawnObject + kUserID);
            COW_GamePlay_PlayerID_o pid = ReadAddr<COW_GamePlay_PlayerID_o>(PawnObject + kPlayerID);
            if (uid == 0 && pid.m_Value == 0 && pid.m_ID == 0 && !isBot && !hasLiveBone) {
                markGhostDead(90);
                continue;
            }
        }
        Vector3 liveRoot = ReadPlayerRootTransform(PawnObject);
        Vector3 mountPos{};
        const bool enemyMounted = IsActivelyMounted(PawnObject, &mountPos);
        if (!enemyMounted) {
            uint64_t vOnly = ReadVehicleIAmIn(PawnObject);
            if (isVaildPtr(vOnly)) {
                Vector3 vp = ResolveVehicleWorldPos(vOnly);
                if (looksLikeWorldPos(vp)) {
                    mountPos = vp;
                    mountPos.y += 0.95f;
                }
            }
        }
        const bool haveMountPos = looksLikeWorldPos(mountPos);
        float liveBodyLen = 0.f;
        bool haveLiveBody = false;
        if (looksLikeWorldPos(liveHead) && looksLikeWorldPos(liveHip)) {
            liveBodyLen = Vector3::Distance(liveHead, liveHip);
            haveLiveBody = true;
        }
        const bool bodyCollapsed = haveLiveBody && liveBodyLen < 0.35f;
        const bool treatAsVehicle = enemyMounted || haveMountPos;
        const bool anyLiveAnchor =
            looksLikeWorldPos(liveHead) || looksLikeWorldPos(liveHip) ||
            looksLikeWorldPos(liveRoot) || haveMountPos;
        if (!anyLiveAnchor) {
            markGhostDead(60);
            continue;
        }
        if (!treatAsVehicle && bodyCollapsed) {
            bool expectStanding = !isKnocked;
            bool rootSaysUpright = false;
            if (looksLikeWorldPos(liveRoot) && looksLikeWorldPos(liveHead)) {
                float dy = liveHead.y - liveRoot.y;
                if (dy >= 1.15f) rootSaysUpright = true;
            }
            if (expectStanding && (rootSaysUpright || !looksLikeWorldPos(liveRoot))) {
                markGhostDead(45);
                continue;
            }
        }
        if (!treatAsVehicle && !looksLikeWorldPos(liveHead) && !looksLikeWorldPos(liveHip) &&
            !looksLikeWorldPos(liveRoot)) {
            markGhostDead(60);
            continue;
        }
        Vector3 headBonePos{};
        bool headFromLive = false;
        if (looksLikeWorldPos(liveHead)) {
            headBonePos = liveHead;
            headFromLive = true;
        } else if (haveMountPos) {
            headBonePos = mountPos;
            headFromLive = true;
        } else if (looksLikeWorldPos(liveRoot)) {
            headBonePos = liveRoot;
            headBonePos.y += treatAsVehicle ? 0.95f : 0.85f;
            headFromLive = true;
        } else if (looksLikeWorldPos(liveHip)) {
            headBonePos = liveHip;
            headBonePos.y += 0.55f;
            headFromLive = true;
        }
        if (!headFromLive || IsZeroVec(headBonePos) || !looksLikeWorldPos(headBonePos)) {
            markGhostDead(45);
            continue;
        }
        if (fabsf(headBonePos.x) < 0.5f && fabsf(headBonePos.z) < 0.5f && fabsf(headBonePos.y) < 2.0f) {
            markGhostDead(45);
            continue;
        }
        if (looksLikeWorldPos(liveRoot)) {
            float dx = headBonePos.x - liveRoot.x;
            float dz = headBonePos.z - liveRoot.z;
            float dXZ = sqrtf(dx * dx + dz * dz);
            if (dXZ > (treatAsVehicle ? 8.0f : 4.5f)) {
                markGhostDead(30);
                continue;
            }
        }
        int headSrcNow = 0;
        int hipSrcNow  = 0;
        Vector3 espHipPos{};
        if (looksLikeWorldPos(liveHip) &&
            Vector3::Distance(headBonePos, liveHip) >= 0.28f &&
            Vector3::Distance(headBonePos, liveHip) < 2.8f) {
            espHipPos = liveHip;
            hipSrcNow = 2;
        } else {
            espHipPos = headBonePos;
            espHipPos.y -= treatAsVehicle ? 1.05f : 0.85f;
            hipSrcNow = 4;
        }
        if (headFromLive) {
            if (looksLikeWorldPos(liveHead) && Vector3::Distance(headBonePos, liveHead) < 0.01f) headSrcNow = 1;
            else if (haveMountPos && Vector3::Distance(headBonePos, mountPos) < 0.01f) headSrcNow = 2;
            else if (looksLikeWorldPos(liveRoot)) headSrcNow = 3;
            else headSrcNow = 4;
        }
        PosTrack &trDisp = g_posTrack[PosTrackSlot(PawnObject)];
        const bool headSrcFlip = (trDisp.lastHeadSrcDisp != 0 && headSrcNow != 0 && trDisp.lastHeadSrcDisp != headSrcNow);
        const bool hipSrcFlip  = (trDisp.lastHipSrcDisp  != 0 && hipSrcNow  != 0 && trDisp.lastHipSrcDisp  != hipSrcNow);
        Vector3 preSmoothHead = headBonePos;
        Vector3 preSmoothHip  = espHipPos;
        headBonePos = EspSmoothDisplayPos(PawnObject, headBonePos, true);
        espHipPos   = EspSmoothDisplayPos(PawnObject, espHipPos, false);
        if (headSrcFlip || hipSrcFlip) {
            if (looksLikeWorldPos(preSmoothHead)) headBonePos = preSmoothHead;
            if (looksLikeWorldPos(preSmoothHip))  espHipPos   = preSmoothHip;
        }
        trDisp.lastHeadSrcDisp = headSrcNow ? headSrcNow : trDisp.lastHeadSrcDisp;
        trDisp.lastHipSrcDisp  = hipSrcNow  ? hipSrcNow  : trDisp.lastHipSrcDisp;
        {
            float bodyLen = Vector3::Distance(headBonePos, espHipPos);
            float dy = headBonePos.y - espHipPos.y;
            if (looksLikeWorldPos(liveHead) && looksLikeWorldPos(liveHip)) {
                float liveBL = Vector3::Distance(liveHead, liveHip);
                if (liveBL >= 0.45f && liveBL <= 1.25f) {
                    if (trDisp.bodyLenHold <= 0 || trDisp.bodyLen <= 0.f) {
                        trDisp.bodyLen = liveBL;
                        trDisp.bodyLenHold = 45;
                    } else {
                        float rel = fabsf(liveBL - trDisp.bodyLen) / fmaxf(trDisp.bodyLen, 0.1f);
                        if (rel < 0.18f) {
                            trDisp.bodyLen = trDisp.bodyLen * 0.85f + liveBL * 0.15f;
                            trDisp.bodyLenHold = 45;
                        } else if (rel > 0.35f) {
                            trDisp.bodyLen = liveBL;
                            trDisp.bodyLenHold = 30;
                        }
                    }
                }
            }
            if (trDisp.bodyLenHold > 0) trDisp.bodyLenHold--;
            const bool haveStableBL = (trDisp.bodyLen >= 0.45f && trDisp.bodyLen <= 1.25f);
            if (bodyLen < 0.28f || bodyLen > 2.6f || dy < 0.15f || dy > 1.35f) {
                if (haveStableBL) {
                    espHipPos = headBonePos;
                    espHipPos.y -= trDisp.bodyLen;
                } else {
                    espHipPos = headBonePos;
                    espHipPos.y -= treatAsVehicle ? 1.05f : 0.85f;
                }
            } else if (haveStableBL) {
                float want = trDisp.bodyLen;
                float cur  = bodyLen;
                if (fabsf(cur - want) > 0.22f) {
                    espHipPos = headBonePos;
                    espHipPos.y -= want;
                }
            }
        }
        float tempDisForAim = useLocalDistance
            ? Vector3::Distance(myLocation, headBonePos)
            : 0.0f;
        if (useLocalDistance && tempDisForAim > maxPossibleDistance) continue;
        if (useLocalDistance && !treatAsVehicle && tempDisForAim < 0.35f) continue;
        Vector3 aimPos = headBonePos;
        bool canAimThisPawn = false;
        if (isAimbot || useAssist || useSilent) {
            Vector3 bone = (useSilent && !isAimbot && !useAssist)
                ? ResolveSilentAimWorldPos(PawnObject, aimPosition)
                : GetAimTargetPosMode(PawnObject, aimPosition, tempDisForAim);
            if (IsZeroVec(bone) || !looksLikeWorldPos(bone)) {
                bone = ResolveSilentAimWorldPos(PawnObject, aimPosition);
            }
            if (IsZeroVec(bone) || !looksLikeWorldPos(bone)) bone = headBonePos;
            const float maxBoneDist = (treatAsVehicle ? 3.5f : 2.6f);
            if (!IsZeroVec(bone) && looksLikeWorldPos(bone) &&
                Vector3::Distance(bone, headBonePos) < maxBoneDist) {
                aimPos = bone;
                if (aimPosition == 0) headBonePos = bone;
                canAimThisPawn = true;
            }
        } else {
            canAimThisPawn = false;
        }
        float dis = useLocalDistance
            ? Vector3::Distance(myLocation, IsZeroVec(aimPos) ? headBonePos : aimPos)
            : tempDisForAim;
        static bool s_espBotPref = false;
        static int s_espBotFrame = -1;
        if (s_espBotFrame != g_cacheFrameCounter) {
            s_espBotFrame = g_cacheFrameCounter;
            s_espBotPref = ESPPrefsBool(@"EspBot", NO);
        }
        bool shouldCountEnemy = true;
        if (isBot && !s_espBotPref) shouldCountEnemy = false;
        if (CurHP <= 0) shouldCountEnemy = false;
        float countDis = dis;
        float countLimit = fmaxf(espDistanceLimit, 1.0f);
        if (shouldCountEnemy && countDis <= countLimit && countDis >= 1.5f) {
            uint64_t uid = ReadAddr<uint64_t>(PawnObject + kUserID);
            uint64_t dedupKey = (uid != 0) ? uid : PawnObject;
            static uint64_t s_countSeen[128];
            static int s_countFrame = -1;
            static int s_countN = 0;
            if (s_countFrame != g_cacheFrameCounter) {
                s_countFrame = g_cacheFrameCounter;
                s_countN = 0;
            }
            bool dup = false;
            for (int ci = 0; ci < s_countN; ci++) {
                if (s_countSeen[ci] == dedupKey) { dup = true; break; }
            }
            if (!dup && s_countN < 128) {
                s_countSeen[s_countN++] = dedupKey;
                if (isBot) stats.botCount++;
                else stats.realCount++;
            }
        }
        const bool mounted = treatAsVehicle;
        bool espVisible = !isEspCheckVisible || isFPP || isCamVis || isKnocked || mounted;
        bool wantDraw = false;
        if ((isESP || isESP2) && (espVisible || (isBot && isEspBot) || mounted)) {
            if (!(isBot && !isEspBot && !mounted)) {
                float espDrawLimit = mounted ? fmaxf(espDistanceLimit, 250.0f) : espDistanceLimit;
                if (!useLocalDistance || dis <= espDrawLimit || (mounted && dis < 8.0f)) {
                    wantDraw = true;
                }
            }
        }
        if (CurHP <= 0) continue;
        if (snapN < 128) {
            EspPawnSnap &s = snaps[snapN++];
            s.pawn = PawnObject;
            s.head = headBonePos;
            s.hip = espHipPos;
            s.aimPos = aimPos;
            s.dis = dis;
            s.curHP = CurHP;
            s.maxHP = MaxHP > 0 ? MaxHP : 200;
            s.isBot = isBot;
            s.isKnocked = isKnocked;
            s.treatAsVehicle = treatAsVehicle;
            s.canAim = canAimThisPawn;
            s.wantDraw = wantDraw;
        }
    }
    static int s_countDiagLog = 0;
    if (++s_countDiagLog % 60 == 1) {
        NSLog(@"[ESP-COUNT] match=0x%llx dict=0x%llx entries=0x%llx cap=%d stride=0x%llx voff=0x%llx snapN=%d (real=%d, bot=%d)",
              (unsigned long long)match, (unsigned long long)playerDict,
              (unsigned long long)entriesArr, slotCap,
              (unsigned long long)entryStride, (unsigned long long)entryValueOff,
              snapN, stats.realCount, stats.botCount);
    }
    if (!GetViewMatrixInto(camera, matrixData)) {
        static int s_noVpLog = 0;
        if (++s_noVpLog % 60 == 1) NSLog(@"[ESP] NO VIEW MATRIX camera=0x%llx", (unsigned long long)camera);
        CGPathRelease(aNumBGPath); CGPathRelease(aNumGPath);
        CGPathRelease(aNumOPath);  CGPathRelease(aNumRPath);
        if (stats.aimAssistPath) { CGPathRelease(stats.aimAssistPath); stats.aimAssistPath = NULL; }
        return stats;
    }
    const int crowdN = snapN;
    const bool crowded = crowdN >= 18;
    const bool veryCrowded = crowdN >= 28;
    if (crowded) {
        float matrixRefresh[16];
        if (GetViewMatrixInto(camera, matrixRefresh)) {
            memcpy(matrixData, matrixRefresh, sizeof(matrixData));
        }
    }
    for (int si = 0; si < snapN; si++) {
        const EspPawnSnap &s = snaps[si];
        if (!s.wantDraw || !isVaildPtr(s.pawn)) continue;
        Vector3 aimW = looksLikeWorldPos(s.aimPos) ? s.aimPos : s.head;
        Vector3 w2sAimCheck = WorldToScreenLayer(aimW, matrixData, (float)matrixVpWidth, (float)matrixVpHeight, (float)viewWidth, (float)viewHeight);
        bool isOnScreen = (w2sAimCheck.z > 0.001f && w2sAimCheck.x >= 0 && w2sAimCheck.x <= viewWidth && w2sAimCheck.y >= 0 && w2sAimCheck.y <= viewHeight);
        const float alertMaxDis = veryCrowded ? 70.f : (crowded ? 95.f : 120.f);
        if ((isAlert360 || isAlertNum) && !isOnScreen && s.dis < alertMaxDis) {
            float viewX = aimW.x * matrixData[0] + aimW.y * matrixData[4] + aimW.z * matrixData[8] + matrixData[12];
            float viewY = aimW.x * matrixData[1] + aimW.y * matrixData[5] + aimW.z * matrixData[9] + matrixData[13];
            float viewZ = aimW.x * matrixData[2] + aimW.y * matrixData[6] + aimW.z * matrixData[10] + matrixData[14];
            if (viewZ < 0.0f) { viewX *= -1.0f; viewY *= -1.0f; }
            float angle = atan2(-viewY, viewX);
            if (isAlert360) {
                float alertRadius = (viewHeight < viewWidth ? viewHeight : viewWidth) / 2.0f - 55.0f;
                float tipX = screenCenter.x + cos(angle) * alertRadius;
                float tipY = screenCenter.y + sin(angle) * alertRadius;
                float tailRadius = alertRadius - 18.0f;
                float leftX = screenCenter.x + cos(angle - 0.09f) * tailRadius;
                float leftY = screenCenter.y + sin(angle - 0.09f) * tailRadius;
                float rightX = screenCenter.x + cos(angle + 0.09f) * tailRadius;
                float rightY = screenCenter.y + sin(angle + 0.09f) * tailRadius;
                CGMutablePathRef alertPath = s.isKnocked ? buffers->snaplineKnockedPath : (s.isBot ? buffers->snaplineBotPath : buffers->snaplinePath);
                CGMutablePathRef tempTriangle = CGPathCreateMutable();
                CGPathMoveToPoint(tempTriangle, NULL, leftX, leftY);
                CGPathAddLineToPoint(tempTriangle, NULL, tipX, tipY);
                CGPathAddLineToPoint(tempTriangle, NULL, rightX, rightY);
                CGPathAddLineToPoint(tempTriangle, NULL, leftX, leftY);
                CGPathAddPath(alertPath, NULL, tempTriangle);
                CGPathRelease(tempTriangle);
                if (s.isKnocked) buffers->snaplineKnockedDirty = YES;
                else if (s.isBot) buffers->snaplineBotDirty = YES;
                else buffers->snaplineDirty = YES;
            }
            if (isAlertNum && !(veryCrowded && s.dis > 55.f)) {
                float dx = cos(angle); float dy = sin(angle); float m = dy / dx;
                float radius = 14.0f; float padding = radius + 6.0f;
                float x_edge, y_edge;
                if (dx > 0) x_edge = screenCenter.x - padding;
                else        x_edge = -(screenCenter.x - padding);
                y_edge = x_edge * m;
                if (fabsf(y_edge) > screenCenter.y - padding) {
                    if (dy > 0) y_edge = screenCenter.y - padding;
                    else        y_edge = -(screenCenter.y - padding);
                    x_edge = y_edge / m;
                }
                float edgeX = screenCenter.x + x_edge;
                float edgeY = screenCenter.y + y_edge;
                CGPathAddEllipseInRect(aNumBGPath, NULL, CGRectMake(edgeX - radius, edgeY - radius, radius * 2.0f, radius * 2.0f));
                float hpPercent = Clamp01f((float)s.curHP / (float)s.maxHP);
                if (hpPercent <= 0.0f) hpPercent = 0.01f;
                float startAngle = -M_PI_2;
                float endAngle = startAngle + (M_PI * 2.0f * hpPercent);
                CGMutablePathRef targetArc = aNumGPath;
                if (hpPercent < 0.35f || s.isKnocked) targetArc = aNumRPath;
                else if (hpPercent < 0.70f) targetArc = aNumOPath;
                CGMutablePathRef tempArc = CGPathCreateMutable();
                CGPathAddArc(tempArc, NULL, edgeX, edgeY, radius, startAngle, endAngle, false);
                CGPathAddPath(targetArc, NULL, tempArc);
                CGPathRelease(tempArc);
                NSString *distText = [NSString stringWithFormat:@"[%dM]", (int)s.dis];
                CGRect textFrame = CGRectMake(edgeX - radius, edgeY - 4.5f, radius * 2.0f, 10.0f);
                ESPViewAddTextCallback((__bridge void *)self, distText, textFrame, [UIColor whiteColor], 8.0f, NO);
            }
        }
        if (isESP2) {
            Vector3 HeadPos = s.head;
            if (IsZeroVec(HeadPos) || !looksLikeWorldPos(HeadPos)) continue;
            Vector3 HipPos = s.hip;
            {
                const float bodyLen = (IsZeroVec(HipPos) || !looksLikeWorldPos(HipPos))
                    ? 0.f : Vector3::Distance(HeadPos, HipPos);
                const float dy = HeadPos.y - HipPos.y;
                const float dxz = sqrtf((HeadPos.x - HipPos.x) * (HeadPos.x - HipPos.x) +
                                       (HeadPos.z - HipPos.z) * (HeadPos.z - HipPos.z));
                const bool hipOk = bodyLen >= 0.30f && bodyLen <= 1.35f &&
                                   dy >= 0.20f && dy <= 1.25f && dxz <= 0.85f;
                if (!hipOk) {
                    HipPos = HeadPos;
                    HipPos.y -= s.treatAsVehicle ? 1.00f : 0.88f;
                }
            }
            Vector3 FootPos = HipPos;
            FootPos.y -= s.treatAsVehicle ? 0.55f : 0.92f;
            HeadPos.y += 0.08f;
            Vector3 w2sHead = WorldToScreenLayer(HeadPos, matrixData, (float)matrixVpWidth, (float)matrixVpHeight, (float)viewWidth, (float)viewHeight);
            Vector3 w2sHip = WorldToScreenLayer(HipPos, matrixData, (float)matrixVpWidth, (float)matrixVpHeight, (float)viewWidth, (float)viewHeight);
            Vector3 w2sFoot = WorldToScreenLayer(FootPos, matrixData, (float)matrixVpWidth, (float)matrixVpHeight, (float)viewWidth, (float)viewHeight);
            const float ep = viewWidth * 0.35f;
            if (w2sHead.z > 0.001f) {
                float topY = w2sHead.y;
                float bottomY = topY;
                bool haveBot = false;
                if (w2sFoot.z > 0.001f) { bottomY = w2sFoot.y; haveBot = true; }
                if (w2sHip.z > 0.001f) {
                    float hipY = w2sHip.y;
                    if (!haveBot) { bottomY = hipY; haveBot = true; }
                    else bottomY = fmaxf(bottomY, hipY);
                }
                if (!haveBot) bottomY = topY + fmaxf(viewHeight * 0.055f, 20.f);
                if (bottomY < topY + 6.0f) bottomY = topY + fmaxf(viewHeight * 0.055f, 20.f);
                float hipH = (w2sHip.z > 0.001f) ? fabsf(w2sHip.y - w2sHead.y) : 0.f;
                float ratioH = (hipH > 3.f)
                    ? (s.treatAsVehicle ? hipH * 1.48f : hipH * 2.02f)
                    : 0.f;
                float rawH = bottomY - topY;
                float boxHeight = (ratioH > 4.f) ? ratioH : rawH;
                if (ratioH > 4.f && rawH > 4.f) {
                    float rel = fabsf(rawH - ratioH) / ratioH;
                    if (rel < 0.18f) boxHeight = ratioH * 0.65f + rawH * 0.35f;
                    else boxHeight = ratioH;
                }
                float maxH = fminf(
                    (hipH > 3.f) ? (s.treatAsVehicle ? hipH * 1.70f : hipH * 2.25f)
                                 : viewHeight * 0.20f,
                    viewHeight * (s.treatAsVehicle ? 0.20f : 0.34f));
                if (boxHeight > maxH) boxHeight = maxH;
                if (boxHeight < (s.treatAsVehicle ? 14.0f : 7.0f))
                    boxHeight = s.treatAsVehicle ? fmaxf(14.0f, viewHeight * 0.04f) : 7.0f;
                float boxWidth = fmaxf(4.5f, boxHeight * (s.treatAsVehicle ? 0.48f : 0.34f));
                float centerX = (w2sHip.z > 0.001f)
                    ? (w2sHip.x * 0.82f + w2sHead.x * 0.18f)
                    : w2sHead.x;
                SmoothBoxScreen(s.pawn, topY, centerX, boxHeight, boxWidth);
                float padY = fmaxf(boxHeight * 0.015f, 0.8f);
                float boxY = topY - padY;
                boxHeight += padY * 2.0f;
                float boxX = centerX - boxWidth * 0.5f;
                const float hardM = fmaxf(viewWidth, viewHeight) * 0.9f;
                if (centerX >= -hardM && centerX <= viewWidth + hardM &&
                    boxY >= -hardM && boxY <= viewHeight + hardM) {
                    CGMutablePathRef currentBoxPath = buffers->boxPath;
                    CGMutablePathRef currentLinePath = buffers->snaplinePath;
                    if (s.isKnocked) {
                        currentBoxPath = buffers->boxKnockedPath;
                        currentLinePath = buffers->snaplineKnockedPath;
                        buffers->boxKnockedDirty = YES;
                        buffers->snaplineKnockedDirty = YES;
                    } else if (s.isBot) {
                        currentBoxPath = buffers->boxBotPath;
                        currentLinePath = buffers->snaplineBotPath;
                        buffers->boxBotDirty = YES;
                        buffers->snaplineBotDirty = YES;
                    } else {
                        buffers->boxDirty = YES;
                        buffers->snaplineDirty = YES;
                    }
                    CGPathAddRect(currentBoxPath, NULL, CGRectMake(boxX, boxY, boxWidth, boxHeight));
                    CGPathMoveToPoint(currentLinePath, NULL, screenCenter.x, 45.0f);
                    CGPathAddLineToPoint(currentLinePath, NULL, centerX, boxY);
                    const bool liteOnScreen = (w2sHead.x >= -ep && w2sHead.x <= viewWidth + ep &&
                                               w2sHead.y >= -ep && w2sHead.y <= viewHeight + ep);
                    if (liteOnScreen && s.maxHP > 0) {
                        float hpPerc = Clamp01f((float)s.curHP / (float)s.maxHP);
                        CGMutablePathRef currentHpPath = buffers->hpFillGreenPath;
                        bool *hpDirtyFlag = &buffers->hpFillGreenDirty;
                        if (hpPerc <= 0.35f) { currentHpPath = buffers->hpFillRedPath; hpDirtyFlag = &buffers->hpFillRedDirty; }
                        else if (hpPerc <= 0.70f) { currentHpPath = buffers->hpFillOrangePath; hpDirtyFlag = &buffers->hpFillOrangeDirty; }
                        float hpBarWidth = fmaxf(1.5f, boxWidth * 0.05f);
                        float hpBarHeight = boxHeight * hpPerc;
                        float hpBarX = boxX + boxWidth;
                        float hpBarY = boxY + (boxHeight - hpBarHeight);
                        CGPathAddRect(buffers->bgFillBlackPath, NULL, CGRectMake(hpBarX, boxY, hpBarWidth, boxHeight));
                        buffers->bgFillBlackDirty = YES;
                        CGPathAddRect(currentHpPath, NULL, CGRectMake(hpBarX, hpBarY, hpBarWidth, hpBarHeight));
                        *hpDirtyFlag = YES;
                    }
                }
            }
        } else if (isESP) {
            if (s.curHP <= 0) continue;
            if (crowded && !isOnScreen && s.dis > (veryCrowded ? 80.f : 120.f)) {
                continue;
            }
            Vector3 hipP = s.hip;
            if (IsZeroVec(hipP) || !looksLikeWorldPos(hipP) ||
                Vector3::Distance(s.head, hipP) < 0.25f) {
                hipP = s.head;
                hipP.y -= s.treatAsVehicle ? 1.05f : 0.85f;
            }
            RenderESPForPawnEx(buffers, ESPViewAddTextCallback, ESPViewAddImageCallback,
                               (__bridge void *)self, s.pawn, s.curHP, s.dis, matrixData,
                               (float)viewWidth, (float)viewHeight, (float)matrixVpWidth, (float)matrixVpHeight,
                               s.head.x, s.head.y, s.head.z,
                               hipP.x, hipP.y, hipP.z,
                               s.isBot ? 1 : 0, s.isKnocked ? 1 : 0);
        }
    }

    // ============================================================
    // AIM SELECTION
    // ============================================================
    const bool allowThroughWall = AimThroughAnyCoverNow();
    if (iAmAlive && useAim) {
        for (int si = 0; si < snapN; si++) {
            const EspPawnSnap &s = snaps[si];
            if (!s.canAim || s.dis > aimDistance) continue;
            uint64_t PawnObject = s.pawn;
            Vector3 aimPos = s.aimPos;
            Vector3 headBonePos = s.head;
            float dis = s.dis;
            int CurHP = s.curHP;
            bool isBot = s.isBot;
            bool isKnocked = s.isKnocked;
            Vector3 w2sAim = WorldToScreenLayer(aimPos, matrixData, (float)matrixVpWidth, (float)matrixVpHeight, (float)viewWidth, (float)viewHeight);
            BOOL canConsiderForAim = YES;
            if (CurHP <= 0) canConsiderForAim = NO;
            if (isAimIgnoreKnock && isKnocked) canConsiderForAim = NO;
            if (isAimIgnoreBot && isBot) canConsiderForAim = NO;
            const bool inFront = (w2sAim.z > 0.001f);
            const float pad = 2.0f;
            const bool onScreen = inFront &&
                w2sAim.x >= -pad && w2sAim.x <= viewWidth + pad &&
                w2sAim.y >= -pad && w2sAim.y <= viewHeight + pad;
            if (!allowThroughWall || (!useSphereAim && !silentSphereOnly)) {
                if (!inFront) {
                    canConsiderForAim = NO;
                } else if (!onScreen) {
                    if (!allowThroughWall) {
                        const float wallOffPad = 36.0f;
                        const bool softOn = w2sAim.x >= -wallOffPad && w2sAim.x <= viewWidth + wallOffPad &&
                                           w2sAim.y >= -wallOffPad && w2sAim.y <= viewHeight + wallOffPad;
                        if (!softOn) canConsiderForAim = NO;
                    } else {
                        canConsiderForAim = NO;
                    }
                }
            } else if (useAim180 && !silentSphereOnly) {
                if (!inFront) canConsiderForAim = NO;
            }
            const bool posLos = allowThroughWall
                ? true
                : GameClearLosToEnemy(myPawnObject, PawnObject, aimPos);
            if (!canConsiderForAim) continue;
            float deltaX = 0.f, deltaY = 0.f, distSq = 0.f;
            if (inFront) {
                deltaX = w2sAim.x - screenCenter.x;
                deltaY = w2sAim.y - screenCenter.y;
                distSq = deltaX * deltaX + deltaY * deltaY;
            }
            bool inRange = false;
            if (!allowThroughWall) {
                if (isAimbot && useAim180) {
                    inRange = inFront;
                } else if (isAimbot) {
                    float fovSq = aimFovSq > 1.f ? aimFovSq : (150.f * 150.f);
                    inRange = inFront && (distSq <= fovSq);
                } else if (useAssistOnly || useSilent || silentSphereOnly) {
                    float rSq = fmaxf(assistRadiusSq, aimFovSq > 1.f ? aimFovSq : (150.f * 150.f));
                    inRange = inFront && (distSq <= rSq);
                }
            } else if (useSilent || (isAimbot && useAim360) || silentSphereOnly) {
                inRange = true;
            } else if (isAimbot && useAim180) {
                inRange = inFront;
            } else if (isAimbot) {
                inRange = inFront && (aimFovSq > 0.f) && (distSq <= aimFovSq);
            } else if (useAssistOnly) {
                inRange = inFront && (distSq <= assistRadiusSq);
            }
            if (!inRange) continue;
            float distanceNorm = dis / safeAimDistance;
            float score = 0.0f;
            const bool scoreAsSphere = allowThroughWall && (useSphereAim || useSilent || silentSphereOnly);
            if (scoreAsSphere) {
                if (aimTargetMode == 1) {
                    float hpNorm = fminf((float)CurHP / 200.0f, 1.5f);
                    score = hpNorm * 0.70f + distanceNorm * 0.30f;
                } else {
                    score = distanceNorm;
                }
                if (inFront) {
                    float screenBias = fminf(distSq / (viewWidth * viewWidth + 1.f), 1.f);
                    score = score * 0.85f + screenBias * 0.15f;
                } else if (useAim360 || silentSphereOnly) {
                    score += 0.05f;
                }
            } else {
                float fovSq = fmaxf(aimFovSq > 1.f ? aimFovSq : safeAimFovSq, 1.f);
                float rangeNorm = isAimbot
                    ? (distSq / fovSq)
                    : (distSq / fmaxf(assistRadiusSq, 1.f));
                if (isAimbot || (useAssist && !useAssistOnly)) {
                    if (aimTargetMode == 0) {
                        score = rangeNorm * 0.85f + distanceNorm * 0.15f;
                    } else if (aimTargetMode == 1) {
                        float hpNorm = fminf((float)CurHP / 200.0f, 1.5f);
                        score = hpNorm * 0.65f + rangeNorm * 0.25f + distanceNorm * 0.10f;
                    } else {
                        score = distanceNorm * 0.75f + rangeNorm * 0.25f;
                    }
                } else if (useAssistOnly) {
                    if (aimTargetMode == 0) {
                        score = rangeNorm * 0.90f + distanceNorm * 0.10f;
                    } else if (aimTargetMode == 1) {
                        float hpNorm = fminf((float)CurHP / 200.0f, 1.5f);
                        score = rangeNorm * 0.55f + hpNorm * 0.35f + distanceNorm * 0.10f;
                    } else {
                        score = rangeNorm * 0.45f + distanceNorm * 0.55f;
                    }
                } else {
                    score = rangeNorm;
                }
            }
            if (PawnObject == gAimLockTarget) score *= 0.18f;
            if (isBot && !isAimIgnoreBot) score *= 0.92f;
            Vector3 pickHead = aimPos;
            if (allowThroughWall) {
                if (score < bestAnyScore) {
                    bestAnyScore = score;
                    bestAnyDist = dis;
                    bestAnyVis = true;
                    bestAnyTarget = PawnObject;
                    bestAnyHead = pickHead;
                }
            }
            if (posLos && score < bestLosScore) {
                bestLosScore = score;
                bestLosDist = dis;
                bestLosVis = true;
                bestLosTarget = PawnObject;
                bestLosHead = pickHead;
                if (!allowThroughWall && score < bestAnyScore) {
                    bestAnyScore = score;
                    bestAnyDist = dis;
                    bestAnyVis = true;
                    bestAnyTarget = PawnObject;
                    bestAnyHead = pickHead;
                }
            }
        }
    }
    if (gAimLockTarget != 0) {
        bool stillInFrame = false;
        for (int si = 0; si < snapN; si++) {
            if (snaps[si].pawn == gAimLockTarget) { stillInFrame = true; break; }
        }
        if (!stillInFrame) {
            gAimLockTarget = 0;
            gAimLockLostFrames = 0;
            s_lockHoldFrames = 0;
        }
    }
    if (g_silentLockedEnemy != 0) {
        bool stillInFrame = false;
        for (int si = 0; si < snapN; si++) {
            if (snaps[si].pawn == g_silentLockedEnemy) { stillInFrame = true; break; }
        }
        if (!stillInFrame) {
            SilentAimClearTarget();
        }
    }
    if (s_lastAimPawn != 0) {
        bool stillInFrame = false;
        for (int si = 0; si < snapN; si++) {
            if (snaps[si].pawn == s_lastAimPawn) { stillInFrame = true; break; }
        }
        if (!stillInFrame) {
            s_lastAimPawn = 0;
        }
    }
    uint64_t rawBestTarget = 0;
    Vector3 rawBestHead{};
    float rawBestDist = FLT_MAX;
    float rawBestScore = FLT_MAX;
    bool rawBestVis = false;
    if (!allowThroughWall) {
        if (bestLosTarget != 0) {
            rawBestTarget = bestLosTarget;
            rawBestHead = bestLosHead;
            rawBestDist = bestLosDist;
            rawBestScore = bestLosScore;
            rawBestVis = true;
        } else if (bestAnyTarget != 0) {
            rawBestTarget = bestAnyTarget;
            rawBestHead = bestAnyHead;
            rawBestDist = bestAnyDist;
            rawBestScore = bestAnyScore;
            rawBestVis = true;
        }
    } else if (bestAnyTarget != 0) {
        rawBestTarget = bestAnyTarget;
        rawBestHead = bestAnyHead;
        rawBestDist = bestAnyDist;
        rawBestScore = bestAnyScore;
        rawBestVis = bestAnyVis;
    }
    bestTarget = rawBestTarget;
    bestHeadPos = rawBestHead;
    bestDistance = rawBestDist;
    bestScore = rawBestScore;
    isVis = rawBestVis;
    static float s_lockScore = FLT_MAX; (void)s_lockScore;
    const bool firingNow = isVaildPtr(myPawnObject) && get_IsFiring(myPawnObject);
    if (gAimLockTarget != 0 && isVaildPtr(gAimLockTarget)) {
        float lockedScore = FLT_MAX;
        Vector3 lockedHead{};
        float lockedDist = FLT_MAX;
        bool lockedFound = false;
        bool lockedLos = false;
        if (rawBestTarget == gAimLockTarget) {
            Vector3 lb = rawBestHead;
            if (IsZeroVec(lb) || !looksLikeWorldPos(lb)) {
                lb = GetAimTargetPosMode(gAimLockTarget, aimPosition, aimDistance);
            }
            const bool liveLos = allowThroughWall
                ? true
                : GameClearLosToEnemy(myPawnObject, gAimLockTarget, lb);
            if (liveLos) {
                lockedFound = true;
                lockedScore = rawBestScore;
                lockedHead = rawBestHead;
                lockedDist = rawBestDist;
                lockedLos = true;
            }
        } else if (bestLosTarget == gAimLockTarget) {
            Vector3 lb = bestLosHead;
            if (IsZeroVec(lb) || !looksLikeWorldPos(lb)) {
                lb = GetAimTargetPosMode(gAimLockTarget, aimPosition, aimDistance);
            }
            const bool liveLos = allowThroughWall
                ? true
                : GameClearLosToEnemy(myPawnObject, gAimLockTarget, lb);
            if (liveLos) {
                lockedFound = true;
                lockedScore = bestLosScore;
                lockedHead = bestLosHead;
                lockedDist = bestLosDist;
                lockedLos = true;
            }
        }
        if (!lockedFound) {
            int lhp = get_CurHP(gAimLockTarget);
            int lmax = get_MaxHP(gAimLockTarget);
            const bool lknock = get_IsKnockedDown(gAimLockTarget);
            Vector3 liveHeadTarget = getPositionExt(getHead(gAimLockTarget));
            const bool hasLiveHead = looksLikeWorldPos(liveHeadTarget);
            if (hasLiveHead && lhp <= 0 && lmax <= 0) { lhp = 200; lmax = 200; }
            const bool lhpBad = !hasLiveHead && (lmax <= 0 || lmax > 2000 || (lhp == 0 && lmax == 0) || (lhp <= 0));
            if (!lhpBad && (lhp > 0) && !(isAimIgnoreKnock && lknock) &&
                !(isAimIgnoreBot && get_IsBot(gAimLockTarget))) {
                Vector3 lb = GetAimTargetPosMode(gAimLockTarget, aimPosition, aimDistance);
                if (IsZeroVec(lb) || !looksLikeWorldPos(lb)) {
                    if (hasLiveHead) lb = liveHeadTarget;
                }
                if (!IsZeroVec(lb) && looksLikeWorldPos(lb)) {
                    float ld = iAmAlive ? Vector3::Distance(myLocation, lb) : 10.f;
                    if (ld <= aimDistance + 5.f && ld >= 0.15f) {
                        Vector3 w2s = WorldToScreenLayer(lb, matrixData, (float)matrixVpWidth, (float)matrixVpHeight,
                                                        (float)viewWidth, (float)viewHeight);
                        const bool inF = w2s.z > 0.001f;
                        float dsq = 0.f;
                        if (inF) {
                            float dx = w2s.x - screenCenter.x, dy = w2s.y - screenCenter.y;
                            dsq = dx*dx + dy*dy;
                        }
                        bool inR = false;
                        if (!allowThroughWall) {
                            if (isAimbot && useAim180) inR = inF;
                            else if (isAimbot) {
                                float fovSq = aimFovSq > 1.f ? aimFovSq : (150.f * 150.f);
                                inR = inF && (dsq <= fovSq * 2.25f);
                            } else {
                                inR = inF && (dsq <= assistRadiusSq * 1.5f);
                            }
                        } else if (useSilent || (isAimbot && useAim360) || silentSphereOnly) {
                            inR = true;
                        } else if (isAimbot && useAim180) {
                            inR = inF;
                        } else if (isAimbot) {
                            float fovSq = aimFovSq > 1.f ? aimFovSq : (150.f * 150.f);
                            inR = inF && (dsq <= fovSq * 2.25f);
                        } else {
                            inR = inF && (dsq <= assistRadiusSq * 1.5f);
                        }
                        if (inR) {
                            const bool liveLos = allowThroughWall
                                ? true
                                : GameClearLosToEnemy(myPawnObject, gAimLockTarget, lb);
                            if (liveLos) {
                                float distanceNorm = ld / fmaxf(aimDistance, 1.f);
                                float fovSq = fmaxf(aimFovSq > 1.f ? aimFovSq : (150.f * 150.f), 1.f);
                                float rangeNorm = isAimbot ? (dsq / fovSq) : (dsq / fmaxf(assistRadiusSq, 1.f));
                                float sc = rangeNorm * 0.85f + distanceNorm * 0.15f;
                                sc *= 0.18f;
                                lockedScore = sc;
                                lockedHead = lb;
                                lockedDist = ld;
                                lockedLos = true;
                                lockedFound = true;
                            }
                        }
                    }
                }
            }
        }
        if (lockedFound) {
            const float switchRatio = firingNow ? 0.45f : 0.62f;
            bool keepLock = true;
            if (!allowThroughWall && !lockedLos) {
                keepLock = false;
            } else if (rawBestTarget != 0 && rawBestTarget != gAimLockTarget) {
                float lockedUnbias = lockedScore / 0.18f;
                if (rawBestScore < lockedUnbias * switchRatio) {
                    keepLock = false;
                }
            } else if (rawBestTarget == 0) {
                keepLock = true;
            }
            if (keepLock || allowThroughWall || lockedLos) {
                if (s_lockHoldFrames < 8) keepLock = true;
                if (firingNow && s_lockHoldFrames < 14) keepLock = true;
            }
            if (!allowThroughWall && !lockedLos) keepLock = false;
            if (keepLock) {
                bestTarget = gAimLockTarget;
                bestHeadPos = lockedHead;
                bestDistance = lockedDist;
                bestScore = lockedScore;
                isVis = lockedLos;
                s_lockScore = lockedScore;
                s_lockHoldFrames++;
            } else {
                bestTarget = rawBestTarget;
                bestHeadPos = rawBestHead;
                bestDistance = rawBestDist;
                bestScore = rawBestScore;
                isVis = rawBestVis;
                s_lockScore = rawBestScore;
                s_lockHoldFrames = 0;
            }
        } else {
            gAimLockLostFrames++;
            if (gAimLockLostFrames <= kAimLockMaxLostFrames && rawBestTarget == 0) {
                bestTarget = 0;
            } else {
                bestTarget = rawBestTarget;
                bestHeadPos = rawBestHead;
                bestDistance = rawBestDist;
                bestScore = rawBestScore;
                isVis = rawBestVis;
                s_lockHoldFrames = 0;
            }
        }
    } else if (rawBestTarget != 0) {
        bestTarget = rawBestTarget;
        bestHeadPos = rawBestHead;
        bestDistance = rawBestDist;
        bestScore = rawBestScore;
        isVis = rawBestVis;
        s_lockHoldFrames = 0;
        s_lockScore = rawBestScore;
    }
    auto AimTargetStillValid = [&](uint64_t pawn) -> bool {
        if (!isVaildPtr(pawn)) return false;
        int hp = get_CurHP(pawn);
        int maxHp = get_MaxHP(pawn);
        const bool knocked = get_IsKnockedDown(pawn);
        Vector3 liveHeadCheck = getPositionExt(getHead(pawn));
        const bool hasLiveHead = looksLikeWorldPos(liveHeadCheck);
        if (hasLiveHead && hp <= 0 && maxHp <= 0) {
            hp = 200; maxHp = 200;
        } else if (hasLiveHead && maxHp <= 0) {
            maxHp = 200; if (hp <= 0) hp = 200;
        }
        if (!hasLiveHead && (maxHp <= 0 || maxHp > 2000)) return false;
        if (!hasLiveHead && (hp == 0 && maxHp == 0)) return false;
        if (!hasLiveHead && (hp <= 0)) return false;
        if (hp > 2000 || (maxHp > 0 && hp > maxHp + 50)) return false;
        if (isAimIgnoreKnock && knocked) return false;
        if (isAimIgnoreBot && get_IsBot(pawn)) return false;
        Vector3 bone = (useSilent && !isAimbot && !useAssist)
            ? ResolveSilentAimWorldPos(pawn, aimPosition)
            : GetAimTargetPosMode(pawn, aimPosition, bestDistance);
        if (IsZeroVec(bone) || !looksLikeWorldPos(bone)) {
            Vector3 liveHead = getPositionExt(getHead(pawn));
            if (looksLikeWorldPos(liveHead)) bone = liveHead;
            else {
                Vector3 liveRoot = ReadPlayerRootTransform(pawn);
                Vector3 mount{};
                if (IsActivelyMounted(pawn, &mount) && looksLikeWorldPos(mount)) bone = mount;
                else if (looksLikeWorldPos(liveRoot)) {
                    bone = liveRoot;
                    bone.y += 0.85f;
                } else {
                    return false;
                }
            }
        }
        if (IsZeroVec(bone) || !looksLikeWorldPos(bone)) return false;
        if (fabsf(bone.x) < 0.5f && fabsf(bone.z) < 0.5f && fabsf(bone.y) < 2.0f) return false;
        {
            Vector3 lh = getPositionExt(getHead(pawn));
            Vector3 lp = getPositionExt(getHip(pawn));
            Vector3 mount{};
            const bool mounted = IsActivelyMounted(pawn, &mount) || looksLikeWorldPos(mount);
            if (!mounted && looksLikeWorldPos(lh) && looksLikeWorldPos(lp) &&
                Vector3::Distance(lh, lp) < 0.35f && !knocked) {
                return false;
            }
        }
        if (!allowThroughWall && !GameClearLosToEnemy(myPawnObject, pawn, bone)) return false;
        if (!allowThroughWall) {
            Vector3 w2s = WorldToScreenLayer(bone, matrixData, (float)matrixVpWidth, (float)matrixVpHeight,
                                            (float)viewWidth, (float)viewHeight);
            const float pad = 48.0f;
            if (w2s.z <= 0.001f ||
                w2s.x < -pad || w2s.x > viewWidth + pad ||
                w2s.y < -pad || w2s.y > viewHeight + pad) {
                return false;
            }
            const bool stickFighting = isVaildPtr(myPawnObject) && get_IsFiring(myPawnObject);
            if (isAimbot && !useAim180 && !stickFighting) {
                float dx = w2s.x - screenCenter.x;
                float dy = w2s.y - screenCenter.y;
                float fovSq = aimFovSq > 1.f ? aimFovSq : (150.f * 150.f);
                if ((dx * dx + dy * dy) > fovSq * 2.25f) return false;
            }
        }
        if (iAmAlive) {
            float d = Vector3::Distance(myLocation, bone);
            if (d < 0.15f || d > aimDistance + 5.0f) return false;
        }
        return true;
    };
    if (bestTarget != 0 && !AimTargetStillValid(bestTarget)) {
        bestTarget = 0;
        isVis = false;
    }
    if (!useAim || !iAmAlive) {
        gAimLockTarget = 0; gAimLockLostFrames = 0;
        s_lockHoldFrames = 0;
        update_aim_assist_legit_tuning(false);
    } else if (bestTarget != 0) {
        if (gAimLockTarget != bestTarget) s_lockHoldFrames = 0;
        gAimLockTarget = bestTarget;
        gAimLockLostFrames = 0;
    } else {
        gAimLockTarget = 0; gAimLockLostFrames = 0;
        s_lockHoldFrames = 0;
    }
    static uint64_t s_lastAimPawnLocal = 0;
    bool rawScope = isVaildPtr(myPawnObject) ? get_IsScoping(myPawnObject) : false;
    bool rawFire  = isVaildPtr(myPawnObject) ? get_IsFiring(myPawnObject) : false;
    bool isFiring  = rawFire;
    bool isScoping = rawScope;
    int trig = triggerMode;
    if (trig < 0) trig = 0;
    if (trig > 3) trig = 3;
    bool shouldActivate = false;
    switch (trig) {
        case 1: shouldActivate = isFiring; break;
        case 2: shouldActivate = isScoping; break;
        case 3: shouldActivate = (isFiring || isScoping); break;
        case 0:
        default: shouldActivate = true; break;
    }
    if (useAssistOnly) {
        shouldActivate = true;
    }
    const bool cameraAimActive = (isAimbot || useAssist) && shouldActivate;
    const bool silentActive = useSilent && iAmAlive && isVaildPtr(myPawnObject);
    if (!cameraAimActive) {
        update_aim_assist_legit_tuning(false);
        AimLockClear();
        gAimLockTarget = 0;
        gAimLockLostFrames = 0;
        s_lastAimPawnLocal = 0;
    }
    static float s_lastBulletTrack = 0.f;
    float bulletTrack = 0.f;
    if (isVaildPtr(myPawnObject) && kLastPlayBulletTrackEffectTime) {
        bulletTrack = ReadAddr<float>(myPawnObject + kLastPlayBulletTrackEffectTime);
    }
    const bool bulletJustFired = (bulletTrack > 0.f && bulletTrack != s_lastBulletTrack);
    if (bulletTrack > 0.f) s_lastBulletTrack = bulletTrack;
    const bool fireWindow = isFiring;
    const bool silentFireWindow = isFiring || bulletJustFired;
    if (isVaildPtr(myPawnObject) &&
        ((silentActive && (silentFireWindow || ((g_cacheFrameCounter & 3) == 0))) ||
         (cameraAimActive && (isFiring || isScoping)))) {
        ZeroWeaponScatterForAim(myPawnObject);
    }
    if (silentActive && bestTarget != 0 && AimTargetStillValid(bestTarget)) {
        Vector3 silentBone = ResolveSilentAimWorldPos(bestTarget, aimPosition);
        if (!IsZeroVec(silentBone) && bestDistance >= 0.15f) {
            SilentAimSetTarget(myPawnObject, bestTarget, silentBone, myLocation, aimPosition);
            s_lastAimPawnLocal = bestTarget;
            bestHeadPos = silentBone;
            Vector3 liveBone = ResolveSilentAimWorldPos(bestTarget, aimPosition);
            if (IsZeroVec(liveBone)) liveBone = silentBone;
            {
                std::lock_guard<std::mutex> lk(g_silentMtx);
                g_silentTargetPos = liveBone;
                g_silentFromLoc = myLocation;
            }
            const int bursts = silentFireWindow ? 120 : 4;
            for (int burst = 0; burst < bursts; burst++) {
                if ((burst & 3) == 0) {
                    Vector3 h2 = ResolveSilentAimWorldPos(bestTarget, aimPosition);
                    if (!IsZeroVec(h2) && looksLikeWorldPos(h2)) {
                        liveBone = h2;
                        std::lock_guard<std::mutex> lk(g_silentMtx);
                        g_silentTargetPos = liveBone;
                    }
                }
                AimSyncFireHit(myPawnObject, myLocation, liveBone);
            }
        } else {
            SilentAimClearTarget();
        }
    } else if (useSilent) {
        SilentAimClearTarget();
    } else {
        if (g_silentKeepRunning.load(std::memory_order_relaxed)) SilentAimStop();
    }
    if (iAmAlive && cameraAimActive && bestTarget != 0) {
        if (!AimTargetStillValid(bestTarget)) {
            bestTarget = 0;
            gAimLockTarget = 0;
            gAimLockLostFrames = 0;
            s_lockHoldFrames = 0;
            s_lastAimPawnLocal = 0;
            AimLockClear();
            update_aim_assist_legit_tuning(false);
        } else {
            Vector3 lookBone = ResolveSilentAimWorldPos(bestTarget, aimPosition);
            if (IsZeroVec(lookBone) || !looksLikeWorldPos(lookBone))
                lookBone = GetAimTargetPosMode(bestTarget, aimPosition, bestDistance);
            if (IsZeroVec(lookBone) || !looksLikeWorldPos(lookBone)) {
                lookBone = ResolveAimHeadWorldPos(bestTarget);
                if (!IsZeroVec(lookBone) && aimPosition > 0) {
                    lookBone.y -= (aimPosition == 1) ? 0.14f : 0.34f;
                }
            }
            if (IsZeroVec(lookBone)) lookBone = ResolvePawnWorldPosAny(bestTarget);
            if (IsZeroVec(lookBone) || bestDistance < 0.15f) {
                update_aim_assist_legit_tuning(false);
                AimLockClear();
            } else {
                Vector3 aimPoint = AimTrackAndLeadEx(bestTarget, lookBone, bestDistance, true, false);
                if (IsZeroVec(aimPoint)) aimPoint = lookBone;
                bestHeadPos = aimPoint;
                s_lastAimPawnLocal = bestTarget;
                bool lookOk = true;
                if (isAimbot && useAim180) {
                    Vector3 w2sLook = WorldToScreenLayer(aimPoint, matrixData, (float)matrixVpWidth, (float)matrixVpHeight, (float)viewWidth, (float)viewHeight);
                    lookOk = (w2sLook.z > 0.001f);
                } else if (isAimbot && (!useSphereAim || !allowThroughWall)) {
                    Vector3 w2sLook = WorldToScreenLayer(aimPoint, matrixData, (float)matrixVpWidth, (float)matrixVpHeight, (float)viewWidth, (float)viewHeight);
                    if (w2sLook.z <= 0.001f) {
                        lookOk = false;
                    } else {
                        float dx = w2sLook.x - screenCenter.x;
                        float dy = w2sLook.y - screenCenter.y;
                        float fovSq = aimFovSq > 1.f ? aimFovSq : (150.f * 150.f);
                        lookOk = (dx * dx + dy * dy) <= fovSq * 1.10f;
                    }
                } else if (useAssistOnly) {
                    Vector3 w2sLook = WorldToScreenLayer(aimPoint, matrixData, (float)matrixVpWidth, (float)matrixVpHeight, (float)viewWidth, (float)viewHeight);
                    if (w2sLook.z <= 0.001f) {
                        lookOk = false;
                    } else {
                        float dx = w2sLook.x - screenCenter.x;
                        float dy = w2sLook.y - screenCenter.y;
                        lookOk = (dx * dx + dy * dy) <= assistRadiusSq * 1.15f;
                    }
                }
                if (!lookOk && bestTarget != 0 && (fireWindow || isScoping) &&
                    (gAimLockTarget == bestTarget || s_lastAimPawnLocal == bestTarget)) {
                    lookOk = true;
                }
                bool didLook = false;
                if (lookOk) {
                    Vector3 fromNow = AimCameraOrigin(myPawnObject, myLocation);
                    Vector3 glued = AimLookAtHeadLive(myPawnObject, bestTarget, aimPosition,
                                                      bestDistance, fromNow, 1, &aimPoint, true);
                    if (!IsZeroVec(glued) && looksLikeWorldPos(glued)) {
                        aimPoint = glued;
                        bestHeadPos = glued;
                    } else if (!IsZeroVec(aimPoint) && looksLikeWorldPos(aimPoint)) {
                        bestHeadPos = aimPoint;
                    }
                    AimLockClear();
                    didLook = true;
                } else {
                    AimLockClear();
                }
                if (!useSilent && fireWindow && didLook && bestTarget != 0) {
                    ZeroWeaponScatterForAim(myPawnObject);
                    Vector3 fromNow = AimCameraOrigin(myPawnObject, myLocation);
                    Vector3 hit = ResolveSilentAimWorldPos(bestTarget, aimPosition);
                    if (IsZeroVec(hit) || !looksLikeWorldPos(hit))
                        hit = GetAimTargetPosMode(bestTarget, aimPosition, bestDistance);
                    if (IsZeroVec(hit) || !looksLikeWorldPos(hit))
                        hit = bestHeadPos;
                    bestHeadPos = hit;
                    for (int i = 0; i < 3; i++) {
                        if (i == 0) {
                            Vector3 h2 = ResolveSilentAimWorldPos(bestTarget, aimPosition);
                            if (!IsZeroVec(h2) && looksLikeWorldPos(h2)) hit = h2;
                        }
                        AimSyncFireHit(myPawnObject, fromNow, hit);
                    }
                    Vector3 from2 = AimCameraOrigin(myPawnObject, myLocation);
                    Quaternion tq = Quaternion::Normalized(GetRotationToLocation(hit, 0.0f, from2));
                    if (!(isnan(tq.x) || isnan(tq.y) || isnan(tq.z) || isnan(tq.w))) {
                        write_aim_rotations(myPawnObject, tq);
                    }
                }
            }
        }
    } else {
        update_aim_assist_legit_tuning(false);
        AimLockClear();
        if (!silentActive) s_lastAimPawnLocal = 0;
        if (bestTarget == 0) {
            gAimLockTarget = 0;
            gAimLockLostFrames = 0;
        }
    }
    if (!cameraAimActive || bestTarget == 0 || !(isFiring || isScoping)) {
        if (!(isFiring || isScoping) || !cameraAimActive || bestTarget == 0)
            AimLockClear();
    }
    self.alertNumBGLayer.path = CGPathIsEmpty(aNumBGPath) ? nil : aNumBGPath;
    self.alertNumGreenLayer.path = CGPathIsEmpty(aNumGPath) ? nil : aNumGPath;
    self.alertNumOrangeLayer.path = CGPathIsEmpty(aNumOPath) ? nil : aNumOPath;
    self.alertNumRedLayer.path = CGPathIsEmpty(aNumRPath) ? nil : aNumRPath;
    CGPathRelease(aNumBGPath);
    CGPathRelease(aNumGPath);
    CGPathRelease(aNumOPath);
    CGPathRelease(aNumRPath);
    return stats;
}

// ============================================================
// Getters / setters / prefs
// ============================================================

Quaternion GetRotationToLocation(Vector3 targetLocation, float y_bias, Vector3 myLoc) {
    Vector3 direction = (targetLocation + Vector3(0, y_bias, 0)) - myLoc;
    return Quaternion::LookRotation(direction, Vector3(0, 1, 0));
}

bool get_IsBot(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    return ReadAddr<uint8_t>(player + (uint64_t)kIsClientBot) != 0;
}

bool get_IsKnockedDown(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    if (get_CurHP(player) <= 0) return false;
    if (ReadAddr<uint8_t>(player + kKnocked) != 0) return true;
    uint64_t phx = ReadAddr<uint64_t>(player + kMyPhysXData);
    if (!isVaildPtr(phx)) return false;
    uint64_t stateCls = ReadAddr<uint64_t>(phx + (uint64_t)kPhxNpeononogeo);
    if (!isVaildPtr(stateCls)) return false;
    return ReadAddr<int>(stateCls + (uint64_t)kGhgState) == 8;
}

bool get_IsBeingRescued(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    return ReadAddr<uint8_t>(player + kBeingRescuredState) >= 2;
}

static const int kPriVarScope = 12;
static const int kPriVarFire  = 21;

bool get_IsFiring(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    int startFire = ReadAddr<int>(player + kIsFiring);
    if (startFire > 0 && startFire <= 9) return true;
    int startFireAlt = ReadAddr<int>(player + 0x1C14);
    if (startFireAlt > 0 && startFireAlt <= 9) return true;
    if (ReadAddr<uint8_t>(player + kIsPrepareAttack) != 0) return true;
    if (ReadAddr<uint8_t>(player + 0x7D8) != 0) return true;
    if (GetDataUInt16(player, kPriVarFire) != 0) return true;
    return false;
}

bool get_IsScoping(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    int scopeState = GetDataUInt16(player, kPriVarScope);
    return (scopeState > 0 && scopeState < 100000);
}

static inline uint32_t get_VisibleFlags(uint64_t player) {
    uint64_t bitArray = ReadAddr<uint64_t>(player + kVisibleObj);
    if (!isVaildPtr(bitArray)) return 0;
    return ReadAddr<uint32_t>(bitArray + kVisibleObjFlags);
}

bool get_IsVisible(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    uint32_t m_Value = get_VisibleFlags(player);
    return (m_Value & 0x1u) != 0;
}

bool get_IsVisibleByFlag(uint64_t player, uint32_t flag) {
    if (!isVaildPtr(player)) return false;
    return (get_VisibleFlags(player) & flag) != 0;
}

bool get_IsFPPVisible(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    uint32_t m_Value = get_VisibleFlags(player);
    if (m_Value == 0) return false;
    return (m_Value & 0x1u) != 0;
}

// ============================================================
// write_aim_rotations — ĐÃ RÚT GỌN, chỉ ghi 2 offset cần thiết
// ============================================================
static void write_aim_rotations(uint64_t player, const Quaternion &out) {
    if (!isVaildPtr(player)) return;
    WriteAddr<Quaternion>(player + kAimRotation, out);
    WriteAddr<Quaternion>(player + kCurrentAimRotation, out);
    // Chỉ ghi thêm 2 offset fallback nếu offset chính khác
    if (kAimRotation != 0x5B4) {
        WriteAddr<Quaternion>(player + 0x5B4, out);
    }
    if (kCurrentAimRotation != 0x19A4) {
        WriteAddr<Quaternion>(player + 0x19A4, out);
    }
}

void set_aim(uint64_t player, Quaternion rotation, float speed, int mode, bool forceInstant) {
    if (!isVaildPtr(player)) return;
    Quaternion q = Quaternion::Normalized(rotation);
    if (isnan(q.x) || isnan(q.y) || isnan(q.z) || isnan(q.w)) return;
    const bool hardLock = forceInstant || mode >= 1 || speed >= 0.75f;
    if (hardLock) {
        write_aim_rotations(player, q);
        return;
    }
    Quaternion current = ReadAddr<Quaternion>(player + kAimRotation);
    float n = current.x * current.x + current.y * current.y + current.z * current.z + current.w * current.w;
    if (!(n > 0.0001f) || isnan(n)) {
        write_aim_rotations(player, q);
        return;
    }
    current = Quaternion::Normalized(current);
    float angle = Quaternion::Angle(current, q);
    if (isnan(angle) || angle < 0.0005f) {
        write_aim_rotations(player, q);
        return;
    }
    float s = Clamp01f(speed);
    float base = 0.55f + 0.45f * s;
    if (angle > 0.08f) base = fmaxf(base, 0.90f);
    float t = fminf(1.0f, base);
    Quaternion out = Quaternion::Normalized(Quaternion::Slerp(current, q, t));
    if (isnan(out.x) || isnan(out.y) || isnan(out.z) || isnan(out.w)) return;
    write_aim_rotations(player, out);
}

static float g_aaSavedKnol = 0.f;
static float g_aaSavedNfk  = 0.f;
static bool  g_aaLegitBoostActive = false;

void update_aim_assist_legit_tuning(bool enable) {
    if (enable == g_aaLegitBoostActive) return;
    if (Moudule_Base == (uint64_t)-1 || Moudule_Base == 0 || !isVaildPtr(Moudule_Base)) {
        g_aaLegitBoostActive = false;
        return;
    }
    uint64_t typeInfo = ReadAddr<uint64_t>(Moudule_Base + kAimAssistTypeInfo);
    if (!isVaildPtr(typeInfo)) return;
    uint64_t statics = ReadAddr<uint64_t>(typeInfo + kTypeInfoStatics);
    if (!isVaildPtr(statics)) return;
    if (!enable) {
        if (g_aaLegitBoostActive) {
            WriteAddr<float>(statics + kAaStaticKnolgmjlcef, g_aaSavedKnol);
            WriteAddr<float>(statics + kAaStaticNfkcllpalej, g_aaSavedNfk);
            g_aaLegitBoostActive = false;
        }
        return;
    }
    g_aaSavedKnol = ReadAddr<float>(statics + kAaStaticKnolgmjlcef);
    g_aaSavedNfk  = ReadAddr<float>(statics + kAaStaticNfkcllpalej);
    WriteAddr<float>(statics + kAaStaticKnolgmjlcef, g_aaSavedKnol * 0.88f);
    WriteAddr<float>(statics + kAaStaticNfkcllpalej, g_aaSavedNfk * 1.18f);
    g_aaLegitBoostActive = true;
}

static float esp_aim_delta_time(void) {
    static CFTimeInterval s_last = 0.0;
    const CFTimeInterval now = CACurrentMediaTime();
    float dt = (s_last > 0.0) ? (float)(now - s_last) : (1.f / 60.f);
    s_last = now;
    if (dt <= 0.f || dt > 0.25f) dt = 1.f / 60.f;
    return dt;
}

static float legit_aim_blend_t(float angleRad, float speed01, float targetDistance, float maxAimDistance) {
    const float dt = esp_aim_delta_time();
    const float dtScale = fminf(fmaxf(dt * 60.f, 0.5f), 2.f);
    const float refAngle = 40.f * 3.14159265f / 180.f;
    const float angleNorm = fminf(angleRad / refAngle, 1.f);
    const float angleEase = 0.28f + 0.72f * (1.f - powf(angleNorm, 1.25f));
    const float speedCurve = 0.035f + 0.32f * powf(speed01, 1.2f);
    const float distNorm = Clamp01f(targetDistance / fmaxf(maxAimDistance, 1.f));
    const float distBias = 0.90f + 0.10f * (1.f - distNorm);
    float t = speedCurve * angleEase * distBias * dtScale;
    const float kMicroAngleRad = 1.5f * 3.14159265f / 180.f;
    if (angleRad < kMicroAngleRad) t *= 0.55f;
    const float maxT = (0.10f + 0.22f * speed01) * dtScale;
    const float minT = 0.012f * dtScale;
    if (t < minT) t = minT;
    if (t > maxT) t = maxT;
    return t;
}

void set_aim_legit(uint64_t player, Quaternion rotation, float targetDistance) {
    if (!isVaildPtr(player)) return;
    Quaternion q = Quaternion::Normalized(rotation);
    if (isnan(q.x) || isnan(q.y) || isnan(q.z) || isnan(q.w)) return;
    Quaternion current = ReadAddr<Quaternion>(player + kAimRotation);
    float n = current.x * current.x + current.y * current.y + current.z * current.z + current.w * current.w;
    if (!(n > 0.0001f) || isnan(n)) {
        write_aim_rotations(player, q);
        return;
    }
    current = Quaternion::Normalized(current);
    float angle = Quaternion::Angle(current, q);
    if (isnan(angle)) return;
    if (angle < 0.0015f) return;
    float s = Clamp01f(aimSpeed);
    float t = legit_aim_blend_t(angle, s, targetDistance, aimDistance);
    Quaternion blended = Quaternion::Slerp(current, q, t);
    Quaternion out = Quaternion::Normalized(blended);
    if (isnan(out.x) || isnan(out.y) || isnan(out.z) || isnan(out.w)) return;
    write_aim_rotations(player, out);
}

static UIFont *LoadCountFont(CGFloat size) {
    static BOOL fontLoaded = NO;
    static NSString *realFontName = @"Arial-BoldMT";
    if (!fontLoaded) {
        NSString *fontPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Font/count.ttf"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:fontPath]) {
            CGDataProviderRef fontDataProvider = CGDataProviderCreateWithFilename([fontPath UTF8String]);
            if (fontDataProvider) {
                CGFontRef customFont = CGFontCreateWithDataProvider(fontDataProvider);
                if (customFont) {
                    CTFontManagerRegisterGraphicsFont(customFont, nil);
                    NSString *postScriptName = (__bridge_transfer NSString *)CGFontCopyPostScriptName(customFont);
                    if (postScriptName) { realFontName = postScriptName; }
                    CGFontRelease(customFont);
                }
                CGDataProviderRelease(fontDataProvider);
            }
        }
        fontLoaded = YES;
    }
    UIFont *font = [UIFont fontWithName:realFontName size:size];
    return font ? font : [UIFont boldSystemFontOfSize:size];
}

static inline CGMutablePathRef ESPCreateMutablePath(void) { return CGPathCreateMutable(); }
static inline void ESPReleasePath(CGMutablePathRef path) { if (path) CGPathRelease(path); }

static inline ESPGeometryBuffers ESPGeometryBuffersCreate(void) {
    ESPGeometryBuffers buffers;
    buffers.boxPath = ESPCreateMutablePath();
    buffers.boxBotPath = ESPCreateMutablePath();
    buffers.boxKnockedPath = ESPCreateMutablePath();
    buffers.bonePath = ESPCreateMutablePath();
    buffers.boneBotPath = ESPCreateMutablePath();
    buffers.boneKnockedPath = ESPCreateMutablePath();
    buffers.snaplinePath = ESPCreateMutablePath();
    buffers.snaplineBotPath = ESPCreateMutablePath();
    buffers.snaplineKnockedPath = ESPCreateMutablePath();
    buffers.hpFillGreenPath = ESPCreateMutablePath();
    buffers.hpFillOrangePath = ESPCreateMutablePath();
    buffers.hpFillRedPath = ESPCreateMutablePath();
    buffers.bgFillBlackPath = ESPCreateMutablePath();
    buffers.alertPath = ESPCreateMutablePath();
    buffers.boxDirty = buffers.boxBotDirty = buffers.boxKnockedDirty = NO;
    buffers.boneDirty = buffers.boneBotDirty = buffers.boneKnockedDirty = NO;
    buffers.snaplineDirty = buffers.snaplineBotDirty = buffers.snaplineKnockedDirty = NO;
    buffers.hpFillGreenDirty = buffers.hpFillOrangeDirty = buffers.hpFillRedDirty = NO;
    buffers.bgFillBlackDirty = buffers.alertDirty = NO;
    return buffers;
}

typedef struct { uint32_t n; uint32_t curves; } ESPPathCountCtx;
static void espCountPathElements(void *info, const CGPathElement *e) {
    ESPPathCountCtx *c = (ESPPathCountCtx *)info;
    if (!c) return;
    c->n++;
    if (e->type == kCGPathElementAddCurveToPoint ||
        e->type == kCGPathElementAddQuadCurveToPoint) c->curves++;
}

static inline void ESPGeometryBuffersRelease(ESPGeometryBuffers *buffers) {
    if (!buffers) return;
    ESPReleasePath(buffers->boxPath); ESPReleasePath(buffers->boxBotPath); ESPReleasePath(buffers->boxKnockedPath);
    ESPReleasePath(buffers->bonePath); ESPReleasePath(buffers->boneBotPath); ESPReleasePath(buffers->boneKnockedPath);
    ESPReleasePath(buffers->snaplinePath); ESPReleasePath(buffers->snaplineBotPath);
    ESPReleasePath(buffers->snaplineKnockedPath); ESPReleasePath(buffers->hpFillGreenPath);
    ESPReleasePath(buffers->hpFillOrangePath); ESPReleasePath(buffers->hpFillRedPath);
    ESPReleasePath(buffers->bgFillBlackPath); ESPReleasePath(buffers->alertPath);
}

static inline void MenuViewApplyPath(CAShapeLayer *layer, CGMutablePathRef path, bool dirty) {
    if (!layer) return;
    if (dirty && path) { layer.path = path; }
    else if (layer.path != nil) { layer.path = nil; }
}

static int syncTick = 0;
static bool s_setNameEnabledGlobal = false;
static NSString *s_customNameGlobal = nil;

void ESPSyncFromPrefs(void) {
    static CFTimeInterval s_lastFullSync = 0;
    CFTimeInterval nowSync = CACurrentMediaTime();
    if (s_lastFullSync > 0 && (nowSync - s_lastFullSync) < 0.05) return;
    s_lastFullSync = nowSync;
    (void)syncTick;

    isStreamerMode = ESPPrefsBool(@"StreamerMode", NO);
    Norecoil   = ESPPrefsBool(@"Norecoil", NO);
    {
        float bs = ESPPrefsFloat(@"BrutalSpeed", 0.16f);
        if (bs < 0.05f) bs = 0.05f;
        if (bs > 0.80f) bs = 0.80f;
        speedvalue = Norecoil ? bs : 1.0f;
    }
    isSpeed = ESPPrefsBool(@"Speed", NO);
    moveSpeedScale = ESPPrefsFloat(@"SpeedValue", 1.22f);
    if (moveSpeedScale < 1.0f) moveSpeedScale = 1.0f;
    if (moveSpeedScale > 1.45f) moveSpeedScale = 1.45f;
    if (!isSpeed) moveSpeedScale = 1.0f;
    if (Norecoil) {
        isSpeed = NO;
        moveSpeedScale = 1.0f;
    }
    isShowFovCircle = ESPPrefsBool(@"ShowFovCircle", YES);
    isESP      = ESPPrefsBool(@"EnableESP", YES);
    isESP2     = ESPPrefsBool(@"EnableESP2", NO);
    isBox      = ESPPrefsBool(@"Box", YES);
    boxMode    = (int)ESPPrefsFloat(@"BoxMode", 0.0f);
    isBone     = ESPPrefsBool(@"Bone", YES);
    isHealth   = ESPPrefsBool(@"Health", YES);
    isName     = ESPPrefsBool(@"Name", YES);
    isDis      = ESPPrefsBool(@"Distance", YES);
    isLine     = ESPPrefsBool(@"Line", YES);
    isEspBot   = ESPPrefsBool(@"EspBot", YES);
    isWeapon   = ESPPrefsBool(@"Weapon", NO);
    isCount    = ESPPrefsBool(@"Count", YES);
    isAlert360 = ESPPrefsBool(@"Alert360", NO);
    isAlertNum = ESPPrefsBool(@"AlertNum", NO);
    isEspCheckVisible = ESPPrefsBool(@"EspCheckVisible", NO);
    {
        BOOL aimOnBot = YES;
        id aimOnBotPref = AppSettingsObjectForKey(@"AimOnBot");
        if (aimOnBotPref != nil) {
            aimOnBot = ESPPrefsBool(@"AimOnBot", YES);
        } else {
            aimOnBot = !ESPPrefsBool(@"AimIgnoreBot", NO);
        }
        isAimIgnoreBot = !aimOnBot;
        if (aimOnBot) isEspBot = YES;
    }
    isAimIgnoreKnock = ESPPrefsBool(@"AimIgnoreKnock", NO);
    isAimBehindWall = ESPPrefsBool(@"AimBehindWall", NO);
    isAimRage = ESPPrefsBool(@"AimRage", NO);
    isAimbot    = ESPPrefsBool(@"Aimbot", NO);
    isAimAssist = ESPPrefsBool(@"AimAssist", NO);
    isAimLegit  = ESPPrefsBool(@"AimLegit", NO);
    if (isAimbot && isAimLegit) {
        isAimLegit = NO;
    } else if (!isAimbot && isAimAssist && isAimLegit) {
        isAimLegit = NO;
    }
    {
        int mode = (int)ESPPrefsFloat(@"AimSphereMode", -1.0f);
        if (mode < 0) {
            mode = ESPPrefsBool(@"Aim360", NO) ? 2 : 0;
        }
        if (mode < 0) mode = 0;
        if (mode > 2) mode = 2;
        aimSphereMode = isAimbot ? mode : 0;
    }
    bool wasSilent = isAimSilent;
    isAimSilent = ESPPrefsBool(@"AimSilent", NO);
    if (wasSilent && !isAimSilent) {
        SilentAimStop();
    }
    isFastReload = ESPPrefsBool(@"FastReload", NO);
    fastReloadSpeed = ESPPrefsFloat(@"FastReloadSpeed", 1.0f);
    isCamPC    = ESPPrefsBool(@"CamPC", NO);
    camPCValue = ESPPrefsFloat(@"CamPCValue", 30.0f);
    if (camPCValue < 0.0f) camPCValue = 0.0f;
    if (camPCValue > 150.0f) camPCValue = 150.0f;
    aimMode = (int)ESPPrefsFloat(@"AimMode", 1.0f);
    triggerMode = (int)ESPPrefsFloat(@"TriggerMode", 0.0f);
    if (triggerMode < 0) triggerMode = 0;
    if (triggerMode > 3) triggerMode = 3;
    aimPosition = (int)ESPPrefsFloat(@"AimPos", 0.0f);
    if (aimPosition < 0) aimPosition = 0;
    if (aimPosition > 2) aimPosition = 2;
    aimTargetMode = (int)ESPPrefsFloat(@"AimTargetMode", 0.0f);
    aimFov = ESPPrefsFloat(@"Fov", 150.0f);
    if (aimFov <= 1.0f) aimFov = 150.0f;
    aimDistance = ESPPrefsFloat(@"AimDistance", -1.0f);
    if (aimDistance < 0.0f) {
        id legacy = AppSettingsObjectForKey(@"Distance");
        if ([legacy isKindOfClass:[NSNumber class]] && [(NSNumber *)legacy floatValue] > 1.5f) {
            aimDistance = [(NSNumber *)legacy floatValue];
        } else {
            aimDistance = 200.0f;
        }
    }
    if (aimDistance <= 1.0f) aimDistance = 200.0f;
    aimSpeed = ESPPrefsFloat(@"AimSpeed", 100.0f) / 100.0f;
    if (aimSpeed < 0.01f) aimSpeed = 0.01f;
    if (aimSpeed > 1.0f) aimSpeed = 1.0f;
    espDistanceLimit = ESPPrefsFloat(@"EspDistanceLimit", 150.0f);
    if (espDistanceLimit < 10.0f) espDistanceLimit = 150.0f;
    s_setNameEnabledGlobal = ESPPrefsBool(@"SetName", NO);
    NSString *customDefault = @"@Bolaminhduc";
    NSString *newName = AppSettingsObjectForKey(@"CustomName");
    if (![newName isKindOfClass:[NSString class]] || ((NSString *)newName).length == 0 ||
        [newName containsString:@"thanhhoa"] || [newName containsString:@"Thanhhoa"] ||
        [newName containsString:@"Ng_thanhhoa"] || [newName containsString:@"ng_thanhhoa"]) {
        newName = customDefault;
    }
    if (![newName isEqualToString:s_customNameGlobal]) {
        s_customNameGlobal = newName;
    }
    int menuStyle = (int)ESPPrefsFloat(@"MenuLayoutStyle", 0.0f);
    if (menuStyle == 1) {
        isEspBot = YES;
        isAimIgnoreBot = NO;
        isAimIgnoreKnock = YES;
        isEspCheckVisible = YES;
    }
    boxThick = ESPPrefsFloat(@"BoxThickness", 1.0f);
    boxR = ESPPrefsFloat(@"BoxColorR", 0.0f); boxG = ESPPrefsFloat(@"BoxColorG", 1.0f); boxB = ESPPrefsFloat(@"BoxColorB", 1.0f);
    boxColorMode = (int)ESPPrefsFloat(@"BoxColorMode", 0.0f);
    if (boxColorMode < 0) boxColorMode = 0;
    if (boxColorMode > 1) boxColorMode = 1;
    boneThick = ESPPrefsFloat(@"BoneThickness", 1.0f);
    boneR = ESPPrefsFloat(@"BoneColorR", 0.0f); boneG = ESPPrefsFloat(@"BoneColorG", 1.0f); boneB = ESPPrefsFloat(@"BoneColorB", 1.0f);
    boneColorMode = (int)ESPPrefsFloat(@"BoneColorMode", 0.0f);
    if (boneColorMode < 0) boneColorMode = 0;
    if (boneColorMode > 1) boneColorMode = 1;
    lineThick = ESPPrefsFloat(@"LineThickness", 1.0f);
    lineR = ESPPrefsFloat(@"LineColorR", 0.0f); lineG = ESPPrefsFloat(@"LineColorG", 1.0f); lineB = ESPPrefsFloat(@"LineColorB", 1.0f);
    lineColorMode = (int)ESPPrefsFloat(@"LineColorMode", 0.0f);
    if (lineColorMode < 0) lineColorMode = 0;
    if (lineColorMode > 1) lineColorMode = 1;
    fovThick = ESPPrefsFloat(@"FovThickness", 0.6f);
    fovR = ESPPrefsFloat(@"FovColorR", 1.0f); fovG = ESPPrefsFloat(@"FovColorG", 1.0f); fovB = ESPPrefsFloat(@"FovColorB", 0.0f);
    fovColorMode = (int)ESPPrefsFloat(@"FovColorMode", 0.0f);
    if (fovColorMode < 0) fovColorMode = 0;
    if (fovColorMode > 1) fovColorMode = 1;
    aimAssistThick = ESPPrefsFloat(@"AimAssistThickness", 1.5f);
    aimAssistR = ESPPrefsFloat(@"AimAssistColorR", 0.0f); aimAssistG = ESPPrefsFloat(@"AimAssistColorG", 1.0f); aimAssistB = ESPPrefsFloat(@"AimAssistColorB", 1.0f);
}

// ============================================================
// EnableCamPC
// ============================================================
void EnableCamPC(uint64_t localPlayerPawn, bool isEnabled, float campcValue) {
    if (!isVaildPtr(localPlayerPawn)) {
        s_lastFollowCameraObj = 0;
        return;
    }
    uint64_t FollowCameraObj = ReadAddr<uint64_t>(localPlayerPawn + kFollowCameraObj);
    if (isVaildPtr(FollowCameraObj)) {
        if (isEnabled && campcValue > 0.0f) {
            WriteAddr<float>(FollowCameraObj + kFollowCameraDistance, campcValue);
            s_lastFollowCameraObj = FollowCameraObj;
        } else if (s_lastFollowCameraObj) {
            WriteAddr<float>(FollowCameraObj + kFollowCameraDistance, 0.0f);
            s_lastFollowCameraObj = 0;
        }
    } else {
        s_lastFollowCameraObj = 0;
    }
}

// ============================================================
// ToggleSpeedX50Safe — bản an toàn thay thế ToggleSpeedX50 cũ
// ============================================================
extern "C" void ToggleSpeedX50Safe(bool enable) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        std::lock_guard<std::mutex> lk(g_patchedMtx);
        pid_t pid = (pid_t)GameTargetProcessPid();
        if (pid <= 0) return;
        task_t tk = 0;
        if (task_for_pid(mach_task_self(), pid, &tk) != KERN_SUCCESS) {
            NSLog(@"[HTH Cheat] LỖI: Không lấy được task_for_pid!");
            return;
        }
        uint64_t originalVal = 4397530849764387586ULL;
        uint64_t hackedVal   = 4397530849740000000ULL;
        const mach_vm_size_t kChunkMax = 4 * 1024 * 1024;
        if (enable) {
            g_patchedAddresses.clear();
            mach_vm_address_t address = 0x100000000;
            mach_vm_size_t size = 0;
            vm_region_basic_info_data_64_t info;
            mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
            mach_port_t object_name;
            while (mach_vm_region(tk, &address, &size, VM_REGION_BASIC_INFO_64,
                                  (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS) {
                if (address > 0x160000000) break;
                if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE)) {
                    mach_vm_address_t chunkAddr = address;
                    mach_vm_size_t remain = size;
                    while (remain > 0) {
                        mach_vm_size_t chunk = remain > kChunkMax ? kChunkMax : remain;
                        uint8_t *buffer = (uint8_t *)malloc(chunk);
                        if (!buffer) { chunkAddr += chunk; remain -= chunk; continue; }
                        mach_vm_size_t bytesRead = 0;
                        kern_return_t rk = mach_vm_read_overwrite(tk, chunkAddr, chunk,
                                                                  (mach_vm_address_t)buffer, &bytesRead);
                        if (rk == KERN_SUCCESS) {
                            for (size_t i = 0; i + 8 <= bytesRead; i += 4) {
                                uint64_t currentValue = *(uint64_t *)(buffer + i);
                                if (currentValue == originalVal) {
                                    mach_vm_address_t exactWriteAddress = chunkAddr + i;
                                    kern_return_t wk = mach_vm_write(tk, exactWriteAddress,
                                                                     (vm_offset_t)&hackedVal, sizeof(hackedVal));
                                    if (wk == KERN_SUCCESS) {
                                        g_patchedAddresses.push_back(exactWriteAddress);
                                    }
                                }
                            }
                        }
                        free(buffer);
                        chunkAddr += chunk;
                        remain -= chunk;
                    }
                }
                address += size;
            }
        } else {
            if (!g_patchedAddresses.empty()) {
                for (mach_vm_address_t savedAddr : g_patchedAddresses) {
                    kern_return_t wk = mach_vm_write(tk, savedAddr,
                                                     (vm_offset_t)&originalVal, sizeof(originalVal));
                    (void)wk;
                }
                g_patchedAddresses.clear();
            }
        }
        mach_port_deallocate(mach_task_self(), tk);
    });
}

// ============================================================
// END OF FILE
// ============================================================
@end
