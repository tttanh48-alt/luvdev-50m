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

#pragma mark - VN TOOL iOS light theme

static UIColor *VNBg(void)       { return [UIColor colorWithRed:0.949 green:0.949 blue:0.969 alpha:1.0]; }
static UIColor *VNCard(void)     { return [UIColor whiteColor]; }
static UIColor *VNPanel2(void)   { return [UIColor colorWithWhite:0.90 alpha:1.0]; }
static UIColor *VNLine(void)     { return [UIColor colorWithWhite:0.85 alpha:1.0]; }
static UIColor *VNText(void)     { return [UIColor blackColor]; }
static UIColor *VNMuted(void)    { return [UIColor colorWithWhite:0.42 alpha:1.0]; }
static UIColor *VNAccent(void)   { return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0]; }
static UIColor *VNAccentDim(void){ return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:0.5]; }
static UIColor *VNBlue(void)     { return VNAccent(); }
static UIColor *VNOrange(void)   { return VNAccent(); }
static UIColor *VNRed(void)      { return [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0]; }

static UIView *VNMakeCard(void) {
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = VNCard();
    v.layer.cornerRadius = 12.0f;
    v.layer.borderWidth = 0.0f;
    v.clipsToBounds = YES;
    return v;
}

static UIFont *VNFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

@interface HomeViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIButton *settingsBtn;

@property (nonatomic, strong) UIView *controlCard;
@property (nonatomic, strong) UIImageView *controlIconView;
@property (nonatomic, strong) UILabel *controlTitleLabel;
@property (nonatomic, strong) UILabel *controlSubtitleLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *killAllButton;

@property (nonatomic, strong) UIView *togglesCard;
@property (nonatomic, strong) UILabel *aimbotLabel;
@property (nonatomic, strong) UISwitch *aimbotSwitch;
@property (nonatomic, strong) UILabel *aimBehindWallLabel;
@property (nonatomic, strong) UISwitch *aimBehindWallSwitch;
@property (nonatomic, strong) UILabel *silentAimLabel;
@property (nonatomic, strong) UISwitch *silentAimSwitch;
@property (nonatomic, strong) UILabel *espLabel;
@property (nonatomic, strong) UISwitch *espSwitch;
@property (nonatomic, strong) UILabel *camLabel;
@property (nonatomic, strong) UISwitch *camSwitch;
@property (nonatomic, strong) UISlider *camSlider;
@property (nonatomic, strong) UILabel *camValueLabel;

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

@property (nonatomic, strong) UIView *aimCard;
@property (nonatomic, strong) UILabel *fovLabel;
@property (nonatomic, strong) UISlider *fovSlider;
@property (nonatomic, strong) UILabel *fovValueLabel;
@property (nonatomic, strong) UILabel *triggerLabel;
@property (nonatomic, strong) UISegmentedControl *triggerSegment;
@property (nonatomic, strong) UILabel *aimPosLabel;
@property (nonatomic, strong) UISegmentedControl *aimPosSegment;

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
@property (nonatomic, strong) UIView *logCard;
@property (nonatomic, strong) UITextView *logTextView;
- (void)appendBootLog:(NSString *)line;

@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) NSInteger gameMissingStreak;
@property (nonatomic, assign) CFTimeInterval pendingHUDEnableUntil;
@property (nonatomic, assign) NSInteger hudRequestSerial;
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

- (void)applyTheme {
    self.view.backgroundColor = VNBg();

    _controlCard.backgroundColor = VNCard();
    _controlTitleLabel.textColor = VNText();
    _controlSubtitleLabel.textColor = VNMuted();
    _startButton.backgroundColor = VNAccent();
    [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _killAllButton.backgroundColor = VNPanel2();
    [_killAllButton setTitleColor:VNRed() forState:UIControlStateNormal];

    _togglesCard.backgroundColor = VNCard();
    _aimbotLabel.textColor = VNText();
    _aimbotSwitch.onTintColor = VNAccent();
    _aimBehindWallLabel.textColor = VNText();
    _aimBehindWallSwitch.onTintColor = VNAccent();
    _silentAimLabel.textColor = VNText();
    _silentAimSwitch.onTintColor = VNAccent();
    _espLabel.textColor = VNText();
    _espSwitch.onTintColor = VNAccent();
    _camLabel.textColor = VNText();
    _camSwitch.onTintColor = VNAccent();
    _camSlider.minimumTrackTintColor = VNAccent();
    _camValueLabel.textColor = VNMuted();

    _espCard.backgroundColor = VNCard();
    _espCardTitle.textColor = VNMuted();
    for (UILabel *l in @[_espBoxLabel, _espLineLabel, _espBoneLabel,
                          _espHealthLabel, _espCountLabel, _espDistanceLimitLabel]) {
        l.textColor = VNText();
    }
    for (UISwitch *s in @[_espBoxSwitch, _espLineSwitch, _espBoneSwitch,
                           _espHealthSwitch, _espCountSwitch]) {
        s.onTintColor = VNAccent();
    }
    _espDistanceLimitSlider.minimumTrackTintColor = VNAccent();
    _espDistanceLimitValueLabel.textColor = VNMuted();

    _aimCard.backgroundColor = VNCard();
    _fovLabel.textColor = VNText();
    _fovSlider.minimumTrackTintColor = VNAccent();
    _fovValueLabel.textColor = VNMuted();
    _triggerLabel.textColor = VNText();
    _triggerSegment.selectedSegmentTintColor = VNAccent();
    _triggerSegment.backgroundColor = VNPanel2();
    _aimPosLabel.textColor = VNText();
    _aimPosSegment.selectedSegmentTintColor = VNAccent();
    _aimPosSegment.backgroundColor = VNPanel2();

    _versionSectionLabel.textColor = VNMuted();
    _ffMaxCard.backgroundColor = VNCard();
    _ffCard.backgroundColor = VNCard();
    _ffMaxNameLabel.textColor = VNText();
    _ffNameLabel.textColor = VNText();

    _statusCard.backgroundColor = VNCard();
    _statusLabel.textColor = VNText();
    _openGameButton.backgroundColor = VNAccent();
    [_openGameButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    _licenseCard.backgroundColor = VNCard();
    _authCard.backgroundColor = VNCard();
    _licenseTitleLabel.textColor = VNMuted();
    _licenseValueLabel.textColor = VNText();
    _authTitleLabel.textColor = VNMuted();
    _authValueLabel.textColor = VNAccent();

    _supportCard.backgroundColor = VNCard();
    _supportTitleLabel.textColor = VNText();
    _supportSubtitleLabel.textColor = VNMuted();
    _joinButton.backgroundColor = VNAccent();
    [_joinButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    _extraCard.backgroundColor = VNCard();
    _autoCleanLabel.textColor = VNText();
    _autoCleanSwitch.onTintColor = VNAccent();
    _authorizationLabel.textColor = VNText();
    [_authorizationButton setTitleColor:VNAccent() forState:UIControlStateNormal];

    _logCard.backgroundColor = VNCard();
    _logTextView.backgroundColor = [UIColor colorWithWhite:0.97 alpha:1.0];
    _logTextView.layer.borderColor = VNLine().CGColor;
    _logTextView.textColor = [UIColor colorWithRed:0.12 green:0.55 blue:0.22 alpha:1.0];

    _settingsBtn.backgroundColor = VNPanel2();
    _settingsBtn.tintColor = VNAccent();

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

- (UIView *)makeCard { return VNMakeCard(); }

- (UIButton *)makeIconButton:(NSString *)systemName {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = VNPanel2();
    b.layer.cornerRadius = 10.0f;
    b.tintColor = VNAccent();
    UIImage *img = [UIImage systemImageNamed:systemName];
    if (img) [b setImage:img forState:UIControlStateNormal];
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
    name.font = VNFont(14, UIFontWeightSemibold);
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

    // Chỉ giữ settings button (đã bỏ close & trash)
    _settingsBtn = [self makeIconButton:@"gearshape.fill"];
    [_settingsBtn addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_settingsBtn];

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
    _controlTitleLabel.font = VNFont(17, UIFontWeightBold);
    _controlTitleLabel.textColor = VNText();
    _controlTitleLabel.adjustsFontSizeToFitWidth = YES;
    _controlTitleLabel.minimumScaleFactor = 0.85f;
    [_controlCard addSubview:_controlTitleLabel];

    _controlSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _controlSubtitleLabel.text = @"Nhấn Bắt đầu khi game đã mở";
    _controlSubtitleLabel.font = VNFont(12, UIFontWeightMedium);
    _controlSubtitleLabel.textColor = VNMuted();
    _controlSubtitleLabel.numberOfLines = 2;
    [_controlCard addSubview:_controlSubtitleLabel];

    _startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _startButton.backgroundColor = VNAccent();
    _startButton.layer.cornerRadius = 12.0f;
    _startButton.titleLabel.font = VNFont(15, UIFontWeightBold);
    [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
    [_startButton addTarget:self action:@selector(startButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_controlCard addSubview:_startButton];

    _killAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _killAllButton.backgroundColor = VNPanel2();
    _killAllButton.layer.cornerRadius = 12.0f;
    _killAllButton.layer.borderWidth = 1.5f;
    _killAllButton.layer.borderColor = VNRed().CGColor;
    _killAllButton.titleLabel.font = VNFont(14, UIFontWeightBold);
    [_killAllButton setTitleColor:VNRed() forState:UIControlStateNormal];
    [_killAllButton setTitle:@"Tắt hết" forState:UIControlStateNormal];
    [_killAllButton addTarget:self action:@selector(killAllTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_controlCard addSubview:_killAllButton];

    // Toggles card
    _togglesCard = [self makeCard];
    [_contentView addSubview:_togglesCard];

    _aimbotLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimbotLabel.text = @"Aimbot";
    _aimbotLabel.font = VNFont(17, UIFontWeightSemibold);
    _aimbotLabel.textColor = VNText();
    [_togglesCard addSubview:_aimbotLabel];
    _aimbotSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _aimbotSwitch.onTintColor = VNAccent();
    _aimbotSwitch.on = ESPPrefsBool(@"Aimbot", NO);
    [_aimbotSwitch addTarget:self action:@selector(aimbotSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_aimbotSwitch];

    _aimBehindWallLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimBehindWallLabel.text = @"Aim Behind Wall";
    _aimBehindWallLabel.font = VNFont(17, UIFontWeightSemibold);
    _aimBehindWallLabel.textColor = VNText();
    [_togglesCard addSubview:_aimBehindWallLabel];

    _aimBehindWallSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _aimBehindWallSwitch.onTintColor = VNAccent();
    _aimBehindWallSwitch.on = ESPPrefsBool(@"AimBehindWall", NO);
    [_aimBehindWallSwitch addTarget:self action:@selector(aimBehindWallSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_aimBehindWallSwitch];

    _silentAimLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _silentAimLabel.text = @"Silent Aim";
    _silentAimLabel.font = VNFont(17, UIFontWeightSemibold);
    _silentAimLabel.textColor = VNText();
    [_togglesCard addSubview:_silentAimLabel];
    _silentAimSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _silentAimSwitch.onTintColor = VNAccent();
    _silentAimSwitch.on = ESPPrefsBool(@"AimSilent", NO);
    [_silentAimSwitch addTarget:self action:@selector(silentAimSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_silentAimSwitch];

    _espLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espLabel.text = @"Bật ESP";
    _espLabel.font = VNFont(17, UIFontWeightSemibold);
    _espLabel.textColor = VNText();
    [_togglesCard addSubview:_espLabel];
    _espSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espSwitch.onTintColor = VNAccent();
    _espSwitch.on = ESPPrefsBool(@"EnableESP", YES);
    [_espSwitch addTarget:self action:@selector(espSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_espSwitch];

    _camLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camLabel.text = @"Camera Xa (CamPC)";
    _camLabel.font = VNFont(17, UIFontWeightSemibold);
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
    _camValueLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightSemibold];
    _camValueLabel.textColor = VNMuted();
    _camValueLabel.textAlignment = NSTextAlignmentRight;
    _camValueLabel.text = [NSString stringWithFormat:@"%.0f", _camSlider.value];
    [_togglesCard addSubview:_camValueLabel];

    // ESP ELEMENTS card
    _espCard = [self makeCard];
    [_contentView addSubview:_espCard];
    _espCardTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    _espCardTitle.text = @"ESP ELEMENTS";
    _espCardTitle.font = VNFont(13, UIFontWeightBold);
    _espCardTitle.textColor = VNMuted();
    [_espCard addSubview:_espCardTitle];

    _espBoxLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espBoxLabel.text = @"Box";
    _espBoxLabel.font = VNFont(17, UIFontWeightSemibold);
    _espBoxLabel.textColor = VNText();
    [_espCard addSubview:_espBoxLabel];
    _espBoxSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espBoxSwitch.onTintColor = VNAccent();
    _espBoxSwitch.on = ESPPrefsBool(@"Box", YES);
    [_espBoxSwitch addTarget:self action:@selector(espBoxChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espBoxSwitch];

    _espLineLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espLineLabel.text = @"Snapline";
    _espLineLabel.font = VNFont(17, UIFontWeightSemibold);
    _espLineLabel.textColor = VNText();
    [_espCard addSubview:_espLineLabel];
    _espLineSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espLineSwitch.onTintColor = VNAccent();
    _espLineSwitch.on = ESPPrefsBool(@"Line", YES);
    [_espLineSwitch addTarget:self action:@selector(espLineChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espLineSwitch];

    _espBoneLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espBoneLabel.text = @"Bone / Skeleton";
    _espBoneLabel.font = VNFont(17, UIFontWeightSemibold);
    _espBoneLabel.textColor = VNText();
    [_espCard addSubview:_espBoneLabel];
    _espBoneSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espBoneSwitch.onTintColor = VNAccent();
    _espBoneSwitch.on = ESPPrefsBool(@"Bone", YES);
    [_espBoneSwitch addTarget:self action:@selector(espBoneChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espBoneSwitch];

    _espHealthLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espHealthLabel.text = @"Health Bar";
    _espHealthLabel.font = VNFont(17, UIFontWeightSemibold);
    _espHealthLabel.textColor = VNText();
    [_espCard addSubview:_espHealthLabel];
    _espHealthSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espHealthSwitch.onTintColor = VNAccent();
    _espHealthSwitch.on = ESPPrefsBool(@"Health", YES);
    [_espHealthSwitch addTarget:self action:@selector(espHealthChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espHealthSwitch];

    _espCountLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espCountLabel.text = @"Player Count";
    _espCountLabel.font = VNFont(17, UIFontWeightSemibold);
    _espCountLabel.textColor = VNText();
    [_espCard addSubview:_espCountLabel];
    _espCountSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espCountSwitch.onTintColor = VNAccent();
    _espCountSwitch.on = ESPPrefsBool(@"Count", YES);
    [_espCountSwitch addTarget:self action:@selector(espCountChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espCountSwitch];

    _espDistanceLimitLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espDistanceLimitLabel.text = @"Max Distance (m)";
    _espDistanceLimitLabel.font = VNFont(17, UIFontWeightSemibold);
    _espDistanceLimitLabel.textColor = VNText();
    [_espCard addSubview:_espDistanceLimitLabel];
    _espDistanceLimitValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espDistanceLimitValueLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightSemibold];
    _espDistanceLimitValueLabel.textColor = VNMuted();
    _espDistanceLimitValueLabel.textAlignment = NSTextAlignmentRight;
    _espDistanceLimitValueLabel.text = [NSString stringWithFormat:@"%.0f", ESPPrefsFloat(@"EspDistanceLimit", 150.0f)];
    [_espCard addSubview:_espDistanceLimitValueLabel];
    _espDistanceLimitSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _espDistanceLimitSlider.minimumValue = 20.0f;
    _espDistanceLimitSlider.maximumValue = 300.0f;
    _espDistanceLimitSlider.value = ESPPrefsFloat(@"EspDistanceLimit", 150.0f);
    _espDistanceLimitSlider.minimumTrackTintColor = VNAccent();
    [_espDistanceLimitSlider addTarget:self action:@selector(espDistanceLimitChanged:) forControlEvents:UIControlEventValueChanged];
    [_espDistanceLimitSlider addTarget:self action:@selector(espDistanceLimitCommitted:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [_espCard addSubview:_espDistanceLimitSlider];

    // Aimbot card
    _aimCard = [self makeCard];
    [_contentView addSubview:_aimCard];
    _fovLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _fovLabel.text = @"FOV size";
    _fovLabel.font = VNFont(17, UIFontWeightSemibold);
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
    _fovValueLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightSemibold];
    _fovValueLabel.textColor = VNMuted();
    _fovValueLabel.textAlignment = NSTextAlignmentRight;
    _fovValueLabel.text = [NSString stringWithFormat:@"%.0f", _fovSlider.value];
    [_aimCard addSubview:_fovValueLabel];

    _triggerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _triggerLabel.text = @"Trigger";
    _triggerLabel.font = VNFont(17, UIFontWeightSemibold);
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
    _aimPosLabel.font = VNFont(17, UIFontWeightSemibold);
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

    // Log card
    _logCard = [self makeCard];
    [_contentView addSubview:_logCard];
    _logTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    _logTextView.editable = NO;
    _logTextView.scrollEnabled = YES;
    _logTextView.showsHorizontalScrollIndicator = NO;
    _logTextView.backgroundColor = [UIColor colorWithWhite:0.97 alpha:1.0];
    _logTextView.layer.cornerRadius = 10.0f;
    _logTextView.layer.borderWidth = 1.0f;
    _logTextView.layer.borderColor = VNLine().CGColor;
    _logTextView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
    _logTextView.textColor = [UIColor colorWithRed:0.12 green:0.55 blue:0.22 alpha:1.0];
    _logTextView.text = @"[VN TOOL] ready.\nPress Bắt đầu to boot kernel.";
    [_logCard addSubview:_logTextView];

    // Version section
    _versionSectionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _versionSectionLabel.text = @"Lựa chọn phiên bản:";
    _versionSectionLabel.font = VNFont(14, UIFontWeightBold);
    _versionSectionLabel.textColor = VNMuted();
    [_contentView addSubview:_versionSectionLabel];

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

    // Status card
    _statusCard = [self makeCard];
    [_contentView addSubview:_statusCard];
    _statusDot = [[UIView alloc] initWithFrame:CGRectZero];
    _statusDot.layer.cornerRadius = 6.0f;
    _statusDot.backgroundColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    [_statusCard addSubview:_statusDot];
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.font = VNFont(16, UIFontWeightSemibold);
    _statusLabel.textColor = VNText();
    _statusLabel.text = @"Trạng thái · Game chưa chạy";
    [_statusCard addSubview:_statusLabel];
    _openGameButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _openGameButton.backgroundColor = VNAccent();
    _openGameButton.layer.cornerRadius = 12.0f;
    _openGameButton.titleLabel.font = VNFont(14, UIFontWeightBold);
    [_openGameButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_openGameButton setTitle:@"Vào Game" forState:UIControlStateNormal];
    [_openGameButton addTarget:self action:@selector(openGameTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_statusCard addSubview:_openGameButton];

    // License + auth
    _licenseCard = [self makeCard];
    [_contentView addSubview:_licenseCard];
    _licenseTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _licenseTitleLabel.text = @"Giấy phép";
    _licenseTitleLabel.font = VNFont(13, UIFontWeightBold);
    _licenseTitleLabel.textColor = VNMuted();
    [_licenseCard addSubview:_licenseTitleLabel];
    _licenseValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _licenseValueLabel.font = VNFont(17, UIFontWeightBold);
    _licenseValueLabel.textColor = VNText();
    _licenseValueLabel.numberOfLines = 3;
    _licenseValueLabel.text = @"—";
    [_licenseCard addSubview:_licenseValueLabel];

    _authCard = [self makeCard];
    [_contentView addSubview:_authCard];
    _authTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authTitleLabel.text = @"Trạng thái";
    _authTitleLabel.font = VNFont(13, UIFontWeightBold);
    _authTitleLabel.textColor = VNMuted();
    [_authCard addSubview:_authTitleLabel];
    _authValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authValueLabel.font = VNFont(18, UIFontWeightBold);
    _authValueLabel.textColor = VNAccent();
    _authValueLabel.numberOfLines = 2;
    _authValueLabel.text = @"—";
    [_authCard addSubview:_authValueLabel];

    // Support
    _supportCard = [self makeCard];
    [_contentView addSubview:_supportCard];
    _supportTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportTitleLabel.text = @"Liên hệ hỗ trợ";
    _supportTitleLabel.font = VNFont(17, UIFontWeightSemibold);
    _supportTitleLabel.textColor = VNText();
    [_supportCard addSubview:_supportTitleLabel];
    _supportSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportSubtitleLabel.text = @"Nhấn Join để nhận hỗ trợ";
    _supportSubtitleLabel.font = VNFont(13, UIFontWeightMedium);
    _supportSubtitleLabel.textColor = VNMuted();
    [_supportCard addSubview:_supportSubtitleLabel];
    _joinButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _joinButton.backgroundColor = VNAccent();
    _joinButton.layer.cornerRadius = 12.0f;
    _joinButton.titleLabel.font = VNFont(15, UIFontWeightBold);
    [_joinButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_joinButton setTitle:@"Join" forState:UIControlStateNormal];
    [_joinButton addTarget:self action:@selector(joinSupportTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_supportCard addSubview:_joinButton];

    // Extra
    _extraCard = [self makeCard];
    [_contentView addSubview:_extraCard];
    _autoCleanLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _autoCleanLabel.text = @"VarClean before HUD";
    _autoCleanLabel.font = VNFont(16, UIFontWeightSemibold);
    _autoCleanLabel.textColor = VNText();
    [_extraCard addSubview:_autoCleanLabel];
    _autoCleanSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _autoCleanSwitch.onTintColor = VNAccent();
    _autoCleanSwitch.on = ESPPrefsBool(@"AutoVarCleanBeforeHUD", NO);
    [_autoCleanSwitch addTarget:self action:@selector(autoCleanSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_extraCard addSubview:_autoCleanSwitch];
    _authorizationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authorizationLabel.font = VNFont(14, UIFontWeightSemibold);
    _authorizationLabel.textColor = VNText();
    [_extraCard addSubview:_authorizationLabel];
    _authorizationButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _authorizationButton.titleLabel.font = VNFont(14, UIFontWeightBold);
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

    CGFloat gear = 44.0f;
    _settingsBtn.frame = CGRectMake(width - insets.right - 16 - gear, insets.top + 8, gear, gear);

    CGFloat contentW = width;
    CGFloat xPad = 16.0f;
    CGFloat cardW = contentW - xPad * 2.0f;
    CGFloat y = insets.top + 62.0f;

    // ===== CONTROL =====
    CGFloat controlH = 100.0f;
    _controlCard.frame = CGRectMake(xPad, y, cardW, controlH);
    CGFloat iconSize = 64.0f;
    _controlIconView.frame = CGRectMake(14, (controlH - iconSize) * 0.5f, iconSize, iconSize);

    CGFloat btnW = 96;
    _startButton.frame = CGRectMake(cardW - btnW - 16, 18, btnW, 36);
    _killAllButton.frame = CGRectMake(cardW - btnW - 16, 60, btnW, 32);

    CGFloat textX = 14 + iconSize + 12;
    CGFloat textW = cardW - btnW - textX - 10;
    _controlTitleLabel.frame = CGRectMake(textX, 22, textW, 24);
    _controlSubtitleLabel.frame = CGRectMake(textX, 48, textW, 36);
    y = CGRectGetMaxY(_controlCard.frame) + 16;

    // ===== TOGGLES (5 rows + slider) =====
    CGFloat toggleRowH = 62.0f;
    CGFloat sliderAreaH = 82.0f;
    CGFloat togglesH = toggleRowH * 5 + sliderAreaH;
    _togglesCard.frame = CGRectMake(xPad, y, cardW, togglesH);

    CGFloat rowY = 0;
    _aimbotLabel.frame = CGRectMake(20, rowY, cardW - 110, toggleRowH);
    _aimbotSwitch.frame = CGRectMake(cardW - 71, rowY + (toggleRowH - 31) * 0.5f, 51, 31);
    rowY += toggleRowH;

    _aimBehindWallLabel.frame = CGRectMake(20, rowY, cardW - 110, toggleRowH);
    _aimBehindWallSwitch.frame = CGRectMake(cardW - 71, rowY + (toggleRowH - 31) * 0.5f, 51, 31);
    rowY += toggleRowH;

    _silentAimLabel.frame = CGRectMake(20, rowY, cardW - 110, toggleRowH);
    _silentAimSwitch.frame = CGRectMake(cardW - 71, rowY + (toggleRowH - 31) * 0.5f, 51, 31);
    rowY += toggleRowH;

    _espLabel.frame = CGRectMake(20, rowY, cardW - 110, toggleRowH);
    _espSwitch.frame = CGRectMake(cardW - 71, rowY + (toggleRowH - 31) * 0.5f, 51, 31);
    rowY += toggleRowH;

    _camLabel.frame = CGRectMake(20, rowY, cardW - 110, toggleRowH);
    _camSwitch.frame = CGRectMake(cardW - 71, rowY + (toggleRowH - 31) * 0.5f, 51, 31);
    rowY += toggleRowH;

    _camSlider.frame = CGRectMake(20, rowY + 24, cardW - 100, 30);
    _camValueLabel.frame = CGRectMake(cardW - 64, rowY + 26, 48, 26);
    y = CGRectGetMaxY(_togglesCard.frame) + 16;

    // ===== ESP ELEMENTS =====
    CGFloat espTitleH = 40.0f;
    CGFloat espRowH = 60.0f;
    CGFloat espSliderArea = 82.0f;
    CGFloat espH = espTitleH + espRowH * 5 + espSliderArea;
    _espCard.frame = CGRectMake(xPad, y, cardW, espH);
    _espCardTitle.frame = CGRectMake(20, 14, cardW - 40, 20);

    NSArray<UILabel *> *espLabelsArr = @[_espBoxLabel, _espLineLabel, _espBoneLabel,
                                          _espHealthLabel, _espCountLabel];
    NSArray<UISwitch *> *espSwitchesArr = @[_espBoxSwitch, _espLineSwitch, _espBoneSwitch,
                                             _espHealthSwitch, _espCountSwitch];
    CGFloat espY = espTitleH;
    for (NSUInteger i = 0; i < 5; i++) {
        UILabel *l = espLabelsArr[i];
        UISwitch *s = espSwitchesArr[i];
        l.frame = CGRectMake(20, espY, cardW - 110, espRowH);
        s.frame = CGRectMake(cardW - 71, espY + (espRowH - 31) * 0.5f, 51, 31);
        espY += espRowH;
    }
    _espDistanceLimitLabel.frame = CGRectMake(20, espY, cardW - 110, 30);
    _espDistanceLimitValueLabel.frame = CGRectMake(cardW - 64, espY, 48, 30);
    _espDistanceLimitSlider.frame = CGRectMake(20, espY + 34, cardW - 40, 30);
    y = CGRectGetMaxY(_espCard.frame) + 16;

    // ===== AIM =====
    CGFloat fovAreaH = 90.0f;
    CGFloat segAreaH = 100.0f;
    CGFloat aimH = fovAreaH + segAreaH * 2;
    _aimCard.frame = CGRectMake(xPad, y, cardW, aimH);

    _fovLabel.frame = CGRectMake(20, 18, 140, 24);
    _fovValueLabel.frame = CGRectMake(cardW - 64, 18, 48, 24);
    _fovSlider.frame = CGRectMake(20, 50, cardW - 40, 30);

    _triggerLabel.frame = CGRectMake(20, fovAreaH + 14, 140, 24);
    _triggerSegment.frame = CGRectMake(20, fovAreaH + 46, cardW - 40, 38);

    _aimPosLabel.frame = CGRectMake(20, fovAreaH + segAreaH + 14, 140, 24);
    _aimPosSegment.frame = CGRectMake(20, fovAreaH + segAreaH + 46, cardW - 40, 38);
    y = CGRectGetMaxY(_aimCard.frame) + 16;

    // ===== LOG =====
    CGFloat logH = 200.0f;
    _logCard.frame = CGRectMake(xPad, y, cardW, logH);
    _logTextView.frame = CGRectMake(10, 8, cardW - 20, logH - 16);
    y = CGRectGetMaxY(_logCard.frame) + 22;

    _versionSectionLabel.frame = CGRectMake(xPad + 4, y, cardW - 8, 22);
    y = CGRectGetMaxY(_versionSectionLabel.frame) + 10;

    CGFloat gap = 12.0f;
    CGFloat versionW = (cardW - gap) * 0.5f;
    CGFloat versionH = 136.0f;
    _ffMaxCard.frame = CGRectMake(xPad, y, versionW, versionH);
    _ffCard.frame = CGRectMake(xPad + versionW + gap, y, versionW, versionH);
    CGFloat iconSide = 68.0f;
    _ffMaxIconView.frame = CGRectMake((versionW - iconSide) * 0.5f, 20, iconSide, iconSide);
    _ffIconView.frame = CGRectMake((versionW - iconSide) * 0.5f, 20, iconSide, iconSide);
    _ffMaxNameLabel.frame = CGRectMake(8, 96, versionW - 16, 24);
    _ffNameLabel.frame = CGRectMake(8, 96, versionW - 16, 24);
    y = CGRectGetMaxY(_ffMaxCard.frame) + 16;

    // ===== STATUS =====
    CGFloat statusH = 72.0f;
    _statusCard.frame = CGRectMake(xPad, y, cardW, statusH);
    _statusDot.frame = CGRectMake(20, (statusH - 12) * 0.5f, 12, 12);
    _openGameButton.frame = CGRectMake(cardW - 116, (statusH - 38) * 0.5f, 100, 38);
    _statusLabel.frame = CGRectMake(42, 0, cardW - 116 - 50, statusH);
    y = CGRectGetMaxY(_statusCard.frame) + 16;

    // ===== INFO =====
    CGFloat infoH = 60.0f;
    _licenseCard.frame = CGRectMake(xPad, y, cardW, infoH);
    _licenseTitleLabel.frame = CGRectMake(20, 0, cardW/2, infoH);
    _licenseValueLabel.frame = CGRectMake(cardW/2, 0, cardW/2 - 20, infoH);
    y = CGRectGetMaxY(_licenseCard.frame) + 1;

    _authCard.frame = CGRectMake(xPad, y, cardW, infoH);
    _authTitleLabel.frame = CGRectMake(20, 0, cardW/2, infoH);
    _authValueLabel.frame = CGRectMake(cardW/2, 0, cardW/2 - 20, infoH);
    y = CGRectGetMaxY(_authCard.frame) + 16;

    // ===== SUPPORT =====
    CGFloat supportH = 80.0f;
    _supportCard.frame = CGRectMake(xPad, y, cardW, supportH);
    _joinButton.frame = CGRectMake(cardW - 96, (supportH - 38) * 0.5f, 80, 38);
    _supportTitleLabel.frame = CGRectMake(20, 20, cardW - 130, 26);
    _supportSubtitleLabel.frame = CGRectMake(20, 48, cardW - 130, 20);
    y = CGRectGetMaxY(_supportCard.frame) + 16;

    // ===== EXTRA =====
    CGFloat extraH = 104.0f;
    _extraCard.frame = CGRectMake(xPad, y, cardW, extraH);
    _autoCleanLabel.frame = CGRectMake(20, 18, cardW - 100, 26);
    CGSize sw = _autoCleanSwitch.intrinsicContentSize;
    _autoCleanSwitch.frame = CGRectMake(cardW - sw.width - 20, 18, sw.width, sw.height);
    _authorizationLabel.frame = CGRectMake(20, 58, cardW - 170, 30);
    _authorizationButton.frame = CGRectMake(cardW - 140, 58, 120, 30);
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

    _ffMaxCard.layer.borderWidth = 2.5f;
    _ffCard.layer.borderWidth = 2.5f;
    _ffMaxCard.layer.borderColor = (isMax ? selected : [UIColor clearColor]).CGColor;
    _ffCard.layer.borderColor = (!isMax ? selected : [UIColor clearColor]).CGColor;
    _ffMaxCard.backgroundColor = isMax ? VNPanel2() : VNCard();
    _ffCard.backgroundColor = !isMax ? VNPanel2() : VNCard();

    UIImage *icon = [self imageNamedWebPOrPNG:isMax ? @"ffmax" : @"ff"];
    if (icon) _controlIconView.image = icon;
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

- (void)silentAimSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"AimSilent", sender.on);
    ESPSyncFromPrefs();
    NSLog(@"[VN] AimSilent set to %d", (int)sender.on);
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

#pragma mark - ESP element toggles
- (void)espBoxChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Box", sender.on);
    ESPSyncFromPrefs();
}
- (void)espLineChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Line", sender.on);
    ESPSyncFromPrefs();
}
- (void)espBoneChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Bone", sender.on);
    ESPSyncFromPrefs();
}
- (void)espHealthChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Health", sender.on);
    ESPSyncFromPrefs();
}
- (void)espCountChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Count", sender.on);
    ESPSyncFromPrefs();
}

- (void)espDistanceLimitChanged:(UISlider *)sender {
    float v = sender.value;
    _espDistanceLimitValueLabel.text = [NSString stringWithFormat:@"%.0f", v];
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
    NSLog(@"[VN] TriggerMode set to %.0f", v);
}

- (void)aimPosSegmentChanged:(UISegmentedControl *)sender {
    float v = (float)sender.selectedSegmentIndex;
    NSUserDefaults *std = [NSUserDefaults standardUserDefaults];
    [std setFloat:v forKey:@"AimPos"];
    [std setFloat:v forKey:@"AimPos_Lite"];
    [std synchronize];
    ESPPrefsSetFloat(@"AimPos", v);
    ESPSyncFromPrefs();
    NSLog(@"[VN] AimPos set to %.0f", v);
}

- (void)aimBehindWallSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"AimBehindWall", sender.on);
    ESPSyncFromPrefs();
}

#pragma mark - Start / Kill All

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
    NSURL *url = [NSURL URLWithString:@"https://t.me/vntool"];
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
        _startButton.backgroundColor = VNAccent();
        return;
    }

    _startButton.enabled = YES;
    _startButton.alpha = 1.0;
    _controlSubtitleLabel.alpha = 1.0;

    CFTimeInterval now = CACurrentMediaTime();
    BOOL isWithinEnableGracePeriod = _pendingHUDEnableUntil > 0 && now < _pendingHUDEnableUntil;
    if (!hudIsEnabled && isWithinEnableGracePeriod) {
        [_startButton setTitle:@"Đang bật…" forState:UIControlStateNormal];
        _startButton.backgroundColor = VNAccentDim();
        return;
    }

    if (hudIsEnabled) {
        _pendingHUDEnableUntil = 0;
        [_startButton setTitle:@"Tắt HUD" forState:UIControlStateNormal];
        _startButton.backgroundColor = VNPanel2();
    } else {
        [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
        _startButton.backgroundColor = VNAccent();
    }
}

@end
