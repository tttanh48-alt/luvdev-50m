//
//  SpringBoardOverlay.m — Fl0rk DrawView
//
//  Shape #1 (stroke): box / snapline / bone / fov — dày 1.2pt trắng.
//  Shape #2 (fill): count + HP bars + alert — fill TRẮNG đặc.
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
#define SB_MIN_PUBLISH_INTERVAL_US 16666ULL
#define SB_DRAW_BONES 0

// Line width cho shape #1 (box/snapline/fov). Tăng từ 0.6 → 1.2 để nhìn rõ.
#define SB_STROKE_WIDTH 1.2

// Fill cho countLayer + HP bar: 1 = TRẮNG đặc (nhìn rõ trên nền tối),
// 0 = ĐEN (nhìn rõ trên nền sáng). Mặc định TRẮNG.
#define SB_FILL_USE_WHITE 1

static BOOL g_sbOverlayOn = NO;
static uint64_t g_sbWin = 0;
static uint64_t g_sbShape = 0;      // stroke
static uint64_t g_sbFillShape = 0;  // fill
static uint64_t g_sbCanvas = 0;

static uint64_t g_sbPersistentPath = 0;
#define SB_PATH_HOLD_FRAMES 4
static uint64_t g_sbPathRing[SB_PATH_HOLD_FRAMES] = {0};
static int g_sbPathRingAt = 0;
static uint64_t g_sbFillPathRing[SB_PATH_HOLD_FRAMES] = {0};
static int g_sbFillPathRingAt = 0;

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

static const char *kShapeKeys[17] = {
    "boxLayer", "boxBotLayer", "boxKnockedLayer",
    "boneLayer", "boneBotLayer", "boneKnockedLayer",
    "snaplineLayer", "snaplineBotLayer", "snaplineKnockedLayer",
    "hpFillGreenLayer", "hpFillOrangeLayer", "hpFillRedLayer",
    "bgFillBlackLayer", "alertLayer", "fovLayer", "aimAssistLayer",
    "countLayer"
};

// Layer nào dùng FILL thay vì stroke:
//   9 hpFillGreen, 10 hpFillOrange, 11 hpFillRed,
//   13 alert, 16 countLayer
// bgFillBlack (12) giữ stroke → viền quanh thanh máu.
#define SB_IS_FILL_LAYER(L) ((L) == 9 || (L) == 10 || (L) == 11 || (L) == 13 || (L) == 16)

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
    for (int i = 0; i < 17; i++) {
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
    g_sbFillShape = 0;
    for (int k = 0; k < SB_PATH_HOLD_FRAMES; k++) g_sbFillPathRing[k] = 0;
    g_sbFillPathRingAt = 0;
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

static void sb_invoke_setpath(uint64_t shape, uint64_t path) {
    if (!r_is_objc_ptr(shape) || !path) return;
    if (!sb_ensure_setpath_invocation()) {
        r_msg2_main_async(shape, "setPath:", path, 0,0,0);
        return;
    }
    r_msg2(g_sbSetPathInv, "setTarget:", shape, 0, 0, 0);
    remote_write64(g_sbSetPathArgBuf, path);
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

    NSLog(@"[SBOverlay] start...");
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
    uint64_t blackColor = r_is_objc_ptr(clsCol) ? r_msg2_main(clsCol, "blackColor", 0,0,0,0) : 0;
    uint64_t whiteCGColor = r_is_objc_ptr(whiteColor) ? r_msg2_main(whiteColor, "CGColor", 0,0,0,0) : 0;
    uint64_t blackCGColor = r_is_objc_ptr(blackColor) ? r_msg2_main(blackColor, "CGColor", 0,0,0,0) : 0;

    uint64_t winAlloc = r_msg2_main(r_class("UIWindow"), "alloc", 0,0,0,0);
    if (!r_is_objc_ptr(winAlloc)) { destroy_remote_call(); return -1; }

    uint64_t win = r_msg2_main(winAlloc, "initWithWindowScene:", scene, 0,0,0);
    if (!r_is_objc_ptr(win)) {
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

    // ===== SHAPE #1: stroke trắng (box / snapline / bone / fov) =====
    uint64_t shape = r_msg2_main(r_class("CAShapeLayer"), "layer", 0,0,0,0);
    if (!r_is_objc_ptr(shape)) { destroy_remote_call(); return -1; }
    r_msg2_main_raw(shape, "setFrame:", bounds, 32, NULL,0,NULL,0,NULL,0);
    if (r_is_objc_ptr(whiteCGColor)) r_msg2_main(shape, "setStrokeColor:", whiteCGColor, 0,0,0);
    r_msg2_main(shape, "setFillColor:", 0, 0,0,0);
    // Line width 1.2pt — nhìn rõ hơn 0.6pt cũ
    double lw = SB_STROKE_WIDTH;
    r_msg2_main_raw(shape, "setLineWidth:", &lw, 8, NULL,0,NULL,0,NULL,0);
    r_msg2_main(shape, "setOpaque:", 0, 0,0,0);
    double z1 = 100;
    r_msg2_main_raw(shape, "setZPosition:", &z1, 8, NULL,0,NULL,0,NULL,0);
    sb_disable_layer_actions(shape);

    // ===== SHAPE #2: FILL (count + HP bar + alert) =====
    uint64_t fillShape = r_msg2_main(r_class("CAShapeLayer"), "layer", 0,0,0,0);
    if (r_is_objc_ptr(fillShape)) {
        r_msg2_main_raw(fillShape, "setFrame:", bounds, 32, NULL,0,NULL,0,NULL,0);
        uint64_t chosenFill = SB_FILL_USE_WHITE ? whiteCGColor : blackCGColor;
        if (r_is_objc_ptr(chosenFill)) r_msg2_main(fillShape, "setFillColor:", chosenFill, 0,0,0);
        r_msg2_main(fillShape, "setStrokeColor:", 0, 0,0,0);
        r_msg2_main(fillShape, "setOpaque:", 0, 0,0,0);
        double z2 = 101;
        r_msg2_main_raw(fillShape, "setZPosition:", &z2, 8, NULL,0,NULL,0,NULL,0);
        sb_disable_layer_actions(fillShape);
    }

    uint64_t cLayer = r_msg2_main(container, "layer", 0,0,0,0);
    if (r_is_objc_ptr(cLayer)) {
        r_msg2_main(cLayer, "addSublayer:", shape, 0,0,0);
        if (r_is_objc_ptr(fillShape)) r_msg2_main(cLayer, "addSublayer:", fillShape, 0,0,0);
    }

    r_msg2_main(win, "setHidden:", 0, 0,0,0);

    uint64_t key = r_sel("fl0rkffESPMenuWindow");
    if (r_is_objc_ptr(key)) {
        dlsym_remote("objc_setAssociatedObject", app, key, win, 1, 0,0,0,0);
    }

    pthread_mutex_lock(&g_sbLock);
    g_sbWin = win;
    g_sbShape = shape;
    g_sbFillShape = fillShape;
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

    NSLog(@"[SBOverlay] LIVE stroke=0x%llx fill=0x%llx fillWhite=%d",
          shape, fillShape, (int)SB_FILL_USE_WHITE);
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
            NSLog(@"[PUSH-HB] on=%d upd=%llu att=%llu skip=%llu",
                  (int)g_sbOverlayOn,
                  (unsigned long long)g_sbSummaryUpdates,
                  (unsigned long long)g_sbSummaryAttempts,
                  (unsigned long long)g_sbSummarySkips);
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

            uint64_t ptsBuf = ptsBuffer();
            if (!ptsBuf || !remote_call_current_success()) {
                if (++g_sbConsecFail >= 3) {
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

            // Tạo 2 path song song: stroke + fill
            uint64_t strokePath = dlsym_remote("CGPathCreateMutable", 0,0,0,0,0,0,0,0);
            uint64_t fillPath   = dlsym_remote("CGPathCreateMutable", 0,0,0,0,0,0,0,0);
            calls += 2;
            if (!strokePath || !fillPath) return;

            // Ring buffer release cũ
            if (g_sbPathRing[g_sbPathRingAt]) {
                dlsym_remote("CGPathRelease", g_sbPathRing[g_sbPathRingAt], 0,0,0,0,0,0,0);
                g_sbPathRing[g_sbPathRingAt] = 0;
            }
            g_sbPathRing[g_sbPathRingAt] = strokePath;
            g_sbPathRingAt = (g_sbPathRingAt + 1) % SB_PATH_HOLD_FRAMES;

            if (g_sbFillPathRing[g_sbFillPathRingAt]) {
                dlsym_remote("CGPathRelease", g_sbFillPathRing[g_sbFillPathRingAt], 0,0,0,0,0,0,0);
                g_sbFillPathRing[g_sbFillPathRingAt] = 0;
            }
            g_sbFillPathRing[g_sbFillPathRingAt] = fillPath;
            g_sbFillPathRingAt = (g_sbFillPathRingAt + 1) % SB_PATH_HOLD_FRAMES;

            g_sbPersistentPath = strokePath;

            double rectBuf[512];
            int rectDoubles = 0;
            double fillRectBuf[256];
            int fillRectDoubles = 0;

            size_t i = 0;
            int curLayer = -1;
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
                    if (rn >= 2046) { i = len; break; }
                    run[rn++] = x; run[rn++] = y;
                }
                if (rn < 4) continue;
                subpaths++;

                const int np = rn / 2;
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
                    limbCount++;
                    if (curLayer >= 6 && curLayer <= 8) {
                        remote_write(ptsBuf, run, (size_t)rn * 8);
                        dlsym_remote("CGPathAddLines", strokePath, 0, ptsBuf, 2, 0,0,0,0);
                        calls++; drawn++;
                    }
                }

                if (isRect) {
                    const bool isFill = SB_IS_FILL_LAYER(curLayer);
                    if (isFill) {
                        if (fillRectDoubles + 4 > (int)(sizeof(fillRectBuf)/sizeof(fillRectBuf[0]))) {
                            remote_write(ptsBuf, fillRectBuf, (size_t)fillRectDoubles * 8);
                            dlsym_remote("CGPathAddRects", fillPath, 0, ptsBuf,
                                         fillRectDoubles / 4, 0, 0,0,0);
                            calls++; drawn++;
                            fillRectDoubles = 0;
                        }
                        fillRectBuf[fillRectDoubles++] = rx;
                        fillRectBuf[fillRectDoubles++] = ry;
                        fillRectBuf[fillRectDoubles++] = rw;
                        fillRectBuf[fillRectDoubles++] = rh;
                    } else {
                        if (rectDoubles + 4 > (int)(sizeof(rectBuf)/sizeof(rectBuf[0]))) {
                            remote_write(ptsBuf, rectBuf, (size_t)rectDoubles * 8);
                            dlsym_remote("CGPathAddRects", strokePath, 0, ptsBuf,
                                         rectDoubles / 4, 0, 0,0,0);
                            calls++; drawn++;
                            rectDoubles = 0;
                        }
                        rectBuf[rectDoubles++] = rx;
                        rectBuf[rectDoubles++] = ry;
                        rectBuf[rectDoubles++] = rw;
                        rectBuf[rectDoubles++] = rh;
                    }
                    rectCount++;
                    continue;
                }

                uint64_t targetPath = SB_IS_FILL_LAYER(curLayer) ? fillPath : strokePath;
                remote_write(ptsBuf, run, (size_t)rn * 8);
                dlsym_remote("CGPathAddLines", targetPath, 0, ptsBuf, np, 0,0,0,0);
                calls++; drawn++;
            }

            if (rectDoubles >= 4) {
                remote_write(ptsBuf, rectBuf, (size_t)rectDoubles * 8);
                dlsym_remote("CGPathAddRects", strokePath, 0, ptsBuf, rectDoubles / 4, 0,0,0,0);
                calls++; drawn++;
            }
            if (fillRectDoubles >= 4) {
                remote_write(ptsBuf, fillRectBuf, (size_t)fillRectDoubles * 8);
                dlsym_remote("CGPathAddRects", fillPath, 0, ptsBuf, fillRectDoubles / 4, 0,0,0,0);
                calls++; drawn++;
            }

            if (drawn > 0) {
                sb_invoke_setpath(g_sbShape, strokePath);
                if (r_is_objc_ptr(g_sbFillShape)) {
                    sb_invoke_setpath(g_sbFillShape, fillPath);
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
                        NSLog(@"[SB-PUSH] sub=%u rect=%u limb=%u calls=%llu ms=%llu upd=%llu",
                              g_sbLastSubpaths, rectCount, limbCount,
                              (unsigned long long)g_sbLastCalls,
                              (unsigned long long)pubMS,
                              (unsigned long long)g_sbSummaryUpdates);
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
    SBRingBuf ring, fillRing;
    for (int k = 0; k < SB_PATH_HOLD_FRAMES; k++) {
        ring.v[k] = g_sbPathRing[k];
        fillRing.v[k] = g_sbFillPathRing[k];
    }
    g_sbOverlayOn = NO;
    g_sbWin = 0;
    g_sbShape = 0;
    g_sbFillShape = 0;
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
            if (path) dlsym_remote("CGPathRelease", path, 0,0,0,0,0,0,0);
            for (int k = 0; k < SB_PATH_HOLD_FRAMES; k++) {
                if (ring.v[k] && ring.v[k] != path)
                    dlsym_remote("CGPathRelease", ring.v[k], 0,0,0,0,0,0,0);
            }
        }
        for (int k = 0; k < SB_PATH_HOLD_FRAMES; k++) {
            if (fillRing.v[k])
                dlsym_remote("CGPathRelease", fillRing.v[k], 0,0,0,0,0,0,0);
        }

        sb_forget_local_paint_state();
        destroy_remote_call();
    });
}
