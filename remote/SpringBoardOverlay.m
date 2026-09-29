//
//  SpringBoardOverlay.m — Fl0rk DrawView: EXTRA trojan thread + 15fps
//
//  One shape layer, one colour (white). The 6-group colour split was
//  reverted: it killed ESP and broke aim. Colours of individual elements
//  (health bar, box, bone, snapline) are drawn on the app side but the
//  SpringBoard mirror renders every subpath in white, which is what the
//  build has always done.
//

#import "SpringBoardOverlay.h"
#import "RemoteCall.h"
#import "remote_objc.h"
#import "../../kexploit/kexploit_opa334.h"
#import <UIKit/UIKit.h>
#import <pthread.h>
#import <string.h>
#import <mach/mach_time.h>

#define SB_OVERLAY_WIN_LEVEL 999999.0
#define SB_MIN_PUBLISH_INTERVAL_US 8000ULL
#define SB_DRAW_BONES 0

static BOOL g_sbOverlayOn = NO;
static uint64_t g_sbWin = 0;
static uint64_t g_sbShape = 0;
static uint64_t g_sbCanvas = 0;

static uint64_t g_sbPersistentPath = 0;
#define SB_PATH_HOLD_FRAMES 4
static uint64_t g_sbPathRing[SB_PATH_HOLD_FRAMES] = {0};
static int g_sbPathRingAt = 0;
static uint64_t g_sbMirrorPtsBuf = 0;
static uint32_t g_sbPathHash = 0;
static NSUInteger g_sbLastPathBytes = 0;
static pthread_mutex_t g_sbLock = PTHREAD_MUTEX_INITIALIZER;

static uint64_t g_sbSetPathInv = 0;
static uint64_t g_sbSetPathArgBuf = 0;
static uint64_t g_sbPerformMainSel = 0;
static uint64_t g_sbInvokeSel = 0;

static uint64_t g_sbSummaryAttempts = 0;
static uint64_t g_sbSummarySkips = 0;
static uint64_t g_sbSummaryUpdates = 0;

static int g_sbConsecFail = 0;
static int g_sbEverOn = 0;
static uint64_t g_sbRearmAfterUS = 0;

static int g_sbSessionDead = 0;
static uint64_t g_sbLastPublishUS = 0;
static uint64_t g_sbRearmBackoffUS = 5000000ULL;

static uint64_t g_sbBusyDrops = 0;
static uint64_t g_sbHoldUS = 0;
static uint64_t g_sbNextPublishUS = 0;
static uint32_t g_sbLastSubpaths = 0;
static uint64_t g_sbLastCalls = 0;

static const char *kShapeKeys[16] = {
    "boxLayer", "boxBotLayer", "boxKnockedLayer",
    "boneLayer", "boneBotLayer", "boneKnockedLayer",
    "snaplineLayer", "snaplineBotLayer", "snaplineKnockedLayer",
    "hpFillGreenLayer", "hpFillOrangeLayer", "hpFillRedLayer",
    "bgFillBlackLayer", "alertLayer", "fovLayer", "aimAssistLayer"
};

static uint64_t dlsym_remote(const char *fn, uint64_t a0, uint64_t a1, uint64_t a2,
                             uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7) {
    const int okBefore = remote_call_current_success() ? 1 : 0;
    uint64_t r = r_dlsym_call(R_TIMEOUT, fn, a0,a1,a2,a3,a4,a5,a6,a7);
    if (okBefore && !remote_call_current_success()) {
        NSLog(@"[PUSH-DLSYM] %s broke the session (fn=%p)", fn, (const void *)fn);
    }
    return r;
}

static uint64_t now_us(void) {
    static mach_timebase_info_data_t tb;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&tb); });
    uint64_t t = mach_absolute_time();
    return (t * tb.numer / tb.denom) / 1000ULL;
}

#define SB_CURVE_CHORDS 12

typedef struct {
    NSMutableData *data;
    double landW, landH;
    double lastX, lastY;
    int haveLast;
} SerCtx;
static uint32_t g_sbSubpathCount = 0;

static void sbEmit(SerCtx *ctx, uint8_t op, double sx, double sy) {
    CGPoint p;
    p.x = ctx->landH - sy;
    p.y = sx;
    [ctx->data appendBytes:&op length:1];
    [ctx->data appendBytes:&p length:sizeof(p)];
    ctx->lastX = sx;
    ctx->lastY = sy;
    ctx->haveLast = 1;
}

static void serFunc(void *info, const CGPathElement *e) {
    SerCtx *ctx = (SerCtx *)info;
    if (e->type == kCGPathElementCloseSubpath) return;

    if (e->type == kCGPathElementAddCurveToPoint && ctx->haveLast) {
        const double p0x = ctx->lastX, p0y = ctx->lastY;
        const double p1x = e->points[0].x, p1y = e->points[0].y;
        const double p2x = e->points[1].x, p2y = e->points[1].y;
        const double p3x = e->points[2].x, p3y = e->points[2].y;
        for (int k = 1; k <= SB_CURVE_CHORDS; k++) {
            const double t  = (double)k / (double)SB_CURVE_CHORDS;
            const double mt = 1.0 - t;
            const double b0 = mt*mt*mt, b1 = 3.0*mt*mt*t, b2 = 3.0*mt*t*t, b3 = t*t*t;
            sbEmit(ctx, 2,
                   b0*p0x + b1*p1x + b2*p2x + b3*p3x,
                   b0*p0y + b1*p1y + b2*p2y + b3*p3y);
        }
        return;
    }
    if (e->type == kCGPathElementAddQuadCurveToPoint && ctx->haveLast) {
        const double p0x = ctx->lastX, p0y = ctx->lastY;
        const double p1x = e->points[0].x, p1y = e->points[0].y;
        const double p2x = e->points[1].x, p2y = e->points[1].y;
        for (int k = 1; k <= SB_CURVE_CHORDS; k++) {
            const double t  = (double)k / (double)SB_CURVE_CHORDS;
            const double mt = 1.0 - t;
            sbEmit(ctx, 2,
                   mt*mt*p0x + 2.0*mt*t*p1x + t*t*p2x,
                   mt*mt*p0y + 2.0*mt*t*p1y + t*t*p2y);
        }
        return;
    }
    if (e->type == kCGPathElementMoveToPoint) g_sbSubpathCount++;
    const CGPoint *src = &e->points[0];
    sbEmit(ctx, (e->type == kCGPathElementMoveToPoint) ? 1 : 2, src->x, src->y);
}

static BOOL mergePaths(UIView *espView, NSMutableData *d) {
    [d setLength:0];
    SerCtx ctx = { .data = d, .landW = 0, .landH = 0, .lastX = 0, .lastY = 0, .haveLast = 0 };
    {
        const CGRect vb = espView.bounds;
        ctx.landW = (vb.size.width  > vb.size.height) ? vb.size.width  : vb.size.height;
        ctx.landH = (vb.size.width  > vb.size.height) ? vb.size.height : vb.size.width;
    }
    g_sbSubpathCount = 0;

    int emitted = 0;
    for (int i = 0; i < 16; i++) {
        id val = [espView valueForKey:[NSString stringWithUTF8String:kShapeKeys[i]]];
        if (![val isKindOfClass:[CAShapeLayer class]]) continue;
        CGPathRef p = ((CAShapeLayer *)val).path;
        if (!p || CGPathIsEmpty(p)) continue;
        uint8_t tag = 4;
        uint8_t idx = (uint8_t)i;
        [d appendBytes:&tag length:1];
        [d appendBytes:&idx length:1];
        CGPathApply(p, &ctx, serFunc);
        emitted = 1;
    }
    if (!emitted) return NO;

    uint32_t h = 2166136261u;
    for (NSUInteger i = 0; i < d.length; i++) {
        h ^= ((const uint8_t *)d.bytes)[i]; h *= 16777619u;
    }
    (void)h;
    g_sbPathHash = h;
    g_sbLastPathBytes = d.length;
    return YES;
}

static void sb_forget_local_paint_state(void) {
    if (r_is_objc_ptr(g_sbSetPathInv) && remote_call_has_local_state()) {
        r_msg2(g_sbSetPathInv, "release", 0,0,0,0);
    }
    if (g_sbSetPathArgBuf && remote_call_has_local_state()) {
        dlsym_remote("free", g_sbSetPathArgBuf, 0,0,0,0,0,0,0);
    }
    g_sbSetPathInv = 0;
    g_sbSetPathArgBuf = 0;
    g_sbPerformMainSel = 0;
    g_sbInvokeSel = 0;
    g_sbPersistentPath = 0;
    g_sbMirrorPtsBuf = 0;
    g_sbPathHash = 0;
    g_sbLastPathBytes = 0;
    g_sbLastSubpaths = 0;
    g_sbLastCalls = 0;
    g_sbNextPublishUS = 0;
    for (int k = 0; k < SB_PATH_HOLD_FRAMES; k++) g_sbPathRing[k] = 0;
    g_sbPathRingAt = 0;
}

static void sb_disable_layer_actions(uint64_t layer) {
    if (!r_is_objc_ptr(layer)) return;
    uint64_t NSMutableDictionary = r_class("NSMutableDictionary");
    uint64_t NSNullCls = r_class("NSNull");
    if (!r_is_objc_ptr(NSMutableDictionary) || !r_is_objc_ptr(NSNullCls)) return;
    uint64_t dict = r_msg2_main(NSMutableDictionary, "dictionary", 0,0,0,0);
    uint64_t nullObj = r_msg2_main(NSNullCls, "null", 0,0,0,0);
    uint64_t keyPath = r_nsstr_retained("path");
    if (r_is_objc_ptr(dict) && r_is_objc_ptr(nullObj) && r_is_objc_ptr(keyPath)) {
        r_msg2_main(dict, "setObject:forKey:", nullObj, keyPath, 0, 0);
        r_msg2_main(layer, "setActions:", dict, 0,0,0);
    }
}

static uint64_t persistentPath(void) {
    if (g_sbPersistentPath) return g_sbPersistentPath;
    g_sbPersistentPath = dlsym_remote("CGPathCreateMutable", 0,0,0,0,0,0,0,0);
    return g_sbPersistentPath;
}

static uint64_t ptsBuffer(void) {
    if (g_sbMirrorPtsBuf) return g_sbMirrorPtsBuf;
    g_sbMirrorPtsBuf = dlsym_remote("malloc", 65536, 0,0,0,0,0,0,0);
    return g_sbMirrorPtsBuf;
}

static BOOL sb_ensure_setpath_invocation(void) {
    if (r_is_objc_ptr(g_sbSetPathInv) && g_sbSetPathArgBuf) return YES;
    if (!r_is_objc_ptr(g_sbShape)) return NO;

    uint64_t rp = persistentPath();
    if (!rp) return NO;

    uint64_t setPathSel = r_sel("setPath:");
    if (!setPathSel) return NO;

    uint64_t sigSel = r_sel("methodSignatureForSelector:");
    uint64_t sig = r_msg(g_sbShape, sigSel, setPathSel, 0, 0, 0);
    if (!r_is_objc_ptr(sig)) return NO;

    uint64_t NSInvocation = r_class("NSInvocation");
    if (!r_is_objc_ptr(NSInvocation)) return NO;

    uint64_t inv = r_msg(NSInvocation, r_sel("invocationWithMethodSignature:"), sig, 0, 0, 0);
    if (!r_is_objc_ptr(inv)) return NO;
    r_msg2(inv, "retain", 0, 0, 0, 0);

    r_msg2(inv, "setTarget:", g_sbShape, 0, 0, 0);
    r_msg2(inv, "setSelector:", setPathSel, 0, 0, 0);

    uint64_t argBuf = dlsym_remote("malloc", 8, 0,0,0,0,0,0,0);
    if (!argBuf) {
        r_msg2(inv, "release", 0, 0, 0, 0);
        return NO;
    }
    remote_write64(argBuf, rp);
    r_msg2(inv, "setArgument:atIndex:", argBuf, 2, 0, 0);
    r_msg2(inv, "retainArguments", 0, 0, 0, 0);

    g_sbSetPathInv = inv;
    g_sbSetPathArgBuf = argBuf;
    g_sbPerformMainSel = r_sel("performSelectorOnMainThread:withObject:waitUntilDone:");
    g_sbInvokeSel = r_sel("invoke");
    NSLog(@"[SBOverlay] GeometryPathInvocation=0x%llx path=0x%llx", inv, rp);
    return YES;
}

static void sb_invoke_cached_main_raw(void) {
    if (!sb_ensure_setpath_invocation()) {
        uint64_t rp = persistentPath();
        if (rp) r_msg2_main_async(g_sbShape, "setPath:", rp, 0,0,0);
        return;
    }
    remote_write64(g_sbSetPathArgBuf, persistentPath());
    r_msg2(g_sbSetPathInv, "setArgument:atIndex:", g_sbSetPathArgBuf, 2, 0, 0);
    if (g_sbPerformMainSel && g_sbInvokeSel) {
        r_msg(g_sbSetPathInv, g_sbPerformMainSel, g_sbInvokeSel, 0, 0, 0);
    }
}

static int sb_open_session(void) {
    if (!g_kexploit_ready) return -1;
    if (remote_call_has_local_state()) {
        if (remote_call_current_success()) return 0;
        abandon_remote_call();
    }
    r_settle_us(3000);
    int rc = init_remote_call_with_first_exception_timeout("SpringBoard", false, 15000);
    if (rc != 0) {
        NSLog(@"[SBOverlay] extra-thread init failed rc=%d", rc);
        return -1;
    }
    uint64_t pid = do_remote_call_stable(5000, "getpid", 0,0,0,0,0,0,0,0);
    if (pid == 0) {
        destroy_remote_call();
        return -1;
    }
    return 0;
}

int SBoardStartOverlay(void) {
    pthread_mutex_lock(&g_sbLock);
    if (g_sbOverlayOn) { pthread_mutex_unlock(&g_sbLock); return 0; }
    pthread_mutex_unlock(&g_sbLock);

    if (!g_kexploit_ready) return -1;

    NSLog(@"[SBOverlay] Fl0rk start_esp_renderer_in_session...");
    if (sb_open_session() != 0) {
        NSLog(@"[SBOverlay] session open failed");
        return -1;
    }

    uint64_t app = r_msg2_main(r_class("UIApplication"), "sharedApplication", 0,0,0,0);
    if (!r_is_objc_ptr(app)) { destroy_remote_call(); return -1; }

    uint64_t keyWin = r_msg2_main(app, "keyWindow", 0,0,0,0);
    if (!r_is_objc_ptr(keyWin)) {
        uint64_t ws = r_msg2_main(app, "windows", 0,0,0,0);
        uint64_t n = r_is_objc_ptr(ws) ? r_msg2_main(ws, "count", 0,0,0,0) : 0;
        if (n > 0 && n < 64) keyWin = r_msg2_main(ws, "objectAtIndex:", 0,0,0,0);
    }
    if (!r_is_objc_ptr(keyWin)) {
        NSLog(@"[SBOverlay] no SB window");
        destroy_remote_call();
        return -1;
    }

    uint64_t scene = r_msg2_main(keyWin, "windowScene", 0,0,0,0);
    if (!r_is_objc_ptr(scene)) {
        NSLog(@"[SBOverlay] no UIWindowScene");
        destroy_remote_call();
        return -1;
    }

    double bounds[4] = {0, 0, 390, 844};
    uint64_t clsScr = r_class("UIScreen");
    if (r_is_objc_ptr(clsScr)) {
        r_msg2_main_struct_ret(r_msg2_main(clsScr, "mainScreen", 0,0,0,0),
                               "bounds", bounds, 32, NULL,0,NULL,0,NULL,0,NULL,0);
    }

    uint64_t clsCol = r_class("UIColor");
    uint64_t clear = r_is_objc_ptr(clsCol) ? r_msg2_main(clsCol, "clearColor", 0,0,0,0) : 0;
    uint64_t whiteColor = r_is_objc_ptr(clsCol) ? r_msg2_main(clsCol, "whiteColor", 0,0,0,0) : 0;
    uint64_t whiteCGColor = r_is_objc_ptr(whiteColor) ? r_msg2_main(whiteColor, "CGColor", 0,0,0,0) : 0;

    uint64_t winAlloc = r_msg2_main(r_class("UIWindow"), "alloc", 0,0,0,0);
    if (!r_is_objc_ptr(winAlloc)) { destroy_remote_call(); return -1; }

    uint64_t win = r_msg2_main(winAlloc, "initWithWindowScene:", scene, 0,0,0);
    if (!r_is_objc_ptr(win)) {
        NSLog(@"[SBOverlay] initWithWindowScene failed");
        destroy_remote_call();
        return -1;
    }

    r_msg2_main_raw(win, "setFrame:", bounds, 32, NULL,0,NULL,0,NULL,0);
    double winLevel = SB_OVERLAY_WIN_LEVEL;
    r_msg2_main_raw(win, "setWindowLevel:", &winLevel, 8, NULL,0,NULL,0,NULL,0);
    r_msg2_main(win, "setUserInteractionEnabled:", 0, 0,0,0);
    if (r_is_objc_ptr(clear)) r_msg2_main(win, "setBackgroundColor:", clear, 0,0,0);

    uint64_t container = r_msg2_main_raw(r_msg2_main(r_class("UIView"), "alloc", 0,0,0,0),
                                         "initWithFrame:", bounds, 32, NULL,0,NULL,0,NULL,0);
    if (!r_is_objc_ptr(container)) { destroy_remote_call(); return -1; }
    if (r_is_objc_ptr(clear)) r_msg2_main(container, "setBackgroundColor:", clear, 0,0,0);
    r_msg2_main(container, "setUserInteractionEnabled:", 0, 0,0,0);
    r_msg2_main(container, "setOpaque:", 0, 0,0,0);
    r_msg2_main(win, "addSubview:", container, 0,0,0);

    uint64_t shape = r_msg2_main(r_class("CAShapeLayer"), "layer", 0,0,0,0);
    if (!r_is_objc_ptr(shape)) { destroy_remote_call(); return -1; }
    r_msg2_main_raw(shape, "setFrame:", bounds, 32, NULL,0,NULL,0,NULL,0);
    if (r_is_objc_ptr(whiteCGColor)) r_msg2_main(shape, "setStrokeColor:", whiteCGColor, 0,0,0);
    r_msg2_main(shape, "setFillColor:", 0, 0,0,0);
    double lw = 1.5;
    r_msg2_main_raw(shape, "setLineWidth:", &lw, 8, NULL,0,NULL,0,NULL,0);
    r_msg2_main(shape, "setOpaque:", 0, 0,0,0);
    double z = 100;
    r_msg2_main_raw(shape, "setZPosition:", &z, 8, NULL,0,NULL,0,NULL,0);
    sb_disable_layer_actions(shape);

    uint64_t cLayer = r_msg2_main(container, "layer", 0,0,0,0);
    if (r_is_objc_ptr(cLayer)) r_msg2_main(cLayer, "addSublayer:", shape, 0,0,0);

    r_msg2_main(win, "setHidden:", 0, 0,0,0);

    uint64_t key = r_sel("fl0rkffESPMenuWindow");
    if (r_is_objc_ptr(key)) {
        dlsym_remote("objc_setAssociatedObject", app, key, win, 1, 0,0,0,0);
    }

    pthread_mutex_lock(&g_sbLock);
    g_sbWin = win;
    g_sbShape = shape;
    g_sbCanvas = container;
    g_sbOverlayOn = YES;
    g_sbEverOn = 1;
    g_sbConsecFail = 0;
    g_sbLastPublishUS = now_us();
    g_sbRearmAfterUS = 0;
    pthread_mutex_unlock(&g_sbLock);

    sb_forget_local_paint_state();
    (void)persistentPath();
    (void)ptsBuffer();
    (void)sb_ensure_setpath_invocation();

    NSLog(@"[SBOverlay] Fl0rk session LIVE win=0x%llx geom=0x%llx inv=%s",
          win, shape, r_is_objc_ptr(g_sbSetPathInv) ? "OK" : "NO");
    return 0;
}

void SBRemotePushESPFrame(UIView *espView) {
    if (!g_sbOverlayOn) {
        if (g_sbEverOn && now_us() > g_sbRearmAfterUS) {
            g_sbRearmAfterUS = now_us() + 3000000ULL;
            g_sbConsecFail = 0;
            if (SBoardStartOverlay() == 0) {
                NSLog(@"[PUSH-REARM] overlay rebuilt — ESP is live again");
            }
        }
        return;
    }
    if (!espView) return;

    const uint64_t tGate = now_us();
    {
        static uint64_t s_hbUS = 0;
        if (tGate > s_hbUS) {
            s_hbUS = tGate + 1000000ULL;
            const int64_t nextIn = (int64_t)g_sbNextPublishUS - (int64_t)tGate;
            const int64_t sinceDraw = (g_sbLastPublishUS == 0)
                                   ? -1 : (int64_t)(tGate - g_sbLastPublishUS);
            NSLog(@"[PUSH-HB] on=%d ever=%d fail=%d sdead=%d ls=%d ok=%d "
                  @"upd=%llu att=%llu skip=%llu next=%lldms since=%lldms thermal=%ld",
                  (int)g_sbOverlayOn, g_sbEverOn, g_sbConsecFail, g_sbSessionDead,
                  (int)remote_call_has_local_state(),
                  (int)remote_call_current_success(),
                  (unsigned long long)g_sbSummaryUpdates,
                  (unsigned long long)g_sbSummaryAttempts,
                  (unsigned long long)g_sbSummarySkips,
                  (long long)(nextIn / 1000),
                  (long long)(sinceDraw / 1000),
                  (long)NSProcessInfo.processInfo.thermalState);
        }
    }

    if (g_sbEverOn && g_sbLastPublishUS != 0 && tGate > g_sbRearmAfterUS) {
        if (tGate - g_sbLastPublishUS > 3000000ULL) {
            uint64_t wait = g_sbRearmBackoffUS;
            g_sbRearmAfterUS = tGate + wait;
            g_sbRearmBackoffUS = (wait < 60000000ULL) ? (wait * 2) : 60000000ULL;
            g_sbConsecFail = 0;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                const char *why =
                    remote_call_init_failure_description(remote_call_last_init_failure());
                NSLog(@"[PUSH-REARM] nothing drawn for 3s (ls=%d ok=%d init=%s pid=%d)",
                      (int)remote_call_has_local_state(),
                      (int)remote_call_current_success(),
                      why ? why : "?", remote_call_current_pid());
                if (SBoardStartOverlay() == 0) {
                    NSLog(@"[PUSH-REARM] session re-initialised, overlay live");
                } else {
                    NSLog(@"[PUSH-REARM] re-init failed, will retry");
                }
            });
        }
    }
    if (!remote_call_has_local_state() || !remote_call_current_success()) {
        g_sbSummarySkips++;
        return;
    }
    g_sbSessionDead = 0;

    g_sbSummaryAttempts++;

    uint64_t t = now_us();
    if (t < g_sbNextPublishUS) {
        g_sbSummarySkips++;
        return;
    }

    static NSMutableData *ops = nil;
    if (!ops) ops = [NSMutableData dataWithCapacity:8192];

    if (!mergePaths(espView, ops)) {
        g_sbSummarySkips++;
        return;
    }

    static int s_remoteBusy = 0;
    if (__sync_lock_test_and_set(&s_remoteBusy, 1)) {
        g_sbBusyDrops++;
        g_sbSummarySkips++;
        return;
    }
    const uint64_t tAcquire = now_us();

    uint64_t intervalUS = SB_MIN_PUBLISH_INTERVAL_US;
    switch (NSProcessInfo.processInfo.thermalState) {
        case NSProcessInfoThermalStateCritical: intervalUS = 50000ULL; break;
        case NSProcessInfoThermalStateSerious:  intervalUS = 33333ULL; break;
        default: intervalUS = SB_MIN_PUBLISH_INTERVAL_US; break;
    }
    g_sbNextPublishUS = t + intervalUS;
    NSData *frameBytes = [ops copy];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        uint64_t tPubStart = now_us();
        @try {
            if (!remote_call_has_local_state() || !remote_call_current_success()) return;
            if (!r_is_objc_ptr(g_sbShape)) return;

            const int okBefore = remote_call_current_success() ? 1 : 0;
            uint64_t rp = persistentPath();
            const int okAfterPath = remote_call_current_success() ? 1 : 0;
            uint64_t ptsBuf = ptsBuffer();
            const int okAfterBuf = remote_call_current_success() ? 1 : 0;
            if (!okBefore || !rp || !ptsBuf || !okAfterBuf || !okAfterPath) {
                static uint64_t s_probeUS = 0;
                uint64_t tP = now_us();
                if (tP > s_probeUS) {
                    s_probeUS = tP + 2000000ULL;
                    NSLog(@"[PUSH-PROBE] before=%d path=0x%llx afterPath=%d "
                          @"buf=0x%llx afterBuf=%d",
                          okBefore, (unsigned long long)rp, okAfterPath,
                          (unsigned long long)ptsBuf, okAfterBuf);
                }
            }
            if (!rp || !ptsBuf || !remote_call_current_success()) {
                if (remote_call_has_local_state() && !remote_call_current_success()) {
                    if (++g_sbConsecFail < 3) {
                        g_sbSummarySkips++;
                        return;
                    }
                    NSLog(@"[PUSH-DEAD] RemoteCall failed %d times in a row — overlay down",
                          g_sbConsecFail);
                    abandon_remote_call();
                    pthread_mutex_lock(&g_sbLock);
                    g_sbOverlayOn = NO;
                    pthread_mutex_unlock(&g_sbLock);
                    g_sbRearmAfterUS = now_us() + 2000000ULL;
                }
                return;
            }
            g_sbConsecFail = 0;

            size_t len = frameBytes.length;
            const uint8_t *b = (const uint8_t *)frameBytes.bytes;

            uint32_t subpaths = 0;
            uint32_t rectCount = 0;
            uint32_t limbCount = 0;
            uint64_t calls = 0;
            uint32_t drawn = 0;

            uint64_t freshPath = dlsym_remote("CGPathCreateMutable", 0,0,0,0,0,0,0,0);
            calls++;
            if (!freshPath) {
                NSLog(@"[PUSH-PATH] CGPathCreateMutable returned 0 — skipping frame");
                return;
            }
            if (g_sbPathRing[g_sbPathRingAt]) {
                dlsym_remote("CGPathRelease", g_sbPathRing[g_sbPathRingAt], 0,0,0,0,0,0,0);
                g_sbPathRing[g_sbPathRingAt] = 0;
            }
            g_sbPathRing[g_sbPathRingAt] = freshPath;
            g_sbPathRingAt = (g_sbPathRingAt + 1) % SB_PATH_HOLD_FRAMES;
            rp = freshPath;
            g_sbPersistentPath = freshPath;

            double rectBuf[512];
            int rectDoubles = 0;
            int maxPts = 0;
            int nBig = 0;
            int c2 = 0, c3 = 0, c4 = 0, c5to8 = 0, c9to32 = 0, c33p = 0;
            double firstRect[4] = {0, 0, 0, 0};
            int haveFirstRect = 0;

            size_t i = 0;
            int curLayer = -1;
            uint32_t nTrunc = 0;
            while (i < len) {
                double run[2048];
                int rn = 0;
                while (i < len) {
                    uint8_t op = b[i++];
                    if (op == 4) {
                        if (i >= len) { i = len; break; }
                        curLayer = b[i++];
                        continue;
                    }
                    if (i + 16 > len) { i = len; break; }
                    double x, y; memcpy(&x, b+i, 8); memcpy(&y, b+i+8, 8); i += 16;
                    if (op == 1) {
                        if (rn > 0) { i -= 17; break; }
                        run[rn++] = x; run[rn++] = y;
                        continue;
                    }
                    if (rn >= 2046) { nTrunc++; i = len; break; }
                    run[rn++] = x; run[rn++] = y;
                }
                if (rn < 4) continue;
                subpaths++;

                const int np = rn / 2;
                if (np > maxPts) maxPts = np;
                if (np > 8) nBig++;
                if (np == 2) c2++;
                else if (np == 3) c3++;
                else if (np == 4) c4++;
                else if (np <= 8) c5to8++;
                else if (np <= 32) c9to32++;
                else c33p++;
                int isRect = 0;
                double rx = 0, ry = 0, rw = 0, rh = 0;

                if (np == 4) {
                    double minX = run[0], maxX = run[0];
                    double minY = run[1], maxY = run[1];
                    for (int k = 1; k < 4; k++) {
                        double px = run[k*2], py = run[k*2+1];
                        if (px < minX) minX = px;
                        if (px > maxX) maxX = px;
                        if (py < minY) minY = py;
                        if (py > maxY) maxY = py;
                    }
                    const double w = maxX - minX, h = maxY - minY;
                    if (w > 0.5 && h > 0.5) {
                        int c00 = 0, c01 = 0, c11 = 0, c10 = 0;
                        for (int k = 0; k < 4; k++) {
                            const double px = run[k*2], py = run[k*2+1];
                            const int lo  = fabs(px - minX) <= 0.5;
                            const int hi  = fabs(px - maxX) <= 0.5;
                            const int loY = fabs(py - minY) <= 0.5;
                            const int hiY = fabs(py - maxY) <= 0.5;
                            if (lo && loY) c00++;
                            else if (hi && loY) c01++;
                            else if (hi && hiY) c11++;
                            else if (lo && hiY) c10++;
                        }
                        if (c00 == 1 && c01 == 1 && c11 == 1 && c10 == 1) {
                            isRect = 1;
                            rx = minX; ry = minY; rw = w; rh = h;
                        }
                    }
                } else if (np == 2) {
                    {
                        limbCount++;
                        if (curLayer >= 6 && curLayer <= 8) {
                            remote_write(ptsBuf, run, (size_t)rn * 8);
                            dlsym_remote("CGPathAddLines", rp, 0, ptsBuf, 2, 0,0,0,0);
                            calls++; drawn++;
                        }
#if SB_DRAW_BONES
                        else if (curLayer >= 3 && curLayer <= 5) {
                            remote_write(ptsBuf, run, (size_t)rn * 8);
                            dlsym_remote("CGPathAddLines", rp, 0, ptsBuf, 2, 0,0,0,0);
                            calls++; drawn++;
                        }
#endif
                    }
                }

                if (isRect) {
                    if (rectDoubles + 4 > (int)(sizeof(rectBuf)/sizeof(rectBuf[0]))) {
                        remote_write(ptsBuf, rectBuf, (size_t)rectDoubles * 8);
                        dlsym_remote("CGPathAddRects", rp, 0, ptsBuf,
                                     rectDoubles / 4, 0, 0,0,0);
                        calls++; drawn++;
                        rectDoubles = 0;
                    }
                    rectBuf[rectDoubles++] = rx;
                    rectBuf[rectDoubles++] = ry;
                    rectBuf[rectDoubles++] = rw;
                    rectBuf[rectDoubles++] = rh;
                    if (!haveFirstRect) {
                        firstRect[0] = rx; firstRect[1] = ry;
                        firstRect[2] = rw; firstRect[3] = rh;
                        haveFirstRect = 1;
                    }
                    rectCount++;
                    continue;
                }

                remote_write(ptsBuf, run, (size_t)rn * 8);
                dlsym_remote("CGPathAddLines", rp, 0, ptsBuf, np, 0,0,0,0);
                calls++; drawn++;
            }

            if (rectDoubles >= 4) {
                remote_write(ptsBuf, rectBuf, (size_t)rectDoubles * 8);
                dlsym_remote("CGPathAddRects", rp, 0, ptsBuf, rectDoubles / 4, 0,0,0,0);
                calls++; drawn++;
            }

            if (drawn > 0) {
                sb_invoke_cached_main_raw();
                g_sbSummaryUpdates++;
                g_sbLastPublishUS = now_us();
                g_sbRearmBackoffUS = 5000000ULL;
                g_sbLastSubpaths = subpaths;
                g_sbLastCalls = calls;
                {
                    static uint64_t s_sbLogUS = 0;
                    uint64_t nowS = now_us();
                    if (nowS > s_sbLogUS) {
                        s_sbLogUS = nowS + 1000000ULL;
                        uint64_t pubMS = (now_us() - tPubStart) / 1000ULL;
                        static uint64_t s_prevUpd = 0, s_prevUpdUS = 0;
                        static uint64_t s_prevDrops = 0, s_prevHold = 0;
                        uint64_t ups = 0, bdropRate = 0, holdMS = 0;
                        {
                            uint64_t tU = now_us();
                            if (tU > s_prevUpdUS + 1000000ULL) {
                                ups = g_sbSummaryUpdates - s_prevUpd;
                                bdropRate = g_sbBusyDrops - s_prevDrops;
                                holdMS = (g_sbHoldUS - s_prevHold) / 1000ULL;
                                s_prevUpd = g_sbSummaryUpdates;
                                s_prevDrops = g_sbBusyDrops;
                                s_prevHold = g_sbHoldUS;
                                s_prevUpdUS = tU;
                            }
                        }
                        NSLog(@"[SB-PUSH] sub=%u rect=%u limb=%u calls=%llu ms=%llu "
                              @"maxPts=%d nBig=%d r0=%.1f,%.1f,%.1f,%.1f ups=%llu "
                              @"bdrops=%llu hold=%llums pts2=%d pts3=%d pts4=%d "
                              @"pts58=%d pts932=%d pts33=%d hash=%u upd=%llu att=%llu skip=%llu "
                              @"mergedSub=%u trunc=%u",
                              g_sbLastSubpaths, rectCount, limbCount,
                              (unsigned long long)g_sbLastCalls,
                              (unsigned long long)pubMS,
                              maxPts, nBig,
                              firstRect[0], firstRect[1], firstRect[2], firstRect[3],
                              (unsigned long long)ups,
                              (unsigned long long)bdropRate,
                              (unsigned long long)holdMS,
                              c2, c3, c4, c5to8, c9to32, c33p,
                              g_sbPathHash,
                              (unsigned long long)g_sbSummaryUpdates,
                              (unsigned long long)g_sbSummaryAttempts,
                              (unsigned long long)g_sbSummarySkips,
                              g_sbSubpathCount, nTrunc);
                    }
                }
            }
        } @finally {
            g_sbHoldUS += now_us() - tAcquire;
            __sync_lock_release(&s_remoteBusy);
        }
    });
}

void SBoardOverlaySetStatus(const char *utf8) { (void)utf8; }

void SBoardStopOverlay(void) {
    pthread_mutex_lock(&g_sbLock);
    if (!g_sbOverlayOn) { pthread_mutex_unlock(&g_sbLock); return; }
    uint64_t win = g_sbWin;
    uint64_t path = g_sbPersistentPath;
    typedef struct { uint64_t v[SB_PATH_HOLD_FRAMES]; } SBRingBuf;
    SBRingBuf ring;
    for (int k = 0; k < SB_PATH_HOLD_FRAMES; k++) ring.v[k] = g_sbPathRing[k];
    g_sbOverlayOn = NO;
    g_sbWin = 0;
    g_sbShape = 0;
    g_sbCanvas = 0;
    pthread_mutex_unlock(&g_sbLock);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        const NSProcessInfoThermalState th = NSProcessInfo.processInfo.thermalState;
        const bool hot = (th == NSProcessInfoThermalStateSerious ||
                          th == NSProcessInfoThermalStateCritical);

        if (!remote_call_has_local_state()) {
            sb_forget_local_paint_state();
            return;
        }

        if (r_is_objc_ptr(win) && !hot) {
            r_msg2_main_async(win, "setHidden:", 1, 0, 0, 0);
        }

        if (!hot) {
            if (path) {
                dlsym_remote("CGPathRelease", path, 0,0,0,0,0,0,0);
            }
            for (int k = 0; k < SB_PATH_HOLD_FRAMES; k++) {
                if (ring.v[k] && ring.v[k] != path) {
                    dlsym_remote("CGPathRelease", ring.v[k], 0,0,0,0,0,0,0);
                }
            }
        }

        sb_forget_local_paint_state();
        destroy_remote_call();
    });
}
