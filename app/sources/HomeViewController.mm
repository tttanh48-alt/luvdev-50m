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

static HomeViewController *g_activeLogVC = nil;
static void HomeVCBootLogSink(NSString *line);

#import <QuartzCore/QuartzCore.h>
#import <SafariServices/SafariServices.h>

static const CGFloat kMenuButtonSize = 56.0f;

#pragma mark - VN TOOL iOS-style theme

static UIColor *VNBg(void)        { return [UIColor colorWithRed:0.949 green:0.949 blue:0.969 alpha:1.0]; }
static UIColor *VNCard(void)      { return [UIColor whiteColor]; }
static UIColor *VNLine(void)      { return [UIColor colorWithWhite:0.78 alpha:0.45]; }
static UIColor *VNText(void)      { return [UIColor blackColor]; }
static UIColor *VNMuted(void)     { return [UIColor colorWithWhite:0.42 alpha:1.0]; }
static UIColor *VNAccent(void)    { return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0]; }
static UIColor *VNAccentDim(void) { return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:0.45]; }
static UIColor *VNRed(void)       { return [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0]; }
static UIColor *VNBlue(void)      { return VNAccent(); }
static UIColor *VNOrange(void)    { return VNAccent(); }

static UIFont *VNFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

static UILabel *VNMakeSectionHeader(NSString *text) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = [text uppercaseString];
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    l.textColor = [UIColor colorWithWhite:0.42 alpha:1.0];
    return l;
}

static UIView *VNMakeRowSeparator(void) {
    UIView *sep = [[UIView alloc] initWithFrame:CGRectZero];
    sep.backgroundColor = VNLine();
    return sep;
}

@interface HomeViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

// Control
@property (nonatomic, strong) UIView *controlCard;
@property (nonatomic, strong) UIImageView *controlIconView;
@property (nonatomic, strong) UILabel *controlTitleLabel;
@property (nonatomic, strong) UILabel *controlSubtitleLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *killAllButton;

// Toggles
@property (nonatomic, strong) UIView *togglesCard;
@property (nonatomic, strong) UILabel *aimbotLabel;
@property (nonatomic, strong) UISwitch *aimbotSwitch;
@property (nonatomic, strong) UILabel *silentAimLabel;
@property (nonatomic, strong) UISwitch *silentAimSwitch;
@property (nonatomic, strong) UILabel *espLabel;
@property (nonatomic, strong) UISwitch *espSwitch;
@property (nonatomic, strong) UILabel *camLabel;
@property (nonatomic, strong) UISwitch *camSwitch;
@property (nonatomic, strong) UISlider *camSlider;
@property (nonatomic, strong) UILabel *camValueLabel;
@property (nonatomic, strong) UILabel *camValueStaticLabel;

// ESP
@property (nonatomic, strong) UIView *espCard;
@property (nonatomic, strong) UILabel *espCardTitle;
@property (nonatomic, strong) UILabel *espBoxLabel;
@property (nonatomic, strong) UISwitch *espBoxSwitch;
@property (nonatomic, strong) UILabel *espLineLabel;
@property (nonatomic, strong) UISwitch *espLineSwitch;
@property (nonatomic, strong) UILabel *espBoneLabel;
@property (nonatomic, strong) UISwitch *espBoneSwitch;
@property (nonatomic, strong) UILabel *espHealthLabel;
@property (nonatomic, strong) UISwitch *espHealthSwitch;
@property (nonatomic, strong) UILabel *espCountLabel;
@property (nonatomic, strong) UISwitch *espCountSwitch;
@property (nonatomic, strong) UILabel *espDistanceLimitLabel;
@property (nonatomic, strong) UISlider *espDistanceLimitSlider;
@property (nonatomic, strong) UILabel *espDistanceLimitValueLabel;

// Aim
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

// Version
@property (nonatomic, strong) UILabel *versionSectionLabel;
@property (nonatomic, strong) UIButton *ffMaxCard;
@property (nonatomic, strong) UIButton *ffCard;
@property (nonatomic, strong) UIImageView *ffMaxIconView;
@property (nonatomic, strong) UIImageView *ffIconView;
@property (nonatomic, strong) UILabel *ffMaxNameLabel;
@property (nonatomic, strong) UILabel *ffNameLabel;

// Status
@property (nonatomic, strong) UIView *statusCard;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *openGameButton;

// Info
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

// Section headers
@property (nonatomic, strong) UILabel *secControl;
@property (nonatomic, strong) UILabel *secDraw;
@property (nonatomic, strong) UILabel *secAim;
@property (nonatomic, strong) UILabel *secCamera;
@property (nonatomic, strong) UILabel *secVersion;
@property (nonatomic, strong) UILabel *secStatus;
@property (nonatomic, strong) UILabel *secInfo;
@property (nonatomic, strong) UILabel *secExtra;
@property (nonatomic, strong) UILabel *secLog;
@end

@implementation HomeViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleDarkContent; }

- (void)viewDidLoad {
    [super viewDidLoad];
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
    [self applyTheme];
    if (self.navigationController) {
        self.navigationController.navigationBar.barStyle = UIBarStyleDefault;
        self.navigationController.navigationBar.translucent = NO;
        self.navigationController.navigationBar.barTintColor = VNBg();
        self.navigationController.navigationBar.tintColor = VNAccent();
        self.navigationController.view.backgroundColor = VNBg();
    }
    if (self.tabBarController) {
        self.tabBarController.tabBar.barStyle = UIBarStyleDefault;
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
    if (g_activeLogVC == self) g_activeLogVC = nil;
}

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

- (void)closeAppTapped:(id)sender {
    (void)sender;
    UIApplication *app = [UIApplication sharedApplication];
    NSString *bundleId = GameTargetIsMax() ? @"com.dts.freefiremax" : @"vn.vng.freefireth";
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", bundleId]];
    if ([app canOpenURL:url]) { [app openURL:url options:@{} completionHandler:nil]; return; }
    NSArray<NSString *> *fallbacks = GameTargetIsMax()
        ? @[ @"freefiremax://", @"ffmax://" ]
        : @[ @"freefireth://", @"freefire://" ];
    for (NSString *scheme in fallbacks) {
        NSURL *u = [NSURL URLWithString:scheme];
        if ([app canOpenURL:u]) { [app openURL:u options:@{} completionHandler:nil]; return; }
    }
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Ẩn menu"
                                            message:@"Vuốt lên từ đáy màn hình để ẩn app. ĐỪNG tắt app — sẽ mất ESP."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đã hiểu" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Theme

- (void)applyTheme {
    self.view.backgroundColor = VNBg();

    _titleLabel.textColor = VNText();
    _titleLabel.font = VNFont(20, UIFontWeightBold);
    _subtitleLabel.textColor = VNMuted();

    NSArray<UILabel *> *headers = @[_secControl, _secDraw, _secAim, _secCamera,
                                     _secVersion, _secStatus, _secInfo,
                                     _secExtra, _secLog, _versionSectionLabel,
                                     _espCardTitle];
    for (UILabel *l in headers) { l.textColor = VNMuted(); }

    NSArray<UIView *> *cards = @[_controlCard, _togglesCard, _espCard, _aimCard,
                                  _statusCard, _licenseCard, _authCard,
                                  _supportCard, _extraCard, _logCard,
                                  _ffCard, _ffMaxCard];
    for (UIView *c in cards) {
        c.backgroundColor = VNCard();
        c.layer.cornerRadius = 10.0f;
        c.layer.borderWidth = 0.0f;
    }

    _startButton.backgroundColor = VNAccent();
    [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _killAllButton.backgroundColor = [UIColor clearColor];
    [_killAllButton setTitleColor:VNRed() forState:UIControlStateNormal];
    _openGameButton.backgroundColor = VNAccent();
    [_openGameButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _joinButton.backgroundColor = VNAccent();
    [_joinButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_authorizationButton setTitleColor:VNAccent() forState:UIControlStateNormal];

    NSArray<UISwitch *> *allSwitches = @[_aimbotSwitch, _silentAimSwitch, _espSwitch,
        _camSwitch, _espBoxSwitch, _espLineSwitch, _espBoneSwitch, _espHealthSwitch,
        _espCountSwitch, _aimBehindWallSwitch, _autoCleanSwitch];
    for (UISwitch *s in allSwitches) s.onTintColor = VNAccent();

    _camSlider.minimumTrackTintColor = VNAccent();
    _fovSlider.minimumTrackTintColor = VNAccent();
    _espDistanceLimitSlider.minimumTrackTintColor = VNAccent();

    _triggerSegment.selectedSegmentTintColor = [UIColor whiteColor];
    _triggerSegment.backgroundColor = [UIColor colorWithWhite:0.90 alpha:1.0];
    _aimPosSegment.selectedSegmentTintColor = [UIColor whiteColor];
    _aimPosSegment.backgroundColor = [UIColor colorWithWhite:0.90 alpha:1.0];

    _logTextView.backgroundColor = [UIColor colorWithWhite:0.97 alpha:1.0];
    _logTextView.textColor = [UIColor colorWithRed:0.12 green:0.55 blue:0.22 alpha:1.0];
    _logTextView.layer.borderWidth = 1.0f;
    _logTextView.layer.borderColor = VNLine().CGColor;

    for (UIButton *b in @[_settingsBtn, _trashBtn, _closeBtn]) {
        b.backgroundColor = [UIColor clearColor];
        b.layer.borderWidth = 0;
        b.tintColor = VNAccent();
    }
    [_closeBtn setTitleColor:VNAccent() forState:UIControlStateNormal];

    _statusLabel.textColor = VNText();
    _licenseTitleLabel.textColor = VNText();
    _licenseValueLabel.textColor = VNMuted();
    _authTitleLabel.textColor = VNText();
    _authValueLabel.textColor = VNAccent();

    [self updateVersionSelectionUI];
    [self updateAuthorizationPresentation];
    [self refreshHUDState];
}

- (UIImage *)imageNamedWebPOrPNG:(NSString *)baseName {
    UIImage *img = [UIImage imageNamed:baseName];
    if (img) return img;
    NSString *path = [[NSBundle mainBundle] pathForResource:baseName ofType:@"webp"];
    if (path.length) { img = [UIImage imageWithContentsOfFile:path]; if (img) return img; }
    path = [[NSBundle mainBundle] pathForResource:baseName ofType:@"png"];
    if (path.length) img = [UIImage imageWithContentsOfFile:path];
    return img;
}

- (UIView *)makeCard {
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = VNCard();
    v.layer.cornerRadius = 10.0f;
    v.clipsToBounds = YES;
    return v;
}

- (UIButton *)makeIconButton:(NSString *)systemName {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = [UIColor clearColor];
    b.tintColor = VNAccent();
    UIImage *img = [UIImage systemImageNamed:systemName];
    if (img) [b setImage:img forState:UIControlStateNormal];
    return b;
}

- (UIButton *)makeCloseButton {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = [UIColor clearColor];
    b.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    [b setTitle:@"✕" forState:UIControlStateNormal];
    [b setTitleColor:VNAccent() forState:UIControlStateNormal];
    return b;
}

- (UIButton *)makeVersionCardCapturingIcon:(UIImageView * __strong *)outIcon
                                 nameLabel:(UILabel * __strong *)outName {
    UIButton *card = [UIButton buttonWithType:UIButtonTypeCustom];
    card.backgroundColor = VNCard();
    card.layer.cornerRadius = 10.0f;
    card.clipsToBounds = YES;
    card.layer.borderWidth = 2.0f;
    card.layer.borderColor = [UIColor clearColor].CGColor;
    card.adjustsImageWhenHighlighted = NO;

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
    icon.contentMode = UIViewContentModeScaleAspectFill;
    icon.clipsToBounds = YES;
    icon.layer.cornerRadius = 8.0f;
    icon.userInteractionEnabled = NO;
    [card addSubview:icon];

    UILabel *name = [[UILabel alloc] initWithFrame:CGRectZero];
    name.font = VNFont(13, UIFontWeightMedium);
    name.textColor = VNText();
    name.textAlignment = NSTextAlignmentCenter;
    name.userInteractionEnabled = NO;
    [card addSubview:name];

    if (outIcon) *outIcon = icon;
    if (outName) *outName = name;
    return card;
}

- (void)beginAuthorization { [self updateAuthorizationPresentation]; [self refreshHUDState]; }
- (void)retryAuthorization:(id)sender { (void)sender; [self beginAuthorization]; }
- (void)revokeAuthorization { SetHUDEnabled(NO); [self updateAuthorizationPresentation]; [self refreshHUDState]; }

- (void)updateAuthorizationPresentation {
    if (!self.isViewLoaded) return;
    _authorizationLabel.text = @"Miễn phí";
    [_authorizationButton setTitle:@"Đã mở khoá" forState:UIControlStateNormal];
    _authorizationButton.enabled = NO;
    _licenseValueLabel.text = @"Không giới hạn";
    _authValueLabel.text = @"Hoạt động";
    _authValueLabel.textColor = VNAccent();
    _autoCleanSwitch.enabled = YES;
    _autoCleanLabel.alpha = 1.0;
    _startButton.alpha = 1.0;
}

#pragma mark - Build UI

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

    // Top bar
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
    _titleLabel.font = VNFont(20, UIFontWeightBold);
    _titleLabel.textColor = VNText();
    [_contentView addSubview:_titleLabel];

    _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _subtitleLabel.text = @"iOS Companion";
    _subtitleLabel.font = VNFont(12, UIFontWeightRegular);
    _subtitleLabel.textColor = VNMuted();
    [_contentView addSubview:_subtitleLabel];

    // ============ SECTION: ĐIỀU KHIỂN HUD ============
    _secControl = VNMakeSectionHeader(@"Điều khiển HUD");
    [_contentView addSubview:_secControl];

    _controlCard = [self makeCard];
    [_contentView addSubview:_controlCard];

    _controlIconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _controlIconView.contentMode = UIViewContentModeScaleAspectFill;
    _controlIconView.clipsToBounds = YES;
    _controlIconView.layer.cornerRadius = 8.0f;
    _controlIconView.image = [self imageNamedWebPOrPNG:@"ff"] ?: [UIImage imageNamed:@"logo"];
    _controlIconView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    [_controlCard addSubview:_controlIconView];

    _controlTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _controlTitleLabel.text = @"HUD Overlay";
    _controlTitleLabel.font = VNFont(16, UIFontWeightRegular);
    _controlTitleLabel.textColor = VNText();
    [_controlCard addSubview:_controlTitleLabel];

    _controlSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _controlSubtitleLabel.text = @"Nhấn Bắt đầu khi game đã mở";
    _controlSubtitleLabel.font = VNFont(12, UIFontWeightRegular);
    _controlSubtitleLabel.textColor = VNMuted();
    _controlSubtitleLabel.numberOfLines = 2;
    [_controlCard addSubview:_controlSubtitleLabel];

    UIView *sep1 = VNMakeRowSeparator();
    sep1.tag = 9101;
    [_controlCard addSubview:sep1];

    _startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _startButton.backgroundColor = VNAccent();
    _startButton.layer.cornerRadius = 8.0f;
    _startButton.titleLabel.font = VNFont(14, UIFontWeightSemibold);
    [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
    [_startButton addTarget:self action:@selector(startButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_controlCard addSubview:_startButton];

    _killAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _killAllButton.backgroundColor = [UIColor clearColor];
    _killAllButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    _killAllButton.titleLabel.font = VNFont(16, UIFontWeightRegular);
    [_killAllButton setTitleColor:VNRed() forState:UIControlStateNormal];
    [_killAllButton setTitle:@"Tắt toàn bộ ESP / Aimbot" forState:UIControlStateNormal];
    [_killAllButton addTarget:self action:@selector(killAllTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_controlCard addSubview:_killAllButton];

    // ============ SECTION: VẼ (ESP) ============
    _secDraw = VNMakeSectionHeader(@"Vẽ");
    [_contentView addSubview:_secDraw];

    _espCard = [self makeCard];
    [_contentView addSubview:_espCard];

    // Box
    _espBoxLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espBoxLabel.text = @"Box";
    _espBoxLabel.font = VNFont(16, UIFontWeightRegular);
    _espBoxLabel.textColor = VNText();
    [_espCard addSubview:_espBoxLabel];

    _espBoxSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espBoxSwitch.onTintColor = VNAccent();
    _espBoxSwitch.on = ESPPrefsBool(@"Box", YES);
    [_espBoxSwitch addTarget:self action:@selector(espBoxChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espBoxSwitch];

    { UIView *sep = VNMakeRowSeparator(); sep.tag = 9200; [_espCard addSubview:sep]; }

    // Snapline
    _espLineLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espLineLabel.text = @"Snapline";
    _espLineLabel.font = VNFont(16, UIFontWeightRegular);
    _espLineLabel.textColor = VNText();
    [_espCard addSubview:_espLineLabel];

    _espLineSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espLineSwitch.onTintColor = VNAccent();
    _espLineSwitch.on = ESPPrefsBool(@"Line", YES);
    [_espLineSwitch addTarget:self action:@selector(espLineChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espLineSwitch];

    { UIView *sep = VNMakeRowSeparator(); sep.tag = 9201; [_espCard addSubview:sep]; }

    // Bone
    _espBoneLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espBoneLabel.text = @"Bone / Skeleton";
    _espBoneLabel.font = VNFont(16, UIFontWeightRegular);
    _espBoneLabel.textColor = VNText();
    [_espCard addSubview:_espBoneLabel];

    _espBoneSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espBoneSwitch.onTintColor = VNAccent();
    _espBoneSwitch.on = ESPPrefsBool(@"Bone", YES);
    [_espBoneSwitch addTarget:self action:@selector(espBoneChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espBoneSwitch];

    { UIView *sep = VNMakeRowSeparator(); sep.tag = 9202; [_espCard addSubview:sep]; }

    // Health
    _espHealthLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espHealthLabel.text = @"Health Bar";
    _espHealthLabel.font = VNFont(16, UIFontWeightRegular);
    _espHealthLabel.textColor = VNText();
    [_espCard addSubview:_espHealthLabel];

    _espHealthSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espHealthSwitch.onTintColor = VNAccent();
    _espHealthSwitch.on = ESPPrefsBool(@"Health", YES);
    [_espHealthSwitch addTarget:self action:@selector(espHealthChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espHealthSwitch];

    { UIView *sep = VNMakeRowSeparator(); sep.tag = 9203; [_espCard addSubview:sep]; }

    // Count
    _espCountLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espCountLabel.text = @"Player Count";
    _espCountLabel.font = VNFont(16, UIFontWeightRegular);
    _espCountLabel.textColor = VNText();
    [_espCard addSubview:_espCountLabel];

    _espCountSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espCountSwitch.onTintColor = VNAccent();
    _espCountSwitch.on = ESPPrefsBool(@"Count", YES);
    [_espCountSwitch addTarget:self action:@selector(espCountChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espCountSwitch];

    // Distance
    UIView *sepLast = VNMakeRowSeparator();
    sepLast.tag = 9210;
    [_espCard addSubview:sepLast];

    _espDistanceLimitLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espDistanceLimitLabel.text = @"Khoảng cách tối đa";
    _espDistanceLimitLabel.font = VNFont(16, UIFontWeightRegular);
    _espDistanceLimitLabel.textColor = VNText();
    [_espCard addSubview:_espDistanceLimitLabel];

    _espDistanceLimitValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espDistanceLimitValueLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    _espDistanceLimitValueLabel.textColor = VNMuted();
    _espDistanceLimitValueLabel.textAlignment = NSTextAlignmentRight;
    _espDistanceLimitValueLabel.text = [NSString stringWithFormat:@"%.0f m", ESPPrefsFloat(@"EspDistanceLimit", 150.0f)];
    [_espCard addSubview:_espDistanceLimitValueLabel];

    _espDistanceLimitSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _espDistanceLimitSlider.minimumValue = 20.0f;
    _espDistanceLimitSlider.maximumValue = 300.0f;
    _espDistanceLimitSlider.value = ESPPrefsFloat(@"EspDistanceLimit", 150.0f);
    _espDistanceLimitSlider.minimumTrackTintColor = VNAccent();
    [_espDistanceLimitSlider addTarget:self action:@selector(espDistanceLimitChanged:) forControlEvents:UIControlEventValueChanged];
    [_espDistanceLimitSlider addTarget:self action:@selector(espDistanceLimitCommitted:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [_espCard addSubview:_espDistanceLimitSlider];

    // ============ SECTION: AIM ============
    _secAim = VNMakeSectionHeader(@"Aim");
    [_contentView addSubview:_secAim];

    _aimCard = [self makeCard];
    [_contentView addSubview:_aimCard];

    // Enable Aim
    _aimbotLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimbotLabel.text = @"Enable Aim";
    _aimbotLabel.font = VNFont(16, UIFontWeightRegular);
    _aimbotLabel.textColor = VNText();
    [_aimCard addSubview:_aimbotLabel];

    _aimbotSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _aimbotSwitch.onTintColor = VNAccent();
    _aimbotSwitch.on = ESPPrefsBool(@"Aimbot", NO);
    [_aimbotSwitch addTarget:self action:@selector(aimbotSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimbotSwitch];

    { UIView *sep = VNMakeRowSeparator(); sep.tag = 9301; [_aimCard addSubview:sep]; }

    // Silent Aim
    _silentAimLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _silentAimLabel.text = @"Silent Aim";
    _silentAimLabel.font = VNFont(16, UIFontWeightRegular);
    _silentAimLabel.textColor = VNText();
    [_aimCard addSubview:_silentAimLabel];

    _silentAimSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _silentAimSwitch.onTintColor = VNAccent();
    _silentAimSwitch.on = ESPPrefsBool(@"AimSilent", NO);
    [_silentAimSwitch addTarget:self action:@selector(silentAimSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_silentAimSwitch];

    { UIView *sep = VNMakeRowSeparator(); sep.tag = 9302; [_aimCard addSubview:sep]; }

    // Behind wall
    _aimBehindWallLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimBehindWallLabel.text = @"Aim Behind Wall";
    _aimBehindWallLabel.font = VNFont(16, UIFontWeightRegular);
    _aimBehindWallLabel.textColor = VNText();
    [_aimCard addSubview:_aimBehindWallLabel];

    _aimBehindWallSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _aimBehindWallSwitch.onTintColor = VNAccent();
    _aimBehindWallSwitch.on = ESPPrefsBool(@"AimBehindWall", NO);
    [_aimBehindWallSwitch addTarget:self action:@selector(aimBehindWallSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimBehindWallSwitch];

    { UIView *sep = VNMakeRowSeparator(); sep.tag = 9303; [_aimCard addSubview:sep]; }

    // FOV
    _fovLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _fovLabel.text = @"FOV";
    _fovLabel.font = VNFont(16, UIFontWeightRegular);
    _fovLabel.textColor = VNText();
    [_aimCard addSubview:_fovLabel];

    _fovValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _fovValueLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    _fovValueLabel.textColor = VNMuted();
    _fovValueLabel.textAlignment = NSTextAlignmentRight;
    _fovValueLabel.text = [NSString stringWithFormat:@"%.0f", ESPPrefsFloat(@"Fov", 150.0f)];
    [_aimCard addSubview:_fovValueLabel];

    _fovSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _fovSlider.minimumValue = 30.0f;
    _fovSlider.maximumValue = 360.0f;
    _fovSlider.value = ESPPrefsFloat(@"Fov", 150.0f);
    _fovSlider.minimumTrackTintColor = VNAccent();
    [_fovSlider addTarget:self action:@selector(fovSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_fovSlider];

    { UIView *sep = VNMakeRowSeparator(); sep.tag = 9304; [_aimCard addSubview:sep]; }

    // Trigger
    _triggerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _triggerLabel.text = @"Trigger";
    _triggerLabel.font = VNFont(16, UIFontWeightRegular);
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
        _triggerSegment.selectedSegmentTintColor = [UIColor whiteColor];
        _triggerSegment.backgroundColor = [UIColor colorWithWhite:0.90 alpha:1.0];
    }
    [_triggerSegment addTarget:self action:@selector(triggerSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_triggerSegment];

    { UIView *sep = VNMakeRowSeparator(); sep.tag = 9305; [_aimCard addSubview:sep]; }

    // Aim Pos
    _aimPosLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimPosLabel.text = @"Aim Position";
    _aimPosLabel.font = VNFont(16, UIFontWeightRegular);
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
        _aimPosSegment.selectedSegmentTintColor = [UIColor whiteColor];
        _aimPosSegment.backgroundColor = [UIColor colorWithWhite:0.90 alpha:1.0];
    }
    [_aimPosSegment addTarget:self action:@selector(aimPosSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimPosSegment];

    // ============ SECTION: CAMERA ============
    _secCamera = VNMakeSectionHeader(@"Camera");
    [_contentView addSubview:_secCamera];

    _togglesCard = [self makeCard];
    [_contentView addSubview:_togglesCard];

    _camLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camLabel.text = @"Camera Xa (CamPC)";
    _camLabel.font = VNFont(16, UIFontWeightRegular);
    _camLabel.textColor = VNText();
    [_togglesCard addSubview:_camLabel];

    _camSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _camSwitch.onTintColor = VNAccent();
    _camSwitch.on = ESPPrefsBool(@"CamPC", NO);
    [_camSwitch addTarget:self action:@selector(camSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_camSwitch];

    { UIView *sep = VNMakeRowSeparator(); sep.tag = 9401; [_togglesCard addSubview:sep]; }

    _camValueStaticLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camValueStaticLabel.text = @"Giá trị";
    _camValueStaticLabel.font = VNFont(16, UIFontWeightRegular);
    _camValueStaticLabel.textColor = VNText();
    [_togglesCard addSubview:_camValueStaticLabel];

    _camValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camValueLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    _camValueLabel.textColor = VNMuted();
    _camValueLabel.textAlignment = NSTextAlignmentRight;
    _camValueLabel.text = [NSString stringWithFormat:@"%.0f", ESPPrefsFloat(@"CamPCValue", 30.0f)];
    [_togglesCard addSubview:_camValueLabel];

    _camSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _camSlider.minimumValue = 0.0f;
    _camSlider.maximumValue = 150.0f;
    _camSlider.value = ESPPrefsFloat(@"CamPCValue", 30.0f);
    _camSlider.minimumTrackTintColor = VNAccent();
    [_camSlider addTarget:self action:@selector(camSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_camSlider];

    // ============ SECTION: PHIÊN BẢN ============
    _secVersion = VNMakeSectionHeader(@"Phiên bản game");
    [_contentView addSubview:_secVersion];
    _versionSectionLabel = _secVersion;

    UIImageView *ffMaxIcon = nil; UILabel *ffMaxName = nil;
    _ffMaxCard = [self makeVersionCardCapturingIcon:&ffMaxIcon nameLabel:&ffMaxName];
    _ffMaxIconView = ffMaxIcon; _ffMaxNameLabel = ffMaxName;
    _ffMaxIconView.image = [self imageNamedWebPOrPNG:@"ffmax"] ?: [UIImage imageNamed:@"logo"];
    _ffMaxNameLabel.text = @"Free Fire MAX";
    _ffMaxCard.tag = 2;
    [_ffMaxCard addTarget:self action:@selector(versionCardTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_ffMaxCard];

    UIImageView *ffIcon = nil; UILabel *ffName = nil;
    _ffCard = [self makeVersionCardCapturingIcon:&ffIcon nameLabel:&ffName];
    _ffIconView = ffIcon; _ffNameLabel = ffName;
    _ffIconView.image = [self imageNamedWebPOrPNG:@"ff"] ?: [UIImage imageNamed:@"logo"];
    _ffNameLabel.text = @"Free Fire";
    _ffCard.tag = 1;
    [_ffCard addTarget:self action:@selector(versionCardTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_ffCard];

    // ============ SECTION: TRẠNG THÁI ============
    _secStatus = VNMakeSectionHeader(@"Trạng thái");
    [_contentView addSubview:_secStatus];

    _statusCard = [self makeCard];
    [_contentView addSubview:_statusCard];

    _statusDot = [[UIView alloc] initWithFrame:CGRectZero];
    _statusDot.layer.cornerRadius = 5.0f;
    _statusDot.backgroundColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    [_statusCard addSubview:_statusDot];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.font = VNFont(15, UIFontWeightRegular);
    _statusLabel.textColor = VNText();
    _statusLabel.text = @"Game chưa chạy";
    [_statusCard addSubview:_statusLabel];

    _openGameButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _openGameButton.backgroundColor = VNAccent();
    _openGameButton.layer.cornerRadius = 8.0f;
    _openGameButton.titleLabel.font = VNFont(13, UIFontWeightSemibold);
    [_openGameButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_openGameButton setTitle:@"Vào Game" forState:UIControlStateNormal];
    [_openGameButton addTarget:self action:@selector(openGameTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_statusCard addSubview:_openGameButton];

    // ============ SECTION: THÔNG TIN ============
    _secInfo = VNMakeSectionHeader(@"Thông tin");
    [_contentView addSubview:_secInfo];

    _licenseCard = [self makeCard];
    [_contentView addSubview:_licenseCard];
    _licenseTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _licenseTitleLabel.text = @"Giấy phép";
    _licenseTitleLabel.font = VNFont(16, UIFontWeightRegular);
    _licenseTitleLabel.textColor = VNText();
    [_licenseCard addSubview:_licenseTitleLabel];
    _licenseValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _licenseValueLabel.font = VNFont(15, UIFontWeightRegular);
    _licenseValueLabel.textColor = VNMuted();
    _licenseValueLabel.textAlignment = NSTextAlignmentRight;
    _licenseValueLabel.text = @"—";
    [_licenseCard addSubview:_licenseValueLabel];

    _authCard = [self makeCard];
    [_contentView addSubview:_authCard];
    _authTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authTitleLabel.text = @"Trạng thái";
    _authTitleLabel.font = VNFont(16, UIFontWeightRegular);
    _authTitleLabel.textColor = VNText();
    [_authCard addSubview:_authTitleLabel];
    _authValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authValueLabel.font = VNFont(15, UIFontWeightRegular);
    _authValueLabel.textColor = VNAccent();
    _authValueLabel.textAlignment = NSTextAlignmentRight;
    _authValueLabel.text = @"—";
    [_authCard addSubview:_authValueLabel];

    // ============ SECTION: KHÁC ============
    _secExtra = VNMakeSectionHeader(@"Khác");
    [_contentView addSubview:_secExtra];

    _extraCard = [self makeCard];
    [_contentView addSubview:_extraCard];

    _autoCleanLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _autoCleanLabel.text = @"VarClean trước khi bật HUD";
    _autoCleanLabel.font = VNFont(16, UIFontWeightRegular);
    _autoCleanLabel.textColor = VNText();
    [_extraCard addSubview:_autoCleanLabel];

    _autoCleanSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _autoCleanSwitch.onTintColor = VNAccent();
    _autoCleanSwitch.on = ESPPrefsBool(@"AutoVarCleanBeforeHUD", NO);
    [_autoCleanSwitch addTarget:self action:@selector(autoCleanSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_extraCard addSubview:_autoCleanSwitch];

    { UIView *sep = VNMakeRowSeparator(); sep.tag = 9501; [_extraCard addSubview:sep]; }

    _authorizationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authorizationLabel.text = @"Kích hoạt";
    _authorizationLabel.font = VNFont(16, UIFontWeightRegular);
    _authorizationLabel.textColor = VNText();
    [_extraCard addSubview:_authorizationLabel];

    _authorizationButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _authorizationButton.titleLabel.font = VNFont(15, UIFontWeightRegular);
    _authorizationButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    [_authorizationButton setTitleColor:VNAccent() forState:UIControlStateNormal];
    [_authorizationButton addTarget:self action:@selector(retryAuthorization:) forControlEvents:UIControlEventTouchUpInside];
    [_extraCard addSubview:_authorizationButton];

    { UIView *sep = VNMakeRowSeparator(); sep.tag = 9502; [_extraCard addSubview:sep]; }

    _supportTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportTitleLabel.text = @"Liên hệ hỗ trợ";
    _supportTitleLabel.font = VNFont(16, UIFontWeightRegular);
    _supportTitleLabel.textColor = VNText();
    [_extraCard addSubview:_supportTitleLabel];

    _supportSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportSubtitleLabel.text = @"Telegram";
    _supportSubtitleLabel.font = VNFont(13, UIFontWeightRegular);
    _supportSubtitleLabel.textColor = VNMuted();
    [_extraCard addSubview:_supportSubtitleLabel];

    _joinButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _joinButton.backgroundColor = VNAccent();
    _joinButton.layer.cornerRadius = 6.0f;
    _joinButton.titleLabel.font = VNFont(13, UIFontWeightSemibold);
    [_joinButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_joinButton setTitle:@"Join" forState:UIControlStateNormal];
    [_joinButton addTarget:self action:@selector(joinSupportTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_extraCard addSubview:_joinButton];

    // ============ SECTION: NHẬT KÝ ============
    _secLog = VNMakeSectionHeader(@"Nhật ký");
    [_contentView addSubview:_secLog];

    _logCard = [self makeCard];
    [_contentView addSubview:_logCard];
    _logTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    _logTextView.editable = NO;
    _logTextView.scrollEnabled = YES;
    _logTextView.showsHorizontalScrollIndicator = NO;
    _logTextView.backgroundColor = [UIColor colorWithWhite:0.97 alpha:1.0];
    _logTextView.layer.cornerRadius = 8.0f;
    _logTextView.layer.borderWidth = 1.0f;
    _logTextView.layer.borderColor = VNLine().CGColor;
    _logTextView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _logTextView.textColor = [UIColor colorWithRed:0.12 green:0.55 blue:0.22 alpha:1.0];
    _logTextView.text = @"[VN TOOL] ready.\nPress Bắt đầu to boot kernel.";
    [_logCard addSubview:_logTextView];

    [self applyTheme];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    _scrollView.frame = self.view.bounds;

    CGFloat gear = 32.0f;
    CGFloat topY = insets.top + 8;
    _closeBtn.frame = CGRectMake(insets.left + 16, topY, gear, gear);
    _settingsBtn.frame = CGRectMake(width - insets.right - 16 - gear, topY, gear, gear);
    _trashBtn.frame = CGRectMake(CGRectGetMinX(_settingsBtn.frame) - 8 - gear, topY, gear, gear);

    CGFloat xPad = 16.0f;
    CGFloat cardW = width - xPad * 2.0f;
    CGFloat y = insets.top + 12;

    _titleLabel.frame = CGRectMake(xPad, y, 200, 26);
    _subtitleLabel.frame = CGRectMake(xPad, y + 26, 200, 16);
    y = y + 26 + 16 + 18;

    CGFloat sectionHeaderH = 20;
    CGFloat rowH = 52;
    CGFloat sepInset = 16;

    // ===== CONTROL =====
    _secControl.frame = CGRectMake(xPad + 4, y, cardW - 8, sectionHeaderH);
    y = CGRectGetMaxY(_secControl.frame) + 6;

    CGFloat controlRow1H = 72;
    CGFloat controlRow2H = 48;
    CGFloat controlH = controlRow1H + 1 + controlRow2H;
    _controlCard.frame = CGRectMake(xPad, y, cardW, controlH);

    CGFloat iconSize = 44;
    _controlIconView.frame = CGRectMake(16, (controlRow1H - iconSize) * 0.5f, iconSize, iconSize);

    _controlTitleLabel.frame = CGRectMake(iconSize + 16 + 12, 14, cardW - iconSize - 16 - 12 - 110, 22);
    _controlSubtitleLabel.frame = CGRectMake(iconSize + 16 + 12, 38, cardW - iconSize - 16 - 12 - 110, 18);

    CGFloat btnW = 92;
    _startButton.frame = CGRectMake(cardW - btnW - 16, (controlRow1H - 34) * 0.5f, btnW, 34);

    UIView *sep1 = [_controlCard viewWithTag:9101];
    sep1.frame = CGRectMake(sepInset, controlRow1H, cardW - sepInset, 0.5);

    _killAllButton.frame = CGRectMake(16, controlRow1H + 1, cardW - 32, controlRow2H);
    y = CGRectGetMaxY(_controlCard.frame) + 24;

    // ===== ESP =====
    _secDraw.frame = CGRectMake(xPad + 4, y, cardW - 8, sectionHeaderH);
    y = CGRectGetMaxY(_secDraw.frame) + 6;

    NSUInteger espRowCount = 5;
    CGFloat espLabelRowH = rowH * espRowCount;
    CGFloat espDistRowH = 92;
    CGFloat espH = espLabelRowH + espDistRowH;
    _espCard.frame = CGRectMake(xPad, y, cardW, espH);

    NSArray<UILabel *> *espLabelsArr = @[_espBoxLabel, _espLineLabel, _espBoneLabel,
                                          _espHealthLabel, _espCountLabel];
    NSArray<UISwitch *> *espSwitchesArr = @[_espBoxSwitch, _espLineSwitch, _espBoneSwitch,
                                             _espHealthSwitch, _espCountSwitch];
    for (NSUInteger i = 0; i < espRowCount; i++) {
        CGFloat ry = i * rowH;
        UILabel *l = espLabelsArr[i];
        UISwitch *s = espSwitchesArr[i];
        l.frame = CGRectMake(16, ry, cardW - 90, rowH);
        CGSize sw = s.intrinsicContentSize;
        s.frame = CGRectMake(cardW - sw.width - 16, ry + (rowH - sw.height) * 0.5f, sw.width, sw.height);

        UIView *sep = [_espCard viewWithTag:9200 + i];
        sep.frame = CGRectMake(sepInset, ry + rowH, cardW - sepInset, 0.5);
    }

    UIView *sepLast = [_espCard viewWithTag:9210];
    sepLast.frame = CGRectMake(sepInset, espLabelRowH, cardW - sepInset, 0.5);

    CGFloat distY = espLabelRowH + 1;
    _espDistanceLimitLabel.frame = CGRectMake(16, distY + 12, cardW - 120, 24);
    _espDistanceLimitValueLabel.frame = CGRectMake(cardW - 100, distY + 12, 84, 24);
    _espDistanceLimitSlider.frame = CGRectMake(16, distY + 46, cardW - 32, 30);
    y = CGRectGetMaxY(_espCard.frame) + 24;

    // ===== AIM =====
    _secAim.frame = CGRectMake(xPad + 4, y, cardW - 8, sectionHeaderH);
    y = CGRectGetMaxY(_secAim.frame) + 6;

    CGFloat aimH = 52*3 + 80 + 84 + 84;
    _aimCard.frame = CGRectMake(xPad, y, cardW, aimH);

    CGFloat aimY = 0;
    _aimbotLabel.frame = CGRectMake(16, aimY, cardW - 90, 52);
    { CGSize sw = _aimbotSwitch.intrinsicContentSize;
      _aimbotSwitch.frame = CGRectMake(cardW - sw.width - 16, aimY + (52 - sw.height)*0.5f, sw.width, sw.height); }
    UIView *aimSep1 = [_aimCard viewWithTag:9301];
    aimSep1.frame = CGRectMake(sepInset, aimY + 52, cardW - sepInset, 0.5);
    aimY += 53;

    _silentAimLabel.frame = CGRectMake(16, aimY, cardW - 90, 52);
    { CGSize sw = _silentAimSwitch.intrinsicContentSize;
      _silentAimSwitch.frame = CGRectMake(cardW - sw.width - 16, aimY + (52 - sw.height)*0.5f, sw.width, sw.height); }
    UIView *aimSep2 = [_aimCard viewWithTag:9302];
    aimSep2.frame = CGRectMake(sepInset, aimY + 52, cardW - sepInset, 0.5);
    aimY += 53;

    _aimBehindWallLabel.frame = CGRectMake(16, aimY, cardW - 90, 52);
    { CGSize sw = _aimBehindWallSwitch.intrinsicContentSize;
      _aimBehindWallSwitch.frame = CGRectMake(cardW - sw.width - 16, aimY + (52 - sw.height)*0.5f, sw.width, sw.height); }
    UIView *aimSep3 = [_aimCard viewWithTag:9303];
    aimSep3.frame = CGRectMake(sepInset, aimY + 52, cardW - sepInset, 0.5);
    aimY += 53;

    _fovLabel.frame = CGRectMake(16, aimY + 12, 120, 22);
    _fovValueLabel.frame = CGRectMake(cardW - 100, aimY + 12, 84, 22);
    _fovSlider.frame = CGRectMake(16, aimY + 42, cardW - 32, 30);
    UIView *aimSep4 = [_aimCard viewWithTag:9304];
    aimSep4.frame = CGRectMake(sepInset, aimY + 80, cardW - sepInset, 0.5);
    aimY += 81;

    _triggerLabel.frame = CGRectMake(16, aimY + 10, 120, 22);
    _triggerSegment.frame = CGRectMake(16, aimY + 38, cardW - 32, 32);
    UIView *aimSep5 = [_aimCard viewWithTag:9305];
    aimSep5.frame = CGRectMake(sepInset, aimY + 84, cardW - sepInset, 0.5);
    aimY += 85;

    _aimPosLabel.frame = CGRectMake(16, aimY + 10, 120, 22);
    _aimPosSegment.frame = CGRectMake(16, aimY + 38, cardW - 32, 32);
    y = CGRectGetMaxY(_aimCard.frame) + 24;

    // ===== CAMERA =====
    _secCamera.frame = CGRectMake(xPad + 4, y, cardW - 8, sectionHeaderH);
    y = CGRectGetMaxY(_secCamera.frame) + 6;

    CGFloat camH = 52 + 1 + 80;
    _togglesCard.frame = CGRectMake(xPad, y, cardW, camH);
    _camLabel.frame = CGRectMake(16, 0, cardW - 90, 52);
    { CGSize sw = _camSwitch.intrinsicContentSize;
      _camSwitch.frame = CGRectMake(cardW - sw.width - 16, (52 - sw.height)*0.5f, sw.width, sw.height); }
    UIView *camSep = [_togglesCard viewWithTag:9401];
    camSep.frame = CGRectMake(sepInset, 52, cardW - sepInset, 0.5);

    _camValueStaticLabel.frame = CGRectMake(16, 53 + 12, 120, 22);
    _camValueLabel.frame = CGRectMake(cardW - 100, 53 + 12, 84, 22);
    _camSlider.frame = CGRectMake(16, 53 + 42, cardW - 32, 30);
    y = CGRectGetMaxY(_togglesCard.frame) + 24;

    // ===== VERSION =====
    _secVersion.frame = CGRectMake(xPad + 4, y, cardW - 8, sectionHeaderH);
    y = CGRectGetMaxY(_secVersion.frame) + 6;

    CGFloat gap = 12;
    CGFloat versionW = (cardW - gap) * 0.5f;
    CGFloat versionH = 120;
    _ffMaxCard.frame = CGRectMake(xPad, y, versionW, versionH);
    _ffCard.frame = CGRectMake(xPad + versionW + gap, y, versionW, versionH);
    CGFloat iconSide = 56;
    _ffMaxIconView.frame = CGRectMake((versionW - iconSide) * 0.5f, 18, iconSide, iconSide);
    _ffIconView.frame = CGRectMake((versionW - iconSide) * 0.5f, 18, iconSide, iconSide);
    _ffMaxNameLabel.frame = CGRectMake(8, 82, versionW - 16, 22);
    _ffNameLabel.frame = CGRectMake(8, 82, versionW - 16, 22);
    y = CGRectGetMaxY(_ffMaxCard.frame) + 24;

    // ===== STATUS =====
    _secStatus.frame = CGRectMake(xPad + 4, y, cardW - 8, sectionHeaderH);
    y = CGRectGetMaxY(_secStatus.frame) + 6;

    CGFloat statusH = 64;
    _statusCard.frame = CGRectMake(xPad, y, cardW, statusH);
    _statusDot.frame = CGRectMake(16, (statusH - 10)*0.5f, 10, 10);
    _openGameButton.frame = CGRectMake(cardW - 108, (statusH - 34)*0.5f, 92, 34);
    _statusLabel.frame = CGRectMake(36, 0, cardW - 108 - 44, statusH);
    y = CGRectGetMaxY(_statusCard.frame) + 24;

    // ===== INFO =====
    _secInfo.frame = CGRectMake(xPad + 4, y, cardW - 8, sectionHeaderH);
    y = CGRectGetMaxY(_secInfo.frame) + 6;

    CGFloat infoH = 52;
    _licenseCard.frame = CGRectMake(xPad, y, cardW, infoH);
    _licenseTitleLabel.frame = CGRectMake(16, 0, cardW/2, infoH);
    _licenseValueLabel.frame = CGRectMake(cardW/2, 0, cardW/2 - 16, infoH);
    y = CGRectGetMaxY(_licenseCard.frame) + 1;

    _authCard.frame = CGRectMake(xPad, y, cardW, infoH);
    _authTitleLabel.frame = CGRectMake(16, 0, cardW/2, infoH);
    _authValueLabel.frame = CGRectMake(cardW/2, 0, cardW/2 - 16, infoH);
    y = CGRectGetMaxY(_authCard.frame) + 24;

    // ===== EXTRA =====
    _secExtra.frame = CGRectMake(xPad + 4, y, cardW - 8, sectionHeaderH);
    y = CGRectGetMaxY(_secExtra.frame) + 6;

    CGFloat extraH = 52 + 1 + 52 + 1 + 72;
    _extraCard.frame = CGRectMake(xPad, y, cardW, extraH);

    _autoCleanLabel.frame = CGRectMake(16, 0, cardW - 90, 52);
    { CGSize sw = _autoCleanSwitch.intrinsicContentSize;
      _autoCleanSwitch.frame = CGRectMake(cardW - sw.width - 16, (52 - sw.height)*0.5f, sw.width, sw.height); }
    UIView *exSep1 = [_extraCard viewWithTag:9501];
    exSep1.frame = CGRectMake(sepInset, 52, cardW - sepInset, 0.5);

    _authorizationLabel.frame = CGRectMake(16, 53, cardW/2, 52);
    _authorizationButton.frame = CGRectMake(cardW/2, 53, cardW/2 - 16, 52);
    UIView *exSep2 = [_extraCard viewWithTag:9502];
    exSep2.frame = CGRectMake(sepInset, 105, cardW - sepInset, 0.5);

    _supportTitleLabel.frame = CGRectMake(16, 106 + 12, cardW - 120, 22);
    _supportSubtitleLabel.frame = CGRectMake(16, 106 + 36, cardW - 120, 18);
    _joinButton.frame = CGRectMake(cardW - 84, 106 + (72 - 32)*0.5f, 68, 32);
    y = CGRectGetMaxY(_extraCard.frame) + 24;

    // ===== LOG =====
    _secLog.frame = CGRectMake(xPad + 4, y, cardW - 8, sectionHeaderH);
    y = CGRectGetMaxY(_secLog.frame) + 6;

    CGFloat logH = 180;
    _logCard.frame = CGRectMake(xPad, y, cardW, logH);
    _logTextView.frame = CGRectMake(8, 8, cardW - 16, logH - 16);
    y = CGRectGetMaxY(_logCard.frame) + 24 + insets.bottom;

    _contentView.frame = CGRectMake(0, 0, width, MAX(y, height));
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
    _ffMaxCard.layer.borderColor = (isMax ? selected : [UIColor clearColor]).CGColor;
    _ffCard.layer.borderColor = (!isMax ? selected : [UIColor clearColor]).CGColor;

    UIImage *icon = [self imageNamedWebPOrPNG:isMax ? @"ffmax" : @"ff"];
    if (icon) _controlIconView.image = icon;
}

#pragma mark - Lifecycle

- (void)appBecameActive {
    GameOffsetsReload();
    [self applyTheme];
    [self updateVersionSelectionUI];
    [self refreshHUDState];
}

#pragma mark - HUD / game

- (BOOL)isGameRunning { return GameTargetIsRunning(); }

- (void)startPollingGameState {
    __weak __typeof(self) weakSelf = self;
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                   repeats:YES
                                                     block:^(NSTimer *timer) {
        [weakSelf refreshHUDState];
    }];
}

- (void)autoCleanSwitchChanged:(UISwitch *)sender { ESPPrefsSetBool(@"AutoVarCleanBeforeHUD", sender.on); }

- (void)aimbotSwitchChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"Aimbot", sender.on); ESPSyncFromPrefs(); }
- (void)silentAimSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"AimSilent", sender.on);
    ESPSyncFromPrefs();
    NSLog(@"[VN] AimSilent set to %d", (int)sender.on);
}
- (void)espSwitchChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"EnableESP", sender.on); ESPSyncFromPrefs(); }
- (void)camSwitchChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"CamPC", sender.on); ESPSyncFromPrefs(); }
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

#pragma mark - ESP toggles
- (void)espBoxChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"Box", sender.on); ESPSyncFromPrefs(); }
- (void)espLineChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"Line", sender.on); ESPSyncFromPrefs(); }
- (void)espBoneChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"Bone", sender.on); ESPSyncFromPrefs(); }
- (void)espHealthChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"Health", sender.on); ESPSyncFromPrefs(); }
- (void)espCountChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"Count", sender.on); ESPSyncFromPrefs(); }

- (void)espDistanceLimitChanged:(UISlider *)sender {
    float v = sender.value;
    _espDistanceLimitValueLabel.text = [NSString stringWithFormat:@"%.0f m", v];
    ESPPrefsSetFloatLive(@"EspDistanceLimit", v);
}
- (void)espDistanceLimitCommitted:(UISlider *)sender {
    ESPPrefsSetFloat(@"EspDistanceLimit", sender.value);
    ESPSyncFromPrefs();
}

- (void)triggerSegmentChanged:(UISegmentedControl *)sender {
    float v = (float)sender.selectedSegmentIndex;
    NSUserDefaults *std = [NSUserDefaults standardUserDefaults];
    [std setFloat:v forKey:@"TriggerMode"];
    [std setFloat:v forKey:@"TriggerMode_Lite"];
    [std synchronize];
    ESPPrefsSetFloat(@"TriggerMode", v);
    ESPSyncFromPrefs();
}
- (void)aimPosSegmentChanged:(UISegmentedControl *)sender {
    float v = (float)sender.selectedSegmentIndex;
    NSUserDefaults *std = [NSUserDefaults standardUserDefaults];
    [std setFloat:v forKey:@"AimPos"];
    [std setFloat:v forKey:@"AimPos_Lite"];
    [std synchronize];
    ESPPrefsSetFloat(@"AimPos", v);
    ESPSyncFromPrefs();
}
- (void)aimBehindWallSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"AimBehindWall", sender.on);
    ESPSyncFromPrefs();
}

#pragma mark - Start / Kill All

- (void)startButtonTapped:(UIButton *)sender {
    (void)sender;
    BOOL hudOn = IsHUDEnabled();
    NSLog(@"[VN-DEBUG] startButton tapped. hudOn(before)=%d", hudOn);

    if (hudOn) {
        ++_hudRequestSerial;
        _pendingHUDEnableUntil = 0;
        SetHUDEnabled(NO);
        NSLog(@"[VN-DEBUG] SetHUDEnabled(NO). hudOn(after)=%d", IsHUDEnabled());
        [self refreshHUDState];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self refreshHUDState];
        });
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

- (void)killAllTapped:(id)sender {
    (void)sender;
    ++_hudRequestSerial;
    _pendingHUDEnableUntil = 0;

    SetHUDEnabled(NO);

    ESPPrefsSetBoolLive(@"Aimbot", NO);
    ESPPrefsSetBoolLive(@"AimSilent", NO);
    ESPPrefsSetBoolLive(@"EnableESP", NO);
    ESPPrefsSetBoolLive(@"CamPC", NO);
    ESPPrefsSetBoolLive(@"Box", NO);
    ESPPrefsSetBoolLive(@"Line", NO);
    ESPPrefsSetBoolLive(@"Bone", NO);
    ESPPrefsSetBoolLive(@"Health", NO);
    ESPPrefsSetBoolLive(@"Count", NO);
    ESPPrefsSetBoolLive(@"AimBehindWall", NO);

    ESPSyncFromPrefs();

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.aimbotSwitch setOn:NO animated:YES];
        [self.silentAimSwitch setOn:NO animated:YES];
        [self.espSwitch setOn:NO animated:YES];
        [self.camSwitch setOn:NO animated:YES];
        [self.espBoxSwitch setOn:NO animated:YES];
        [self.espLineSwitch setOn:NO animated:YES];
        [self.espBoneSwitch setOn:NO animated:YES];
        [self.espHealthSwitch setOn:NO animated:YES];
        [self.espCountSwitch setOn:NO animated:YES];
        [self.aimBehindWallSwitch setOn:NO animated:YES];

        [self appendBootLog:@"[VN] Tắt toàn bộ HUD + ESP + Aimbot"];
        [self refreshHUDState];
    });
}

#pragma mark - Open game / support

- (void)openGameTapped:(id)sender {
    (void)sender;
    NSString *bundleId = GameTargetIsMax() ? @"com.dts.freefiremax" : @"vn.vng.freefireth";
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", bundleId]];
    UIApplication *app = [UIApplication sharedApplication];
    if ([app canOpenURL:url]) { [app openURL:url options:@{} completionHandler:nil]; return; }
    NSArray<NSString *> *fallbacks = GameTargetIsMax()
        ? @[ @"freefiremax://", @"ffmax://" ]
        : @[ @"freefireth://", @"freefire://" ];
    for (NSString *scheme in fallbacks) {
        NSURL *u = [NSURL URLWithString:scheme];
        if ([app canOpenURL:u]) { [app openURL:u options:@{} completionHandler:nil]; return; }
    }
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Không mở được game"
                                            message:@"Hãy mở Free Fire / Free Fire MAX thủ công."
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
        _statusLabel.text = [NSString stringWithFormat:@"%@ đang chạy", name];
    } else {
        _statusDot.backgroundColor = VNRed();
        _statusLabel.text = @"Game chưa chạy";
    }

    if (!gameIsAvailable) {
        [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
        _startButton.enabled = YES;
        _startButton.backgroundColor = VNAccent();
        _controlSubtitleLabel.text = @"Nhấn Bắt đầu khi game đã mở";
        _pendingHUDEnableUntil = 0;
        return;
    }

    _startButton.enabled = YES;

    CFTimeInterval now = CACurrentMediaTime();
    BOOL isWithinEnableGracePeriod = _pendingHUDEnableUntil > 0 && now < _pendingHUDEnableUntil;
    if (!hudIsEnabled && isWithinEnableGracePeriod) {
        [_startButton setTitle:@"Đang bật…" forState:UIControlStateNormal];
        _startButton.backgroundColor = VNAccentDim();
        _controlSubtitleLabel.text = @"Đang khởi động kernel…";
        return;
    }

    if (hudIsEnabled) {
        _pendingHUDEnableUntil = 0;
        [_startButton setTitle:@"Tắt HUD" forState:UIControlStateNormal];
        _startButton.backgroundColor = VNRed();
        _controlSubtitleLabel.text = @"HUD đang hoạt động";
    } else {
        [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
        _startButton.backgroundColor = VNAccent();
        _controlSubtitleLabel.text = @"Nhấn Bắt đầu khi game đã mở";
    }
}

@end
