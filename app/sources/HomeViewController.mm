#import "HomeViewController.h"
#import "HUDHelper.h"
#import "rootless.h"
#import "pid.h"
#import "ESPPrefs.h"
#import "esp.h"
#import "GameOffsets.h"
#import "roothide/varCleanController.h"
#import "AppSettingsViewController.h"
#import "../KernelBoot.h"

// NOTE: MDTheme.h is deliberately NOT imported. The previous build still
// called MDThemeLoadFromPrefs() in viewDidLoad, and that function rewrote
// the window appearance with values from prefs. When the user's stored
// theme was light, it overrode every local colour set by applyTheme, which
// is why the screen stayed white no matter what palette this file used.
// Everything below uses a local palette and never touches prefs.

static HomeViewController *g_activeLogVC = nil;
static void HomeVCBootLogSink(NSString *line);

#import <QuartzCore/QuartzCore.h>
#import <SafariServices/SafariServices.h>

static const CGFloat kMenuButtonSize = 56.0f;

#pragma mark - VN TOOL dark navy theme (GitHub-style)
static UIColor *VNBg(void)     { return [UIColor colorWithRed:0.043 green:0.059 blue:0.078 alpha:1.0]; } // #0B0F14
static UIColor *VNCard(void)   { return [UIColor colorWithRed:0.086 green:0.106 blue:0.133 alpha:1.0]; } // #161B22
static UIColor *VNLine(void)   { return [UIColor colorWithRed:0.188 green:0.212 blue:0.239 alpha:1.0]; } // #30363D
static UIColor *VNText(void)   { return [UIColor colorWithRed:0.902 green:0.929 blue:0.953 alpha:1.0]; } // #E6EDF3
static UIColor *VNMuted(void)  { return [UIColor colorWithRed:0.545 green:0.580 blue:0.620 alpha:1.0]; } // #8B949E
static UIColor *VNAccent(void) { return [UIColor colorWithRed:0.247 green:0.725 blue:0.314 alpha:1.0]; } // #3FB950
static UIColor *VNBlue(void)   { return [UIColor colorWithRed:0.345 green:0.651 blue:1.000 alpha:1.0]; } // #58A6FF
static UIColor *VNOrange(void) { return [UIColor colorWithRed:0.941 green:0.533 blue:0.243 alpha:1.0]; } // #F0883E
static UIColor *VNRed(void)    { return [UIColor colorWithRed:0.973 green:0.318 blue:0.286 alpha:1.0]; } // #F85149
static UIColor *VNPanel2(void) { return [UIColor colorWithRed:0.129 green:0.149 blue:0.176 alpha:1.0]; } // #21262D

static UIView *VNMakeCard(void) {
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = VNCard();
    v.layer.cornerRadius = 14.0f;
    v.layer.borderWidth = 1.0f;
    v.layer.borderColor = VNLine().CGColor;
    return v;
}

static UIFont *VNFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

@interface HomeViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UILabel *titleLabel;

@property (nonatomic, strong) UIView *controlCard;
@property (nonatomic, strong) UIImageView *controlIconView;
@property (nonatomic, strong) UILabel *controlTitleLabel;
@property (nonatomic, strong) UILabel *controlSubtitleLabel;
@property (nonatomic, strong) UIButton *startButton;

@property (nonatomic, strong) UIView *togglesCard;
@property (nonatomic, strong) UILabel *aimbotLabel;
@property (nonatomic, strong) UISwitch *aimbotSwitch;
@property (nonatomic, strong) UILabel *espLabel;
@property (nonatomic, strong) UISwitch *espSwitch;
@property (nonatomic, strong) UILabel *camLabel;
@property (nonatomic, strong) UISwitch *camSwitch;
@property (nonatomic, strong) UISlider *camSlider;
@property (nonatomic, strong) UILabel *camValueLabel;

@property (nonatomic, strong) UIView *aimCard;
@property (nonatomic, strong) UILabel *fovLabel;
@property (nonatomic, strong) UISlider *fovSlider;
@property (nonatomic, strong) UILabel *fovValueLabel;
@property (nonatomic, strong) UILabel *triggerLabel;
@property (nonatomic, strong) UISegmentedControl *triggerSegment;
@property (nonatomic, strong) UILabel *aimPosLabel;
@property (nonatomic, strong) UISegmentedControl *aimPosSegment;
@property (nonatomic, strong) UILabel *aimBehindWallLabel;
@property (nonatomic, strong) UISwitch *aimBehindWallSwitch;

@property (nonatomic, strong) UILabel *versionSectionLabel;
@property (nonatomic, strong) UIButton *ffMaxCard;
@property (nonatomic, strong) UIButton *ffCard;
@property (nonatomic, strong) UIImageView *ffMaxIconView;
@property (nonatomic, strong) UIImageView *ffIconView;
@property (nonatomic, strong) UILabel *ffMaxNameLabel;
@property (nonatomic, strong) UILabel *ffNameLabel;

@property (nonatomic, strong) UIView *statusCard;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *openGameButton;

@property (nonatomic, strong) UIView *licenseCard;
@property (nonatomic, strong) UILabel *licenseTitleLabel;
@property (nonatomic, strong) UILabel *licenseValueLabel;

@property (nonatomic, strong) UIView *authCard;
@property (nonatomic, strong) UILabel *authTitleLabel;
@property (nonatomic, strong) UILabel *authValueLabel;

@property (nonatomic, strong) UIView *supportCard;
@property (nonatomic, strong) UILabel *supportTitleLabel;
@property (nonatomic, strong) UILabel *supportSubtitleLabel;
@property (nonatomic, strong) UIButton *joinButton;

@property (nonatomic, strong) UIView *extraCard;
@property (nonatomic, strong) UILabel *autoCleanLabel;
@property (nonatomic, strong) UISwitch *autoCleanSwitch;
@property (nonatomic, strong) UILabel *authorizationLabel;
@property (nonatomic, strong) UIButton *authorizationButton;
@property (nonatomic, strong) UIButton *settingsBtn;
@property (nonatomic, strong) UIView *logCard;
@property (nonatomic, strong) UITextView *logTextView;
- (void)appendBootLog:(NSString *)line;
@property (nonatomic, strong) UIButton *trashBtn;

@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) NSInteger gameMissingStreak;
@property (nonatomic, assign) CFTimeInterval pendingHUDEnableUntil;
@property (nonatomic, assign) NSInteger hudRequestSerial;
@end

@implementation HomeViewController

#pragma mark - Lifecycle

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Intentionally no MDThemeLoadFromPrefs() here. It used to rewrite the
    // window appearance from prefs and undo every colour set below.
    [self buildUI];
    _gameMissingStreak = 0;
    _pendingHUDEnableUntil = 0;
    _hudRequestSerial = 0;

    GameOffsetsReload();
    [self updateVersionSelectionUI];
    [self updateAuthorizationPresentation];
    [self refreshHUDState];
    [self applyTheme];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appBecameActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    [self startPollingGameState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Re-assert the dark theme every time we come back from the game.
    [self applyTheme];
    // Dark the surrounding chrome if we are inside a nav/tab controller.
    if (self.navigationController) {
        self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
        self.navigationController.navigationBar.translucent = NO;
        self.navigationController.navigationBar.barTintColor = VNBg();
        self.navigationController.navigationBar.tintColor = VNText();
        self.navigationController.view.backgroundColor = VNBg();
    }
    if (self.tabBarController) {
        self.tabBarController.tabBar.barStyle = UIBarStyleBlack;
        self.tabBarController.tabBar.translucent = NO;
        self.tabBarController.tabBar.barTintColor = VNCard();
        self.tabBarController.tabBar.tintColor = VNAccent();
        self.tabBarController.tabBar.unselectedItemTintColor = VNMuted();
        self.tabBarController.view.backgroundColor = VNBg();
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_pollTimer invalidate];
}

#pragma mark - Helpers

- (UIColor *)cardBackground { return VNCard(); }
- (UIColor *)accentGreen { return VNAccent(); }
- (UIColor *)accentBlue { return VNBlue(); }
- (UIColor *)accentOrange { return VNOrange(); }

- (void)openSettings {
    AppSettingsViewController *vc = [[AppSettingsViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)openVarClean {
    varCleanController *vc = [varCleanController sharedInstance];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

// Close button. The most reliable way to hide the config screen while
// keeping the process alive is to bring Free Fire to the foreground —
// iOS backgrounds this app automatically, KeepAlive audio prevents
// suspension, and the offscreen ESP_View timer keeps mirroring to
// SpringBoard. If the game is not installed / scheme does not resolve,
// fall back to the private suspend selector, and if that is not present
// either, exit(0) so at least the app disappears.
- (void)closeAppTapped:(id)sender {
    (void)sender;
    UIApplication *app = [UIApplication sharedApplication];

    // 1) Bring Free Fire to front (best path: game gets focus, we background).
    NSString *bundleId = GameTargetIsMax() ? @"com.dts.freefiremax" : @"vn.vng.freefireth";
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", bundleId]];
    if ([app canOpenURL:url]) {
        [app openURL:url options:@{} completionHandler:nil];
        return;
    }
    NSArray<NSString *> *fallbacks = GameTargetIsMax()
        ? @[ @"freefiremax://", @"ffmax://" ]
        : @[ @"freefireth://", @"freefire://" ];
    for (NSString *scheme in fallbacks) {
        NSURL *u = [NSURL URLWithString:scheme];
        if ([app canOpenURL:u]) {
            [app openURL:u options:@{} completionHandler:nil];
            return;
        }
    }

    // 2) Private suspend selector (backgrounds the app directly).
    SEL sel = NSSelectorFromString(@"suspend");
    if ([app respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [app performSelector:sel];
#pragma clang diagnostic pop
        return;
    }

    // 3) Last resort — terminate. The user can relaunch.
    exit(0);
}

- (void)applyTheme {
    self.view.backgroundColor = VNBg();

    _titleLabel.textColor = VNText();
    _titleLabel.font = VNFont(30, UIFontWeightBold);

    _controlCard.backgroundColor = VNCard();
    _controlCard.layer.borderColor = VNLine().CGColor;
    _controlTitleLabel.textColor = VNText();
    _controlSubtitleLabel.textColor = VNMuted();
    _startButton.backgroundColor = VNAccent();
    [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    _togglesCard.backgroundColor = VNCard();
    _togglesCard.layer.borderColor = VNLine().CGColor;
    _aimbotLabel.textColor = VNText();
    _aimbotSwitch.onTintColor = VNAccent();
    _espLabel.textColor = VNText();
    _espSwitch.onTintColor = VNAccent();
    _camLabel.textColor = VNText();
    _camSwitch.onTintColor = VNAccent();
    _camSlider.minimumTrackTintColor = VNAccent();
    _camValueLabel.textColor = VNMuted();

    _aimCard.backgroundColor = VNCard();
    _aimCard.layer.borderColor = VNLine().CGColor;
    _fovLabel.textColor = VNText();
    _fovSlider.minimumTrackTintColor = VNAccent();
    _fovValueLabel.textColor = VNMuted();
    _triggerLabel.textColor = VNText();
    _triggerSegment.selectedSegmentTintColor = VNAccent();
    _aimPosLabel.textColor = VNText();
    _aimPosSegment.selectedSegmentTintColor = VNAccent();
    _aimBehindWallLabel.textColor = VNText();
    _aimBehindWallSwitch.onTintColor = VNAccent();

    _versionSectionLabel.textColor = VNMuted();
    _ffMaxCard.backgroundColor = VNCard();
    _ffCard.backgroundColor = VNCard();
    _ffMaxNameLabel.textColor = VNText();
    _ffNameLabel.textColor = VNText();

    _statusCard.backgroundColor = VNCard();
    _statusCard.layer.borderColor = VNLine().CGColor;
    _statusLabel.textColor = VNText();
    _openGameButton.backgroundColor = VNOrange();
    [_openGameButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    _licenseCard.backgroundColor = VNCard();
    _licenseCard.layer.borderColor = VNLine().CGColor;
    _authCard.backgroundColor = VNCard();
    _authCard.layer.borderColor = VNLine().CGColor;
    _licenseTitleLabel.textColor = VNMuted();
    _licenseValueLabel.textColor = VNText();
    _authTitleLabel.textColor = VNMuted();
    _authValueLabel.textColor = VNAccent();

    _supportCard.backgroundColor = VNCard();
    _supportCard.layer.borderColor = VNLine().CGColor;
    _supportTitleLabel.textColor = VNText();
    _supportSubtitleLabel.textColor = VNMuted();
    _joinButton.backgroundColor = VNBlue();
    [_joinButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    _extraCard.backgroundColor = VNCard();
    _extraCard.layer.borderColor = VNLine().CGColor;
    _autoCleanLabel.textColor = VNText();
    _autoCleanSwitch.onTintColor = VNAccent();
    _authorizationLabel.textColor = VNText();
    [_authorizationButton setTitleColor:VNAccent() forState:UIControlStateNormal];

    _logCard.backgroundColor = VNCard();
    _logCard.layer.borderColor = VNLine().CGColor;

    _settingsBtn.backgroundColor = VNPanel2();
    _settingsBtn.layer.borderColor = VNLine().CGColor;
    _settingsBtn.tintColor = VNText();
    _trashBtn.backgroundColor = VNPanel2();
    _trashBtn.layer.borderColor = VNLine().CGColor;
    _trashBtn.tintColor = VNText();
    _closeBtn.backgroundColor = VNRed();
    _closeBtn.layer.borderColor = VNRed().CGColor;

    [self updateVersionSelectionUI];
    [self updateAuthorizationPresentation];
    [self refreshHUDState];
}

- (UIImage *)imageNamedWebPOrPNG:(NSString *)baseName {
    UIImage *img = [UIImage imageNamed:baseName];
    if (img) return img;
    NSString *path = [[NSBundle mainBundle] pathForResource:baseName ofType:@"webp"];
    if (path.length) {
        img = [UIImage imageWithContentsOfFile:path];
        if (img) return img;
    }
    path = [[NSBundle mainBundle] pathForResource:baseName ofType:@"png"];
    if (path.length) {
        img = [UIImage imageWithContentsOfFile:path];
    }
    return img;
}

- (UIView *)makeCard {
    return VNMakeCard();
}

- (UIButton *)makeIconButton:(NSString *)systemName {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = VNPanel2();
    b.layer.cornerRadius = 10.0f;
    b.layer.borderWidth = 1.0f;
    b.layer.borderColor = VNLine().CGColor;
    b.tintColor = VNText();
    UIImage *img = [UIImage systemImageNamed:systemName];
    if (img) [b setImage:img forState:UIControlStateNormal];
    return b;
}

// Standalone close button: text "✕" on a red background so it is clearly
// visible against the dark cards and cannot be confused with the settings
// or trash icon buttons.
- (UIButton *)makeCloseButton {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = VNRed();
    b.layer.cornerRadius = 10.0f;
    b.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    [b setTitle:@"✕" forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    return b;
}

- (UIButton *)makeVersionCardCapturingIcon:(UIImageView * __strong *)outIcon
                                 nameLabel:(UILabel * __strong *)outName {
    UIButton *card = [UIButton buttonWithType:UIButtonTypeCustom];
    card.backgroundColor = VNCard();
    card.layer.cornerRadius = 14.0f;
    card.clipsToBounds = YES;
    card.layer.borderWidth = 2.0f;
    card.layer.borderColor = [UIColor clearColor].CGColor;
    card.adjustsImageWhenHighlighted = NO;

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
    icon.contentMode = UIViewContentModeScaleAspectFill;
    icon.clipsToBounds = YES;
    icon.layer.cornerRadius = 10.0f;
    icon.userInteractionEnabled = NO;
    [card addSubview:icon];

    UILabel *name = [[UILabel alloc] initWithFrame:CGRectZero];
    name.font = VNFont(13, UIFontWeightSemibold);
    name.textColor = VNText();
    name.textAlignment = NSTextAlignmentCenter;
    name.userInteractionEnabled = NO;
    [card addSubview:name];

    if (outIcon) *outIcon = icon;
    if (outName) *outName = name;
    return card;
}

#pragma mark - Authorization

- (void)beginAuthorization {
    [self updateAuthorizationPresentation];
    [self refreshHUDState];
}

- (void)retryAuthorization:(id)sender {
    (void)sender;
    [self beginAuthorization];
}

- (void)revokeAuthorization {
    SetHUDEnabled(NO);
    [self updateAuthorizationPresentation];
    [self refreshHUDState];
}

- (void)updateAuthorizationPresentation {
    if (!self.isViewLoaded) return;
    _authorizationLabel.text = @"No key required";
    [_authorizationButton setTitle:@"Unlocked" forState:UIControlStateNormal];
    _authorizationButton.enabled = NO;
    _licenseValueLabel.text = @"Unlimited";
    _authValueLabel.text = @"Hoạt động";
    _authValueLabel.textColor = VNAccent();
    _authorizationLabel.textColor = VNText();
    _autoCleanSwitch.enabled = YES;
    _autoCleanLabel.alpha = 1.0;
    _startButton.alpha = 1.0;
}

#pragma mark - UI

- (void)buildUI {
    self.view.backgroundColor = VNBg();

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.backgroundColor = VNBg();
    [self.view addSubview:_scrollView];

    _contentView = [[UIView alloc] initWithFrame:CGRectZero];
    _contentView.backgroundColor = VNBg();
    [_scrollView addSubview:_contentView];

    // Close button on the far left. Text-based (✕) rather than SF Symbol
    // so it cannot silently render as an empty button on iOS versions
    // where "xmark" is missing.
    _closeBtn = [self makeCloseButton];
    [_closeBtn addTarget:self action:@selector(closeAppTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_closeBtn];

    _settingsBtn = [self makeIconButton:@"gearshape.fill"];
    [_settingsBtn addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    _trashBtn = [self makeIconButton:@"trash.fill"];
    [_trashBtn addTarget:self action:@selector(openVarClean) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_settingsBtn];
    [self.view addSubview:_trashBtn];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.text = @"VN TOOL";
    _titleLabel.font = VNFont(30, UIFontWeightBold);
    _titleLabel.textColor = VNText();
    [_contentView addSubview:_titleLabel];

    // Control card
    _controlCard = [self makeCard];
    [_contentView addSubview:_controlCard];

    _controlIconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _controlIconView.contentMode = UIViewContentModeScaleAspectFill;
    _controlIconView.clipsToBounds = YES;
    _controlIconView.layer.cornerRadius = 12.0f;
    _controlIconView.image = [self imageNamedWebPOrPNG:@"ff"] ?: [UIImage imageNamed:@"logo"];
    _controlIconView.backgroundColor = VNPanel2();
    [_controlCard addSubview:_controlIconView];

    _controlTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _controlTitleLabel.text = @"Điều khiển HUD";
    _controlTitleLabel.font = VNFont(16, UIFontWeightSemibold);
    _controlTitleLabel.textColor = VNText();
    [_controlCard addSubview:_controlTitleLabel];

    _controlSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _controlSubtitleLabel.text = @"Nhấn Bắt đầu khi game đã mở";
    _controlSubtitleLabel.font = VNFont(12, UIFontWeightRegular);
    _controlSubtitleLabel.textColor = VNMuted();
    _controlSubtitleLabel.numberOfLines = 2;
    [_controlCard addSubview:_controlSubtitleLabel];

    _startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _startButton.backgroundColor = VNAccent();
    _startButton.layer.cornerRadius = 16.0f;
    _startButton.titleLabel.font = VNFont(14, UIFontWeightBold);
    [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
    [_startButton addTarget:self action:@selector(startButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_controlCard addSubview:_startButton];

    // Toggles card
    _togglesCard = [self makeCard];
    [_contentView addSubview:_togglesCard];

    _aimbotLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimbotLabel.text = @"Aimbot";
    _aimbotLabel.font = VNFont(15, UIFontWeightSemibold);
    _aimbotLabel.textColor = VNText();
    [_togglesCard addSubview:_aimbotLabel];

    _aimbotSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _aimbotSwitch.onTintColor = VNAccent();
    _aimbotSwitch.on = ESPPrefsBool(@"Aimbot", NO);
    [_aimbotSwitch addTarget:self action:@selector(aimbotSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_aimbotSwitch];

    _espLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espLabel.text = @"ESP";
    _espLabel.font = VNFont(15, UIFontWeightSemibold);
    _espLabel.textColor = VNText();
    [_togglesCard addSubview:_espLabel];

    _espSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espSwitch.onTintColor = VNAccent();
    _espSwitch.on = ESPPrefsBool(@"EnableESP", YES);
    [_espSwitch addTarget:self action:@selector(espSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_espSwitch];

    _camLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camLabel.text = @"Camera Xa (CamPC)";
    _camLabel.font = VNFont(15, UIFontWeightSemibold);
    _camLabel.textColor = VNText();
    [_togglesCard addSubview:_camLabel];

    _camSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _camSwitch.onTintColor = VNAccent();
    _camSwitch.on = ESPPrefsBool(@"CamPC", NO);
    [_camSwitch addTarget:self action:@selector(camSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_camSwitch];

    _camSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _camSlider.minimumValue = 0.0f;
    _camSlider.maximumValue = 150.0f;
    _camSlider.value = ESPPrefsFloat(@"CamPCValue", 30.0f);
    _camSlider.minimumTrackTintColor = VNAccent();
    [_camSlider addTarget:self action:@selector(camSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_camSlider];

    _camValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camValueLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _camValueLabel.textColor = VNMuted();
    _camValueLabel.text = [NSString stringWithFormat:@"%.0f", _camSlider.value];
    [_togglesCard addSubview:_camValueLabel];

    // Aimbot card
    _aimCard = [self makeCard];
    [_contentView addSubview:_aimCard];

    _fovLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _fovLabel.text = @"FOV size";
    _fovLabel.font = VNFont(14, UIFontWeightSemibold);
    _fovLabel.textColor = VNText();
    [_aimCard addSubview:_fovLabel];

    _fovSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _fovSlider.minimumValue = 30.0f;
    _fovSlider.maximumValue = 360.0f;
    _fovSlider.value = ESPPrefsFloat(@"Fov", 150.0f);
    _fovSlider.minimumTrackTintColor = VNAccent();
    [_fovSlider addTarget:self action:@selector(fovSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_fovSlider];

    _fovValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _fovValueLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _fovValueLabel.textColor = VNMuted();
    _fovValueLabel.textAlignment = NSTextAlignmentRight;
    _fovValueLabel.text = [NSString stringWithFormat:@"%.0f", _fovSlider.value];
    [_aimCard addSubview:_fovValueLabel];

    _triggerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _triggerLabel.text = @"Trigger";
    _triggerLabel.font = VNFont(14, UIFontWeightSemibold);
    _triggerLabel.textColor = VNText();
    [_aimCard addSubview:_triggerLabel];

    _triggerSegment = [[UISegmentedControl alloc] initWithItems:@[@"Auto", @"Fire", @"Scope", @"Both"]];
    {
        NSInteger idx = (NSInteger)ESPPrefsFloat(@"TriggerMode", 0.0f);
        if (idx < 0) idx = 0;
        if (idx > 3) idx = 3;
        _triggerSegment.selectedSegmentIndex = idx;
    }
    if (@available(iOS 13.0, *)) {
        _triggerSegment.selectedSegmentTintColor = VNAccent();
        _triggerSegment.backgroundColor = VNPanel2();
    }
    [_triggerSegment addTarget:self action:@selector(triggerSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_triggerSegment];

    _aimPosLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimPosLabel.text = @"Aim Position";
    _aimPosLabel.font = VNFont(14, UIFontWeightSemibold);
    _aimPosLabel.textColor = VNText();
    [_aimCard addSubview:_aimPosLabel];

    _aimPosSegment = [[UISegmentedControl alloc] initWithItems:@[@"Đầu", @"Cổ", @"Thân"]];
    {
        NSInteger idx = (NSInteger)ESPPrefsFloat(@"AimPos", 0.0f);
        if (idx < 0) idx = 0;
        if (idx > 2) idx = 2;
        _aimPosSegment.selectedSegmentIndex = idx;
    }
    if (@available(iOS 13.0, *)) {
        _aimPosSegment.selectedSegmentTintColor = VNAccent();
        _aimPosSegment.backgroundColor = VNPanel2();
    }
    [_aimPosSegment addTarget:self action:@selector(aimPosSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimPosSegment];

    _aimBehindWallLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimBehindWallLabel.text = @"Aim Behind Wall";
    _aimBehindWallLabel.font = VNFont(14, UIFontWeightSemibold);
    _aimBehindWallLabel.textColor = VNText();
    [_aimCard addSubview:_aimBehindWallLabel];

    _aimBehindWallSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _aimBehindWallSwitch.onTintColor = VNAccent();
    _aimBehindWallSwitch.on = ESPPrefsBool(@"AimBehindWall", NO);
    [_aimBehindWallSwitch addTarget:self action:@selector(aimBehindWallSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimBehindWallSwitch];

    // Log card
    _logCard = [self makeCard];
    [_contentView addSubview:_logCard];

    _logTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    _logTextView.editable = NO;
    _logTextView.scrollEnabled = YES;
    _logTextView.showsHorizontalScrollIndicator = NO;
    _logTextView.backgroundColor = [UIColor colorWithRed:0.02 green:0.04 blue:0.03 alpha:1.0];
    _logTextView.layer.cornerRadius = 10.0f;
    _logTextView.layer.borderWidth = 1.0f;
    _logTextView.layer.borderColor = VNLine().CGColor;
    _logTextView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _logTextView.textColor = [UIColor colorWithRed:0.55 green:0.95 blue:0.6 alpha:1.0];
    _logTextView.text = @"[VN TOOL] ready.\nPress Bắt đầu to boot kernel.";
    [_logCard addSubview:_logTextView];

    // Version section
    _versionSectionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _versionSectionLabel.text = @"Lựa chọn phiên bản:";
    _versionSectionLabel.font = VNFont(13, UIFontWeightMedium);
    _versionSectionLabel.textColor = VNMuted();
    [_contentView addSubview:_versionSectionLabel];

    UIImageView *ffMaxIcon = nil;
    UILabel *ffMaxName = nil;
    _ffMaxCard = [self makeVersionCardCapturingIcon:&ffMaxIcon nameLabel:&ffMaxName];
    _ffMaxIconView = ffMaxIcon;
    _ffMaxNameLabel = ffMaxName;
    _ffMaxIconView.image = [self imageNamedWebPOrPNG:@"ffmax"] ?: [UIImage imageNamed:@"logo"];
    _ffMaxNameLabel.text = @"Free Fire MAX";
    _ffMaxCard.tag = 2;
    [_ffMaxCard addTarget:self action:@selector(versionCardTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_ffMaxCard];

    UIImageView *ffIcon = nil;
    UILabel *ffName = nil;
    _ffCard = [self makeVersionCardCapturingIcon:&ffIcon nameLabel:&ffName];
    _ffIconView = ffIcon;
    _ffNameLabel = ffName;
    _ffIconView.image = [self imageNamedWebPOrPNG:@"ff"] ?: [UIImage imageNamed:@"logo"];
    _ffNameLabel.text = @"Free Fire";
    _ffCard.tag = 1;
    [_ffCard addTarget:self action:@selector(versionCardTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_ffCard];

    // Status card
    _statusCard = [self makeCard];
    [_contentView addSubview:_statusCard];

    _statusDot = [[UIView alloc] initWithFrame:CGRectZero];
    _statusDot.layer.cornerRadius = 5.0f;
    _statusDot.backgroundColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    [_statusCard addSubview:_statusDot];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.font = VNFont(14, UIFontWeightMedium);
    _statusLabel.textColor = VNText();
    _statusLabel.text = @"Trạng thái · Game chưa chạy";
    [_statusCard addSubview:_statusLabel];

    _openGameButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _openGameButton.backgroundColor = VNOrange();
    _openGameButton.layer.cornerRadius = 14.0f;
    _openGameButton.titleLabel.font = VNFont(13, UIFontWeightBold);
    [_openGameButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_openGameButton setTitle:@"Vào Game" forState:UIControlStateNormal];
    [_openGameButton addTarget:self action:@selector(openGameTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_statusCard addSubview:_openGameButton];

    // License + auth
    _licenseCard = [self makeCard];
    [_contentView addSubview:_licenseCard];
    _licenseTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _licenseTitleLabel.text = @"Giấy phép";
    _licenseTitleLabel.font = VNFont(12, UIFontWeightMedium);
    _licenseTitleLabel.textColor = VNMuted();
    [_licenseCard addSubview:_licenseTitleLabel];
    _licenseValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _licenseValueLabel.font = VNFont(15, UIFontWeightSemibold);
    _licenseValueLabel.textColor = VNText();
    _licenseValueLabel.numberOfLines = 3;
    _licenseValueLabel.text = @"—";
    [_licenseCard addSubview:_licenseValueLabel];

    _authCard = [self makeCard];
    [_contentView addSubview:_authCard];
    _authTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authTitleLabel.text = @"Trạng thái";
    _authTitleLabel.font = VNFont(12, UIFontWeightMedium);
    _authTitleLabel.textColor = VNMuted();
    [_authCard addSubview:_authTitleLabel];
    _authValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authValueLabel.font = VNFont(16, UIFontWeightSemibold);
    _authValueLabel.textColor = VNAccent();
    _authValueLabel.numberOfLines = 2;
    _authValueLabel.text = @"—";
    [_authCard addSubview:_authValueLabel];

    // Support
    _supportCard = [self makeCard];
    [_contentView addSubview:_supportCard];
    _supportTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportTitleLabel.text = @"Liên hệ hỗ trợ";
    _supportTitleLabel.font = VNFont(15, UIFontWeightSemibold);
    _supportTitleLabel.textColor = VNText();
    [_supportCard addSubview:_supportTitleLabel];
    _supportSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportSubtitleLabel.text = @"Nhấn Join để nhận hỗ trợ";
    _supportSubtitleLabel.font = VNFont(12, UIFontWeightRegular);
    _supportSubtitleLabel.textColor = VNMuted();
    [_supportCard addSubview:_supportSubtitleLabel];
    _joinButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _joinButton.backgroundColor = VNBlue();
    _joinButton.layer.cornerRadius = 14.0f;
    _joinButton.titleLabel.font = VNFont(13, UIFontWeightBold);
    [_joinButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_joinButton setTitle:@"Join" forState:UIControlStateNormal];
    [_joinButton addTarget:self action:@selector(joinSupportTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_supportCard addSubview:_joinButton];

    // Extra
    _extraCard = [self makeCard];
    [_contentView addSubview:_extraCard];

    _autoCleanLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _autoCleanLabel.text = @"VarClean before HUD";
    _autoCleanLabel.font = VNFont(14, UIFontWeightMedium);
    _autoCleanLabel.textColor = VNText();
    [_extraCard addSubview:_autoCleanLabel];

    _autoCleanSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _autoCleanSwitch.onTintColor = VNAccent();
    _autoCleanSwitch.on = ESPPrefsBool(@"AutoVarCleanBeforeHUD", NO);
    [_autoCleanSwitch addTarget:self action:@selector(autoCleanSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_extraCard addSubview:_autoCleanSwitch];

    _authorizationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authorizationLabel.font = VNFont(12, UIFontWeightMedium);
    _authorizationLabel.textColor = VNText();
    _authorizationLabel.textAlignment = NSTextAlignmentLeft;
    [_extraCard addSubview:_authorizationLabel];

    _authorizationButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _authorizationButton.titleLabel.font = VNFont(12, UIFontWeightSemibold);
    [_authorizationButton setTitleColor:VNAccent() forState:UIControlStateNormal];
    [_authorizationButton addTarget:self action:@selector(retryAuthorization:) forControlEvents:UIControlEventTouchUpInside];
    [_extraCard addSubview:_authorizationButton];

    [self applyTheme];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    _scrollView.frame = self.view.bounds;

    CGFloat gear = 36.0f;
    // Row 1: [X close] ... [trash] [gear]
    _closeBtn.frame = CGRectMake(insets.left + 16, insets.top + 8, gear, gear);
    _settingsBtn.frame = CGRectMake(width - insets.right - 16 - gear, insets.top + 8, gear, gear);
    _trashBtn.frame = CGRectMake(CGRectGetMinX(_settingsBtn.frame) - 10 - gear, insets.top + 8, gear, gear);

    CGFloat contentW = width;
    CGFloat xPad = 16.0f;
    CGFloat cardW = contentW - xPad * 2.0f;
    CGFloat y = insets.top + 52.0f;

    // Title sits between the close button and the two icon buttons.
    CGFloat titleX = CGRectGetMaxX(_closeBtn.frame) + 12;
    CGFloat titleRight = CGRectGetMinX(_trashBtn.frame) - 12;
    CGFloat titleW = titleRight - titleX;
    if (titleW < 80) titleW = 80;
    _titleLabel.frame = CGRectMake(titleX, y, titleW, 40);
    y = CGRectGetMaxY(_titleLabel.frame) + 14;

    CGFloat controlH = 86.0f;
    _controlCard.frame = CGRectMake(xPad, y, cardW, controlH);
    CGFloat iconSize = MIN(kMenuButtonSize, MIN(cardW * 0.42f, controlH * 0.85f));
    iconSize = MAX(48.0f, iconSize);
    _controlIconView.frame = CGRectMake(14, (controlH - iconSize) * 0.5f, iconSize, iconSize);
    _startButton.frame = CGRectMake(cardW - 108, 26, 94, 34);
    CGFloat textX = 80;
    CGFloat textW = cardW - 108 - textX - 8;
    _controlTitleLabel.frame = CGRectMake(textX, 20, textW, 22);
    _controlSubtitleLabel.frame = CGRectMake(textX, 44, textW, 28);
    y = CGRectGetMaxY(_controlCard.frame) + 12;

    CGFloat togglesH = 176.0f;
    _togglesCard.frame = CGRectMake(xPad, y, cardW, togglesH);
    _aimbotLabel.frame = CGRectMake(16, 14, 200, 24);
    _aimbotSwitch.frame = CGRectMake(cardW - 68, 10, 51, 31);
    _espLabel.frame = CGRectMake(16, 54, 200, 24);
    _espSwitch.frame = CGRectMake(cardW - 68, 50, 51, 31);
    _camLabel.frame = CGRectMake(16, 94, 200, 24);
    _camSwitch.frame = CGRectMake(cardW - 68, 90, 51, 31);
    _camSlider.frame = CGRectMake(16, 128, cardW - 90, 30);
    _camValueLabel.frame = CGRectMake(cardW - 64, 130, 48, 24);
    y = CGRectGetMaxY(_togglesCard.frame) + 12;

    CGFloat aimH = 254.0f;
    _aimCard.frame = CGRectMake(xPad, y, cardW, aimH);
    _fovLabel.frame = CGRectMake(16, 14, 120, 20);
    _fovValueLabel.frame = CGRectMake(cardW - 64, 14, 48, 20);
    _fovSlider.frame = CGRectMake(16, 38, cardW - 32, 30);
    _triggerLabel.frame = CGRectMake(16, 78, 120, 20);
    _triggerSegment.frame = CGRectMake(16, 100, cardW - 32, 32);
    _aimPosLabel.frame = CGRectMake(16, 142, 120, 20);
    _aimPosSegment.frame = CGRectMake(16, 164, cardW - 32, 32);
    _aimBehindWallLabel.frame = CGRectMake(16, 214, 220, 24);
    _aimBehindWallSwitch.frame = CGRectMake(cardW - 68, 210, 51, 31);
    y = CGRectGetMaxY(_aimCard.frame) + 12;

    CGFloat logH = 210.0f;
    _logCard.frame = CGRectMake(xPad, y, cardW, logH);
    _logTextView.frame = CGRectMake(10, 8, cardW - 20, logH - 16);
    y = CGRectGetMaxY(_logCard.frame) + 16;

    _versionSectionLabel.frame = CGRectMake(xPad + 4, y, cardW - 8, 20);
    y = CGRectGetMaxY(_versionSectionLabel.frame) + 10;

    CGFloat gap = 12.0f;
    CGFloat versionW = (cardW - gap) * 0.5f;
    CGFloat versionH = 128.0f;
    _ffMaxCard.frame = CGRectMake(xPad, y, versionW, versionH);
    _ffCard.frame = CGRectMake(xPad + versionW + gap, y, versionW, versionH);

    CGFloat iconSide = 64.0f;
    _ffMaxIconView.frame = CGRectMake((versionW - iconSide) * 0.5f, 18, iconSide, iconSide);
    _ffIconView.frame = CGRectMake((versionW - iconSide) * 0.5f, 18, iconSide, iconSide);
    _ffMaxNameLabel.frame = CGRectMake(8, 90, versionW - 16, 24);
    _ffNameLabel.frame = CGRectMake(8, 90, versionW - 16, 24);
    y = CGRectGetMaxY(_ffMaxCard.frame) + 14;

    CGFloat statusH = 64.0f;
    _statusCard.frame = CGRectMake(xPad, y, cardW, statusH);
    _statusDot.frame = CGRectMake(16, 27, 10, 10);
    _openGameButton.frame = CGRectMake(cardW - 112, 15, 98, 34);
    _statusLabel.frame = CGRectMake(36, 18, cardW - 112 - 44, 28);
    y = CGRectGetMaxY(_statusCard.frame) + 12;

    CGFloat halfW = (cardW - gap) * 0.5f;
    CGFloat halfH = 92.0f;
    _licenseCard.frame = CGRectMake(xPad, y, halfW, halfH);
    _authCard.frame = CGRectMake(xPad + halfW + gap, y, halfW, halfH);
    _licenseTitleLabel.frame = CGRectMake(14, 12, halfW - 28, 18);
    _licenseValueLabel.frame = CGRectMake(14, 36, halfW - 28, 46);
    _authTitleLabel.frame = CGRectMake(14, 12, halfW - 28, 18);
    _authValueLabel.frame = CGRectMake(14, 40, halfW - 28, 36);
    y = CGRectGetMaxY(_licenseCard.frame) + 12;

    CGFloat supportH = 72.0f;
    _supportCard.frame = CGRectMake(xPad, y, cardW, supportH);
    _joinButton.frame = CGRectMake(cardW - 92, 19, 78, 34);
    _supportTitleLabel.frame = CGRectMake(16, 16, cardW - 120, 22);
    _supportSubtitleLabel.frame = CGRectMake(16, 40, cardW - 120, 18);
    y = CGRectGetMaxY(_supportCard.frame) + 12;

    CGFloat extraH = 96.0f;
    _extraCard.frame = CGRectMake(xPad, y, cardW, extraH);
    _autoCleanLabel.frame = CGRectMake(16, 16, cardW - 90, 22);
    CGSize sw = _autoCleanSwitch.intrinsicContentSize;
    _autoCleanSwitch.frame = CGRectMake(cardW - sw.width - 16, 14, sw.width, sw.height);
    _authorizationLabel.frame = CGRectMake(16, 52, cardW - 150, 28);
    _authorizationButton.frame = CGRectMake(cardW - 132, 52, 116, 28);
    y = CGRectGetMaxY(_extraCard.frame) + 24 + insets.bottom;

    _contentView.frame = CGRectMake(0, 0, contentW, MAX(y, height));
    _scrollView.contentSize = _contentView.bounds.size;
}

#pragma mark - Version selection

- (void)versionCardTapped:(UIButton *)sender {
    BOOL pickMax = (sender.tag == 2);
    NSString *gameId = pickMax ? @"ffmax" : @"ff";
    GameTargetSetSelectedId(gameId);
    [self updateVersionSelectionUI];
    [self refreshHUDState];
}

- (void)updateVersionSelectionUI {
    BOOL isMax = GameTargetIsMax();
    UIColor *selected = VNAccent();

    _ffMaxCard.layer.borderWidth = 2.0f;
    _ffCard.layer.borderWidth = 2.0f;
    _ffMaxCard.layer.borderColor = (isMax ? selected : VNLine()).CGColor;
    _ffCard.layer.borderColor = (!isMax ? selected : VNLine()).CGColor;
    _ffMaxCard.backgroundColor = isMax ? VNPanel2() : VNCard();
    _ffCard.backgroundColor = !isMax ? VNPanel2() : VNCard();

    UIImage *icon = [self imageNamedWebPOrPNG:isMax ? @"ffmax" : @"ff"];
    if (icon) {
        _controlIconView.image = icon;
    }
}

#pragma mark - App lifecycle

- (void)appBecameActive {
    GameOffsetsReload();
    [self applyTheme];
    [self updateVersionSelectionUI];
    [self refreshHUDState];
}

#pragma mark - HUD / game

- (BOOL)isGameRunning {
    return GameTargetIsRunning();
}

- (void)startPollingGameState {
    __weak __typeof(self) weakSelf = self;
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                   repeats:YES
                                                     block:^(NSTimer *timer) {
        [weakSelf refreshHUDState];
    }];
}

- (void)autoCleanSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBool(@"AutoVarCleanBeforeHUD", sender.on);
}

- (void)aimbotSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Aimbot", sender.on);
    ESPSyncFromPrefs();
}

- (void)espSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"EnableESP", sender.on);
    ESPSyncFromPrefs();
}

- (void)camSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"CamPC", sender.on);
    ESPSyncFromPrefs();
}

- (void)camSliderChanged:(UISlider *)sender {
    float v = sender.value;
    _camValueLabel.text = [NSString stringWithFormat:@"%.0f", v];
    ESPPrefsSetFloatLive(@"CamPCValue", v);
}

- (void)fovSliderChanged:(UISlider *)sender {
    float v = sender.value;
    _fovValueLabel.text = [NSString stringWithFormat:@"%.0f", v];
    ESPPrefsSetFloatLive(@"Fov", v);
}

// Trigger / AimPos write both key variants. ESPPrefs appends "_Lite" when
// the menu layout is Lite; if the layout is Pro it writes the plain key.
// The read path in esp.mm goes through the same ResolveKey, so a mismatch
// only happens when the layout changes between a write and a read, or when
// the value was written before a layout change. Writing both keys and
// syncing NSUserDefaults directly closes that gap.
- (void)triggerSegmentChanged:(UISegmentedControl *)sender {
    float v = (float)sender.selectedSegmentIndex;
    NSUserDefaults *std = [NSUserDefaults standardUserDefaults];
    [std setFloat:v forKey:@"TriggerMode"];
    [std setFloat:v forKey:@"TriggerMode_Lite"];
    [std synchronize];
    ESPPrefsSetFloat(@"TriggerMode", v);
    ESPSyncFromPrefs();
    NSLog(@"[VN] TriggerMode set to %.0f (both keys)", v);
}

- (void)aimPosSegmentChanged:(UISegmentedControl *)sender {
    float v = (float)sender.selectedSegmentIndex;
    NSUserDefaults *std = [NSUserDefaults standardUserDefaults];
    [std setFloat:v forKey:@"AimPos"];
    [std setFloat:v forKey:@"AimPos_Lite"];
    [std synchronize];
    ESPPrefsSetFloat(@"AimPos", v);
    ESPSyncFromPrefs();
    NSLog(@"[VN] AimPos set to %.0f (both keys)", v);
}

- (void)aimBehindWallSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"AimBehindWall", sender.on);
    ESPSyncFromPrefs();
}

- (void)startButtonTapped:(UIButton *)sender {
    (void)sender;
    BOOL hudOn = IsHUDEnabled();
    if (hudOn) {
        ++_hudRequestSerial;
        _pendingHUDEnableUntil = 0;
        SetHUDEnabled(NO);
        [self refreshHUDState];
        return;
    }

    NSInteger requestSerial = ++_hudRequestSerial;
    _startButton.enabled = NO;
    [self startHUDForRequest:requestSerial];
}

- (void)startHUDForRequest:(NSInteger)requestSerial {
    _pendingHUDEnableUntil = CACurrentMediaTime() + 2.5;
    GameOffsetsReload();
    BOOL autoClean = ESPPrefsBool(@"AutoVarCleanBeforeHUD", NO);
    if (!autoClean) {
        g_activeLogVC = self;
        kernelBootLog = HomeVCBootLogSink;
        kernelBootStart();
        self.startButton.enabled = YES;
        [self refreshHUDState];
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [[varCleanController sharedInstance] runVarCleanNowWithCompletion:^(BOOL authorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (requestSerial != self.hudRequestSerial || !authorized) {
                    self.pendingHUDEnableUntil = 0;
                    [self refreshHUDState];
                    return;
                }
                SetHUDEnabled(YES);
                self.startButton.enabled = YES;
                [self refreshHUDState];
            });
        }];
    });
}

- (void)openGameTapped:(id)sender {
    (void)sender;
    NSString *bundleId = GameTargetIsMax() ? @"com.dts.freefiremax" : @"vn.vng.freefireth";
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", bundleId]];
    UIApplication *app = [UIApplication sharedApplication];
    if ([app canOpenURL:url]) {
        [app openURL:url options:@{} completionHandler:nil];
        return;
    }
    NSArray<NSString *> *fallbacks = GameTargetIsMax()
        ? @[ @"freefiremax://", @"ffmax://" ]
        : @[ @"freefireth://", @"freefire://" ];
    for (NSString *scheme in fallbacks) {
        NSURL *u = [NSURL URLWithString:scheme];
        if ([app canOpenURL:u]) {
            [app openURL:u options:@{} completionHandler:nil];
            return;
        }
    }
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Không mở được game"
                                            message:@"Hãy mở Free Fire / Free Fire MAX thủ công, rồi quay lại nhấn Bắt đầu."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)joinSupportTapped:(id)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:@"https://t.me/"];
    if (!url) return;
    if (@available(iOS 9.0, *)) {
        SFSafariViewController *svc = [[SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:svc animated:YES completion:nil];
    } else {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

static void HomeVCBootLogSink(NSString *line) {
    dispatch_async(dispatch_get_main_queue(), ^{
        HomeViewController *vc = g_activeLogVC;
        if (!vc) return;
        [vc appendBootLog:line];
    });
}

- (void)appendBootLog:(NSString *)line {
    static NSMutableString *bootText;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ bootText = [NSMutableString new]; });
    [bootText appendFormat:@"%@\n", line];
    if (bootText.length > 8000) [bootText deleteCharactersInRange:NSMakeRange(0, bootText.length - 8000)];
    NSString *snap = [bootText copy];
    self.logTextView.text = snap;
    [self.logTextView scrollRangeToVisible:NSMakeRange(snap.length, 0)];
}

- (void)refreshHUDState {
    if (!self.isViewLoaded) return;
    GameOffsetsReload();

    BOOL gameIsRunning = [self isGameRunning];
    BOOL hudIsEnabled = IsHUDEnabled();
    _gameMissingStreak = gameIsRunning ? 0 : _gameMissingStreak + 1;
    BOOL gameIsAvailable = gameIsRunning || _gameMissingStreak < 8;

    if (gameIsRunning) {
        _statusDot.backgroundColor = VNAccent();
        NSString *name = GameTargetIsMax() ? @"Free Fire MAX" : @"Free Fire";
        _statusLabel.text = [NSString stringWithFormat:@"Trạng thái · %@ đang chạy", name];
    } else {
        _statusDot.backgroundColor = VNRed();
        _statusLabel.text = @"Trạng thái · Game chưa chạy";
    }

    if (!gameIsAvailable) {
        [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
        _startButton.enabled = YES;
        _startButton.alpha = 1.0;
        _controlSubtitleLabel.alpha = 1.0;
        _pendingHUDEnableUntil = 0;
        return;
    }

    _startButton.enabled = YES;
    _startButton.alpha = 1.0;
    _controlSubtitleLabel.alpha = 1.0;

    CFTimeInterval now = CACurrentMediaTime();
    BOOL isWithinEnableGracePeriod = _pendingHUDEnableUntil > 0 && now < _pendingHUDEnableUntil;
    if (!hudIsEnabled && isWithinEnableGracePeriod) {
        [_startButton setTitle:@"Đang bật…" forState:UIControlStateNormal];
        return;
    }

    if (hudIsEnabled) {
        _pendingHUDEnableUntil = 0;
        [_startButton setTitle:@"Tắt HUD" forState:UIControlStateNormal];
        _startButton.backgroundColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    } else {
        [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
        _startButton.backgroundColor = VNAccent();
    }
}

@end
