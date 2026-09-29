//
//  SpringBoardOverlay.m — Fl0rk DrawView with COLOR GROUPS
//
//  Changes vs previous build:
//    - 6 shape layers (was 1) grouped by color. Health bar can now be green,
//      orange or red; box/bone/snapline keep their own colors; FOV yellow.
//    - Group map / colors are hardcoded on the SB side.
//    - Publish interval default 16000us (60 fps) instead of 8000us.
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
#define SB_MIN_PUBLISH_INTERVAL_US 16000ULL
#define SB_DRAW_BONES 0

// Six colour groups.
enum {
    SBG_CYAN = 0,
    SBG_YELLOW = 1,
    SBG_RED = 2,
    SBG_GREEN = 3,
    SBG_ORANGE = 4,
    SBG_DARK = 5,
    SBG_COUNT = 6,
};

// 0..15 layer index -> 0..5 group.
//   0 boxLayer            -> cyan
//   1 boxBotLayer         -> yellow
//   2 boxKnockedLayer     -> red
//   3 boneLayer           -> cyan
//   4 boneBotLayer        -> yellow
//   5 boneKnockedLayer    -> red
//   6 snaplineLayer       -> cyan
//   7 snaplineBotLayer    -> yellow
//   8 snaplineKnockedLayer-> red
//   9 hpFillGreenLayer    -> green
//  10 hpFillOrangeLayer   -> orange
//  11 hpFillRedLayer      -> red
//  12 bgFillBlackLayer    -> dark
//  13 alertLayer          -> green
//  14 fovLayer            -> yellow
//  15 aimAssistLayer      -> cyan
static const uint8_t kLayerGroupMap[16] = {
    0, 1, 2, 0, 1, 2, 0, 1, 2, 3, 4, 2, 5, 3, 1, 0
};

typedef struct { double r, g, b, a; } SBColorF;
static const SBColorF kGroupColor[SBG_COUNT] = {
    { 0.00, 1.00, 1.00, 1.00 },  // cyan
    { 1.00, 1.00, 0.00, 1.00 },  // yellow
    { 1.00, 0.00, 0.00, 1.00 },  // red
    { 0.20, 1.00, 0.20, 1.00 },  // green
    { 1.00, 0.60, 0.00, 1.00 },  // orange
    { 0.00, 0.00, 0.00, 0.55 },  // dark background
};
static const int kGroupFilled[SBG_COUNT] = {
    0, 0, 0, 1, 1, 1
};

static BOOL g_sbOverlayOn = NO;
static uint64_t g_sbWin = 0;
static uint64_t g_sbCanvas = 0;
static uint64_t g_sbLayer[SBG_COUNT] = {0};

#define SB_PATH_HOLD_FRAMES 4
static uint64_t g_sbPathRing[SBG_COUNT][SB_PATH_HOLD_FRAMES] = {{0}};
static int g_sbPathRingAt = 0;
static uint64_t g_sbMirrorPtsBuf = 0;
static pthread_mutex_t g_sbLock = PTHREAD_MUTEX_INITIALIZER;

static uint64_t g_sbSetPathInv[SBG_COUNT] = {0};
static uint64_t g_sbSetPathArgBuf[SBG_COUNT] = {0};
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
static uint8_t g_sbGroupHadData[SBG_COUNT] = {0};

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
    return emitted ? YES : NO;
}

static void sb_forget_local_paint_state(void) {
    for (int g = 0; g < SBG_COUNT; g++) {
        if (r_is_objc_ptr(g_sbSetPathInv[g]) && remote_call_has_local_state()) {
            r_msg2(g_sbSetPathInv[g], "release", 0,0,0,0);
        }
        if (g_sbSetPathArgBuf[g] && remote_call_has_local_state()) {
            dlsym_remote("free", g_sbSetPathArgBuf[g], 0,0,0,0,0,0,0);
        }
        g_sbSetPathInv[g] = 0;
        g_sbSetPathArgBuf[g] = 0;
        for (int k = 0; k < SB_PATH_HOLD_FRAMES; k++) g_sbPathRing[g][k] = 0;
    }
    g_sbPathRingAt = 0;
    g_sbPerformMainSel = 0;
    g_sbInvokeSel = 0;
    g_sbMirrorPtsBuf = 0;
    g_sbNextPublishUS = 0;
    g_sbLastSubpaths = 0;
    g_sbLastCalls = 0;
    for (int g = 0; g < SBG_COUNT; g++) g_sbGroupHadData[g] = 0;
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

static uint64_t ptsBuffer(void) {
    if (g_sbMirrorPtsBuf) return g_sbMirrorPtsBuf;
    g_sbMirrorPtsBuf = dlsym_remote("malloc", 65536, 0,0,0,0,0,0,0);
    return g_sbMirrorPtsBuf;
}

static uint64_t makeColor(double r, double g, double b, double a) {
    uint64_t cls = r_class("UIColor");
    if (!r_is_objc_ptr(cls)) return 0;
    double args[4] = { r, g, b, a };
    uint64_t col = r_msg2_main_raw(cls, "colorWithRed:green:blue:alpha:",
                                   args, 32, NULL,0,NULL,0,NULL,0);
    return col;
}

static BOOL sb_ensure_setpath_invocation_for_group(int g) {
    if (g < 0 || g >= SBG_COUNT) return NO;
    if (r_is_objc_ptr(g_sbSetPathInv[g]) && g_sbSetPathArgBuf[g]) return YES;
    if (!r_is_objc_ptr(g_sbLayer[g])) return NO;

    uint64_t setPathSel = r_sel("setPath:");
    if (!setPathSel) return NO;

    uint64_t sigSel = r_sel("methodSignatureForSelector:");
    uint64_t sig = r_msg(g_sbLayer[g], sigSel, setPathSel, 0, 0, 0);
    if (!r_is_objc_ptr(sig)) return NO;

    uint64_t NSInvocation = r_class("NSInvocation");
    if (!r_is_objc_ptr(NSInvocation)) return NO;

    uint64_t inv = r_msg(NSInvocation, r_sel("invocationWithMethodSignature:"), sig, 0, 0, 0);
    if (!r_is_objc_ptr(inv)) return NO;
    r_msg2(inv, "retain", 0, 0, 0, 0);
    r_msg2(inv, "setTarget:", g_sbLayer[g], 0, 0, 0);
    r_msg2(inv, "setSelector:", setPathSel, 0, 0, 0);

    uint64_t argBuf = dlsym_remote("malloc", 8, 0,0,0,0,0,0,0);
    if (!argBuf) {
        r_msg2(inv, "release", 0, 0, 0, 0);
        return NO;
    }
    r_msg2(inv, "setArgument:atIndex:", argBuf, 2, 0, 0);
    r_msg2(inv, "retainArguments", 0, 0, 0, 0);

    g_sbSetPathInv[g] = inv;
    g_sbSetPathArgBuf[g] = argBuf;
    if (!g_sbPerformMainSel) {
        g_sbPerformMainSel = r_sel("performSelectorOnMainThread:withObject:waitUntilDone:");
        g_sbInvokeSel = r_sel("invoke");
    }
    return YES;
}

static void sb_invoke_setpath(int g, uint64_t path) {
    if (g < 0 || g >= SBG_COUNT) return;
    if (!sb_ensure_setpath_invocation_for_group(g)) {
        if (r_is_objc_ptr(g_sbLayer[g])) {
            // FIX: r_msg2_main_async takes 6 args (obj, sel, a0, a1, a2, a3), not 7.
            r_msg2_main_async(g_sbLayer[g], "setPath:", path, 0, 0, 0);
        }
        return;
    }
    remote_write64(g_sbSetPathArgBuf[g], path);
    r_msg2(g_sbSetPathInv[g], "setArgument:atIndex:", g_sbSetPathArgBuf[g], 2, 0, 0);
    if (g_sbPerformMainSel && g_sbInvokeSel) {
        r_msg(g_sbSetPathInv[g], g_sbPerformMainSel, g_sbInvokeSel, 0, 0, 0);
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
    if (rc != 0) return -1;
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

    NSLog(@"[SBOverlay] start (6 colour groups, 60fps)...");
    if (sb_open_session() != 0) return -1;

    uint64_t app = r_msg2_main(r_class("UIApplication"), "sharedApplication", 0,0,0,0);
    if (!r_is_objc_ptr(app)) { destroy_remote_call(); return -1; }

    uint64_t keyWin = r_msg2_main(app, "keyWindow", 0,0,0,0);
    if (!r_is_objc_ptr(keyWin)) {
        uint64_t ws = r_msg2_main(app, "windows", 0,0,0,0);
        uint64_t n = r_is_objc_ptr(ws) ? r_msg2_main(ws, "count", 0,0,0,0) : 0;
        if (n > 0 && n < 64) keyWin = r_msg2_main(ws, "objectAtIndex:", 0,0,0,0);
    }
    if (!r_is_objc_ptr(keyWin)) { destroy_remote_call(); return -1; }

    uint64_t scene = r_msg2_main(keyWin, "windowScene", 0,0,0,0);
    if (!r_is_objc_ptr(scene)) { destroy_remote_call(); return -1; }

    double bounds[4] = {0, 0, 390, 844};
    uint64_t clsScr = r_class("UIScreen");
    if (r_is_objc_ptr(clsScr)) {
        r_msg2_main_struct_ret(r_msg2_main(clsScr, "mainScreen", 0,0,0,0),
                               "bounds", bounds, 32, NULL,0,NULL,0,NULL,0,NULL,0);
    }

    uint64_t clsCol = r_class("UIColor");
    uint64_t clear = r_is_objc_ptr(clsCol) ? r_msg2_main(clsCol, "clearColor", 0,0,0,0) : 0;

    uint64_t winAlloc = r_msg2_main(r_class("UIWindow"), "alloc", 0,0,0,0);
    if (!r_is_objc_ptr(winAlloc)) { destroy_remote_call(); return -1; }

    uint64_t win = r_msg2_main(winAlloc, "initWithWindowScene:", scene, 0,0,0);
    if (!r_is_objc_ptr(win)) { destroy_remote_call(); return -1; }

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

    uint64_t cLayer = r_msg2_main(container, "layer", 0,0,0,0);
    if (!r_is_objc_ptr(cLayer)) { destroy_remote_call(); return -1; }

    for (int g = 0; g < SBG_COUNT; g++) {
        uint64_t shape = r_msg2_main(r_class("CAShapeLayer"), "layer", 0,0,0,0);
        if (!r_is_objc_ptr(shape)) continue;

        r_msg2_main_raw(shape, "setFrame:", bounds, 32, NULL,0,NULL,0,NULL,0);

        uint64_t color = makeColor(kGroupColor[g].r, kGroupColor[g].g,
                                   kGroupColor[g].b, kGroupColor[g].a);
        uint64_t cgcol = r_is_objc_ptr(color)
            ? r_msg2_main(color, "CGColor", 0,0,0,0) : 0;

        if (kGroupFilled[g]) {
            r_msg2_main(shape, "setStrokeColor:", 0, 0,0,0);
            if (r_is_objc_ptr(cgcol)) r_msg2_main(shape, "setFillColor:", cgcol, 0,0,0);
            double lw = 0.0;
            r_msg2_main_raw(shape, "setLineWidth:", &lw, 8, NULL,0,NULL,0,NULL,0);
        } else {
            if (r_is_objc_ptr(cgcol)) r_msg2_main(shape, "setStrokeColor:", cgcol, 0,0,0);
            r_msg2_main(shape, "setFillColor:", 0, 0,0,0);
            double lw = 1.5;
            r_msg2_main_raw(shape, "setLineWidth:", &lw, 8, NULL,0,NULL,0,NULL,0);
        }
        r_msg2_main(shape, "setOpaque:", 0, 0,0,0);
        double z = 100.0 + (double)g;
        r_msg2_main_raw(shape, "setZPosition:", &z, 8, NULL,0,NULL,0,NULL,0);
        sb_disable_layer_actions(shape);
        r_msg2_main(cLayer, "addSublayer:", shape, 0,0,0);

        g_sbLayer[g] = shape;
    }

    r_msg2_main(win, "setHidden:", 0, 0,0,0);

    pthread_mutex_lock(&g_sbLock);
    g_sbWin = win;
    g_sbCanvas = container;
    g_sbOverlayOn = YES;
    g_sbEverOn = 1;
    g_sbConsecFail = 0;
    g_sbLastPublishUS = now_us();
    g_sbRearmAfterUS = 0;
    for (int g = 0; g < SBG_COUNT; g++) g_sbGroupHadData[g] = 0;
    pthread_mutex_unlock(&g_sbLock);

    sb_forget_local_paint_state();
    (void)ptsBuffer();
    for (int g = 0; g < SBG_COUNT; g++) (void)sb_ensure_setpath_invocation_for_group(g);

    NSLog(@"[SBOverlay] session LIVE win=0x%llx groups=%d @60fps",
          win, SBG_COUNT);
    return 0;
}

void SBRemotePushESPFrame(UIView *espView) {
    if (!g_sbOverlayOn) {
        if (g_sbEverOn && now_us() > g_sbRearmAfterUS) {
            g_sbRearmAfterUS = now_us() + 3000000ULL;
            g_sbConsecFail = 0;
            if (SBoardStartOverlay() == 0) {
                NSLog(@"[PUSH-REARM] overlay rebuilt");
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
            const int64_t sinceDraw = (g_sbLastPublishUS == 0)
                                   ? -1 : (int64_t)(tGate - g_sbLastPublishUS);
            NSLog(@"[PUSH-HB] on=%d ever=%d fail=%d ls=%d ok=%d "
                  @"upd=%llu att=%llu skip=%llu since=%lldms thermal=%ld",
                  (int)g_sbOverlayOn, g_sbEverOn, g_sbConsecFail,
                  (int)remote_call_has_local_state(),
                  (int)remote_call_current_success(),
                  (unsigned long long)g_sbSummaryUpdates,
                  (unsigned long long)g_sbSummaryAttempts,
                  (unsigned long long)g_sbSummarySkips,
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
                if (SBoardStartOverlay() == 0) {
                    NSLog(@"[PUSH-REARM] session re-initialised");
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
        for (int g = 0; g < SBG_COUNT; g++) {
            if (g_sbGroupHadData[g]) {
                sb_invoke_setpath(g, 0);
                g_sbGroupHadData[g] = 0;
            }
        }
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
            uint64_t ptsBuf = ptsBuffer();
            if (!ptsBuf || !remote_call_current_success()) return;

            size_t len = frameBytes.length;
            const uint8_t *b = (const uint8_t *)frameBytes.bytes;

            uint8_t groupMask = 0;
            for (size_t i = 0; i + 1 < len; ) {
                uint8_t op = b[i++];
                if (op == 4) {
                    uint8_t idx = b[i++];
                    if (idx < 16) groupMask |= (1 << kLayerGroupMap[idx]);
                    continue;
                }
                if (i + 16 > len) break;
                i += 16;
            }

            CGMutablePathRef gpath[SBG_COUNT] = {0};
            double rectBuf[SBG_COUNT][512];
            int rectDoubles[SBG_COUNT] = {0};
            uint32_t subpaths = 0, rectCount = 0, limbCount = 0;
            uint64_t calls = 0;
            int curGroup = -1;
            uint32_t nTrunc = 0;

            for (int g = 0; g < SBG_COUNT; g++) {
                if (!(groupMask & (1 << g))) continue;
                uint64_t p = dlsym_remote("CGPathCreateMutable", 0,0,0,0,0,0,0,0);
                calls++;
                if (!p) continue;
                gpath[g] = (CGMutablePathRef)p;
                int slot = g_sbPathRingAt % SB_PATH_HOLD_FRAMES;
                if (g_sbPathRing[g][slot]) {
                    dlsym_remote("CGPathRelease", g_sbPathRing[g][slot], 0,0,0,0,0,0,0);
                    g_sbPathRing[g][slot] = 0;
                }
                g_sbPathRing[g][slot] = p;
            }
            g_sbPathRingAt = (g_sbPathRingAt + 1) % SB_PATH_HOLD_FRAMES;

            size_t i = 0;
            while (i < len) {
                uint8_t op = b[i++];
                if (op == 4) {
                    uint8_t idx = b[i++];
                    curGroup = (idx < 16) ? kLayerGroupMap[idx] : -1;
                    continue;
                }
                if (curGroup < 0 || !gpath[curGroup]) {
                    if (i + 16 <= len) i += 16; else break;
                    continue;
                }

                double run[2048];
                int rn = 0;
                int pendingOp = op;
                while (i < len || pendingOp) {
                    uint8_t curOp;
                    if (pendingOp) { curOp = (uint8_t)pendingOp; pendingOp = 0; }
                    else curOp = b[i++];
                    if (curOp == 4) { i -= 1; break; }
                    if (i + 16 > len) { i = len; break; }
                    double x, y; memcpy(&x, b+i, 8); memcpy(&y, b+i+8, 8); i += 16;
                    if (curOp == 1) {
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

                if (np == 2) {
                    limbCount++;
                    remote_write(ptsBuf, run, (size_t)rn * 8);
                    dlsym_remote("CGPathAddLines", (uint64_t)gpath[curGroup],
                                 0, ptsBuf, 2, 0,0,0,0);
                    calls++;
                    continue;
                }

                int isRect = 0;
                double rx = 0, ry = 0, rw = 0, rh = 0;
                if (np == 4) {
                    double minX = run[0], maxX = run[0], minY = run[1], maxY = run[1];
                    for (int k = 1; k < 4; k++) {
                        double px = run[k*2], py = run[k*2+1];
                        if (px < minX) minX = px; if (px > maxX) maxX = px;
                        if (py < minY) minY = py; if (py > maxY) maxY = py;
                    }
                    const double w = maxX - minX, h = maxY - minY;
                    if (w > 0.5 && h > 0.5) {
                        int c00=0,c01=0,c11=0,c10=0;
                        for (int k = 0; k < 4; k++) {
                            const double px = run[k*2], py = run[k*2+1];
                            const int lo = fabs(px-minX)<=0.5, hi = fabs(px-maxX)<=0.5;
                            const int loY= fabs(py-minY)<=0.5, hiY= fabs(py-maxY)<=0.5;
                            if (lo&&loY) c00++;
                            else if (hi&&loY) c01++;
                            else if (hi&&hiY) c11++;
                            else if (lo&&hiY) c10++;
                        }
                        if (c00==1 && c01==1 && c11==1 && c10==1) {
                            isRect = 1; rx = minX; ry = minY; rw = w; rh = h;
                        }
                    }
                }

                if (isRect) {
                    int *rd = &rectDoubles[curGroup];
                    if (*rd + 4 > 512) {
                        remote_write(ptsBuf, rectBuf[curGroup], (size_t)(*rd) * 8);
                        dlsym_remote("CGPathAddRects", (uint64_t)gpath[curGroup],
                                     0, ptsBuf, (uint64_t)(*rd) / 4, 0,0,0,0);
                        calls++;
                        *rd = 0;
                    }
                    rectBuf[curGroup][(*rd)++] = rx;
                    rectBuf[curGroup][(*rd)++] = ry;
                    rectBuf[curGroup][(*rd)++] = rw;
                    rectBuf[curGroup][(*rd)++] = rh;
                    rectCount++;
                    continue;
                }

                remote_write(ptsBuf, run, (size_t)rn * 8);
                dlsym_remote("CGPathAddLines", (uint64_t)gpath[curGroup],
                             0, ptsBuf, np, 0,0,0,0);
                calls++;
            }

            for (int g = 0; g < SBG_COUNT; g++) {
                if (rectDoubles[g] >= 4) {
                    remote_write(ptsBuf, rectBuf[g], (size_t)rectDoubles[g] * 8);
                    dlsym_remote("CGPathAddRects", (uint64_t)gpath[g],
                                 0, ptsBuf, (uint64_t)rectDoubles[g] / 4, 0,0,0,0);
                    calls++;
                }
            }

            for (int g = 0; g < SBG_COUNT; g++) {
                const uint8_t has = (groupMask & (1 << g)) ? 1 : 0;
                if (has) {
                    sb_invoke_setpath(g, (uint64_t)gpath[g]);
                    g_sbGroupHadData[g] = 1;
                } else if (g_sbGroupHadData[g]) {
                    sb_invoke_setpath(g, 0);
                    g_sbGroupHadData[g] = 0;
                }
            }

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
                    NSLog(@"[SB-PUSH] mask=0x%02x sub=%u rect=%u limb=%u calls=%llu "
                          @"ms=%llu upd=%llu att=%llu skip=%llu trunc=%u",
                          groupMask, subpaths, rectCount, limbCount,
                          (unsigned long long)calls, (unsigned long long)pubMS,
                          (unsigned long long)g_sbSummaryUpdates,
                          (unsigned long long)g_sbSummaryAttempts,
                          (unsigned long long)g_sbSummarySkips,
                          nTrunc);
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
    typedef struct { uint64_t v[SBG_COUNT][SB_PATH_HOLD_FRAMES]; } SBRing;
    SBRing ring;
    for (int g = 0; g < SBG_COUNT; g++)
        for (int k = 0; k < SB_PATH_HOLD_FRAMES; k++)
            ring.v[g][k] = g_sbPathRing[g][k];
    g_sbOverlayOn = NO;
    g_sbWin = 0;
    g_sbCanvas = 0;
    pthread_mutex_unlock(&g_sbLock);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        const NSProcessInfoThermalState th = NSProcessInfo.processInfo.thermalState;
        const bool hot = (th == NSProcessInfoThermalStateSerious ||
                          th == NSProcessInfoThermalStateCritical);
        if (!remote_call_has_local_state()) { sb_forget_local_paint_state(); return; }

        if (r_is_objc_ptr(win) && !hot) {
            // r_msg2_main_async: 6 args only.
            r_msg2_main_async(win, "setHidden:", 1, 0, 0, 0);
        }
        if (!hot) {
            for (int g = 0; g < SBG_COUNT; g++) {
                for (int k = 0; k < SB_PATH_HOLD_FRAMES; k++) {
                    if (ring.v[g][k]) {
                        dlsym_remote("CGPathRelease", ring.v[g][k], 0,0,0,0,0,0,0);
                    }
                }
            }
        }
        sb_forget_local_paint_state();
        destroy_remote_call();
    });
}
