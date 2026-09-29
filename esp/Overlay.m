//
//  DirectOverlay.mm — ESP offscreen host (NOT Direct/SBSAccessibility overlay)
//
//  User direction: this build draws ONLY via SpringBoard RemoteCall.
//  Local window exists solely so ESP_View's GCD timer runs and mirrors
//  paths through SBRemotePushESPFrame. Window stays hidden/alpha=0.
//
#import "DirectOverlay.h"
#import "../esp/esp.h"
#import "../esp/ESPPrefs.h"
#import "../esp/GameOffsets.h"
#import "../esp/menu.h"
#import "../../app/KeepAlive.h"
#import <objc/runtime.h>

static UIWindow *g_espHostWindow = nil;

@interface ESPHostPassThroughView : UIView
@end
@implementation ESPHostPassThroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    return hit;
}
@end

@interface ESPHostVC : UIViewController
@end
@implementation ESPHostVC
- (void)loadView {
    self.view = [[ESPHostPassThroughView alloc] initWithFrame:CGRectZero];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.userInteractionEnabled = YES;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}
- (BOOL)shouldAutorotate { return YES; }
@end

int StartESPHost(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_espHostWindow) return;

        [[KeepAlive shared] start];
        ESPPrefsSync();
        ESPSyncFromPrefs();
        GameOffsetsReload();

        ESPHostVC *vc = [[ESPHostVC alloc] init];
        CGRect screen = [UIScreen mainScreen].bounds;

        ESP_View *espView = [[ESP_View alloc] initWithFrame:screen];
        espView.backgroundColor = [UIColor clearColor];
        espView.userInteractionEnabled = NO;
        [vc.view addSubview:espView];

        // Menu stays local for toggles; not an all-apps overlay.
        MenuView *menuView = [[MenuView alloc] initWithFrame:screen];
        menuView.userInteractionEnabled = YES;
        [vc.view addSubview:menuView];

        g_espHostWindow = [[UIWindow alloc] initWithFrame:screen];
        g_espHostWindow.rootViewController = vc;
        g_espHostWindow.backgroundColor = [UIColor clearColor];
        g_espHostWindow.windowLevel = UIWindowLevelNormal - 1;
        g_espHostWindow.alpha = 0.0;
        // hidden=NO is what keeps the window and its ESP_View alive so the
        // GCD timer in ESP_View fires. makeKeyAndVisible is NOT needed: the
        // timer is a dispatch_source on the main queue, not a UIWindow
        // event, so it runs regardless of key status. Removing it avoids a
        // transparent key window competing with MenuView for key focus,
        // which is what the earlier comment was trying to work around.
        g_espHostWindow.hidden = NO; // must be in hierarchy for timer/views
        g_espHostWindow.userInteractionEnabled = YES;
        // [g_espHostWindow makeKeyAndVisible];  ← removed (watchdog/thermal)

        NSLog(@"[ESPHost] offscreen ESP_View host started (draw via SpringBoard only)");
    });
    return 0;
}

int StartDirectOverlay(void) {
    return StartESPHost();
}
