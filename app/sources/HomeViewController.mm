#import "HomeViewController.h"
#import "HUDHelper.h"
#import "rootless.h"
#import "pid.h"
#import "ESPPrefs.h"
#import "esp.h"
#import "GameOffsets.h"
#import "roothide/varCleanController.h"
#import "MDTheme.h"
#import "AppSettingsViewController.h"
#import "../KernelBoot.h"

#import <QuartzCore/QuartzCore.h>
#import <SafariServices/SafariServices.h>

static HomeViewController *g_activeLogVC = nil;
static void HomeVCBootLogSink(NSString *line);

static const CGFloat kMenuButtonSize = 56.0f;

@interface HomeViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *titleLabel;

// Control
@property (nonatomic, strong) UIView *controlCard;
@property (nonatomic, strong) UIImageView *controlIconView;
@property (nonatomic, strong) UILabel *controlTitleLabel;
@property (nonatomic, strong) UILabel *controlSubtitleLabel;
@property (nonatomic, strong) UIButton *startButton;

// ESP
@property (nonatomic, strong) UIView *espCard;
@property (nonatomic, strong) UILabel *espTitleLabel;
@property (nonatomic, strong) UISwitch *espSwitch;
@property (nonatomic, strong) UISwitch *espBoxSwitch, *espBoneSwitch, *espNameSwitch, *espDistSwitch;
@property (nonatomic, strong) UISwitch *espLineSwitch, *espHealthSwitch, *espCountSwitch, *espWeaponSwitch;
@property (nonatomic, strong) UISwitch *espAlert360Switch, *espAlertNumSwitch, *espCheckVisSwitch, *espBotSwitch;

// AIM
@property (nonatomic, strong) UIView *aimCard;
@property (nonatomic, strong) UILabel *aimTitleLabel;
@property (nonatomic, strong) UISwitch *aimbotSwitch;
@property (nonatomic, strong) UISegmentedControl *aimPosSegment;
@property (nonatomic, strong) UISegmentedControl *triggerSegment;
@property (nonatomic, strong) UISwitch *aimSilentSwitch;
@property (nonatomic, strong) UISwitch *aimAssistSwitch;
@property (nonatomic, strong) UISlider *aimFovSlider;
@property (nonatomic, strong) UILabel *aimFovValueLabel;
@property (nonatomic, strong) UISlider *aimDistanceSlider;
@property (nonatomic, strong) UILabel *aimDistanceValueLabel;

// MOVE
@property (nonatomic, strong) UIView *moveCard;
@property (nonatomic, strong) UILabel *moveTitleLabel;
@property (nonatomic, strong) UISwitch *brutalSwitch;
@property (nonatomic, strong) UISwitch *speedSwitch;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel *speedValueLabel;
@property (nonatomic, strong) UISwitch *fastReloadSwitch;
@property (nonatomic, strong) UISlider *fastReloadSlider;
@property (nonatomic, strong) UILabel *fastReloadValueLabel;

// CAM
@property (nonatomic, strong) UIView *camCard;
@property (nonatomic, strong) UILabel *camTitleLabel;
@property (nonatomic, strong) UISwitch *camSwitch;
@property (nonatomic, strong) UISlider *camSlider;
@property (nonatomic, strong) UILabel *camValueLabel;

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

// License / auth
@property (nonatomic, strong) UIView *licenseCard;
@property (nonatomic, strong) UILabel *licenseTitleLabel;
@property (nonatomic, strong) UILabel *licenseValueLabel;
@property (nonatomic, strong) UIView *authCard;
@property (nonatomic, strong) UILabel *authTitleLabel;
@property (nonatomic, strong) UILabel *authValueLabel;

// Support
@property (nonatomic, strong) UIView *supportCard;
@property (nonatomic, strong) UILabel *supportTitleLabel;
@property (nonatomic, strong) UILabel *supportSubtitleLabel;
@property (nonatomic, strong) UIButton *joinButton;

// Extra
@property (nonatomic, strong) UIView *extraCard;
@property (nonatomic, strong) UILabel *autoCleanLabel;
@property (nonatomic, strong) UISwitch *autoCleanSwitch;
@property (nonatomic, strong) UILabel *authorizationLabel;
@property (nonatomic, strong) UIButton *authorizationButton;
@property (nonatomic, strong) UIButton *settingsBtn;
@property (nonatomic, strong) UIView *logCard;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UIButton *trashBtn;

@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) NSInteger gameMissingStreak;
@property (nonatomic, assign) CFTimeInterval pendingHUDEnableUntil;
@property (nonatomic, assign) NSInteger hudRequestSerial;
@end

@implementation HomeViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    MDThemeLoadFromPrefs();
    [self buildUI];
    _gameMissingStreak = 0;
    _pendingHUDEnableUntil = 0;
    _hudRequestSerial = 0;

    GameOffsetsReload();
    [self updateVersionSelectionUI];
    [self updateAuthorizationPresentation];
    [self refreshHUDState];
    [self applyTheme];
    [self syncAllSwitchesFromPrefs];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appBecameActive)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme)
                                                 name:MDThemeDidChangeNotification object:nil];
    [self startPollingGameState];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_pollTimer invalidate];
}

#pragma mark - Helpers

- (UIColor *)cardBackground { return MDThemePanel(); }
- (UIColor *)accentGreen  { return MDThemeAccent(); }
- (UIColor *)accentBlue   { return MDThemeBlue(); }
- (UIColor *)accentOrange { return MDThemeOrange(); }

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

- (void)applyTheme {
    MDThemeLoadFromPrefs();
    self.view.backgroundColor = MDThemeBg();
    _titleLabel.textColor = MDThemeText();
    _titleLabel.font = MDThemeFont(30, UIFontWeightBold);

    for (UIView *card in @[_controlCard, _espCard, _aimCard, _moveCard, _camCard, _statusCard,
                            _licenseCard, _authCard, _supportCard, _extraCard]) {
        card.backgroundColor = MDThemePanel();
        card.layer.borderColor = MDThemeLine().CGColor;
        card.layer.borderWidth = 1.0f;
    }
    _controlTitleLabel.textColor = MDThemeText();
    _controlSubtitleLabel.textColor = MDThemeMuted();
    _startButton.backgroundColor = MDThemeAccent();
    _espTitleLabel.textColor = MDThemeText();
    _aimTitleLabel.textColor = MDThemeText();
    _moveTitleLabel.textColor = MDThemeText();
    _camTitleLabel.textColor = MDThemeText();

    NSArray *allSwitches = @[_espSwitch, _espBoxSwitch, _espBoneSwitch, _espNameSwitch, _espDistSwitch,
                              _espLineSwitch, _espHealthSwitch, _espCountSwitch, _espWeaponSwitch,
                              _espAlert360Switch, _espAlertNumSwitch, _espCheckVisSwitch, _espBotSwitch,
                              _aimbotSwitch, _aimSilentSwitch, _aimAssistSwitch,
                              _brutalSwitch, _speedSwitch, _fastReloadSwitch,
                              _camSwitch, _autoCleanSwitch];
    for (UISwitch *sw in allSwitches) sw.onTintColor = MDThemeAccent();

    _aimFovValueLabel.textColor = MDThemeMuted();
    _aimDistanceValueLabel.textColor = MDThemeMuted();
    _speedValueLabel.textColor = MDThemeMuted();
    _fastReloadValueLabel.textColor = MDThemeMuted();
    _camValueLabel.textColor = MDThemeMuted();

    _versionSectionLabel.textColor = MDThemeMuted();
    _ffMaxNameLabel.textColor = MDThemeText();
    _ffNameLabel.textColor = MDThemeText();
    _statusLabel.textColor = MDThemeText();
    _openGameButton.backgroundColor = MDThemeOrange();
    _licenseTitleLabel.textColor = MDThemeMuted();
    _licenseValueLabel.textColor = MDThemeText();
    _authTitleLabel.textColor = MDThemeMuted();
    _supportTitleLabel.textColor = MDThemeText();
    _supportSubtitleLabel.textColor = MDThemeMuted();
    _joinButton.backgroundColor = MDThemeBlue();
    _autoCleanLabel.textColor = MDThemeText();
    [_authorizationButton setTitleColor:MDThemeAccent() forState:UIControlStateNormal];

    _settingsBtn.backgroundColor = MDThemePanel2();
    _settingsBtn.layer.borderColor = MDThemeLine().CGColor;
    _settingsBtn.tintColor = MDThemeText();
    _trashBtn.backgroundColor = MDThemePanel2();
    _trashBtn.layer.borderColor = MDThemeLine().CGColor;
    _trashBtn.tintColor = MDThemeText();

    if (self.tabBarController) MDThemeApplyToTabBar(self.tabBarController.tabBar);
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
    if (path.length) img = [UIImage imageWithContentsOfFile:path];
    return img;
}

- (UIView *)makeCard { return MDThemeMakeCard(); }

- (UILabel *)makeRowLabel:(NSString *)text {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    l.textColor = [UIColor whiteColor];
    return l;
}

- (UILabel *)makeSubLabel:(NSString *)text {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    l.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    return l;
}

- (UISwitch *)makeSwitchOn:(BOOL)on action:(SEL)action {
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.onTintColor = [self accentGreen];
    sw.on = on;
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (UISlider *)makeSliderMin:(float)min max:(float)max val:(float)val action:(SEL)action {
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectZero];
    s.minimumValue = min;
    s.maximumValue = max;
    s.value = val;
    s.minimumTrackTintColor = [self accentGreen];
    [s addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return s;
}

- (UILabel *)makeValueLabel:(float)val {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    l.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    l.text = [NSString stringWithFormat:@"%.0f", val];
    l.textAlignment = NSTextAlignmentRight;
    return l;
}

#pragma mark - Authorization

- (void)beginAuthorization { [self updateAuthorizationPresentation]; [self refreshHUDState]; }
- (void)retryAuthorization:(id)sender { (void)sender; [self beginAuthorization]; }
- (void)revokeAuthorization { SetHUDEnabled(NO); [self updateAuthorizationPresentation]; [self refreshHUDState]; }

- (void)updateAuthorizationPresentation {
    if (!self.isViewLoaded) return;
    _authorizationLabel.text = @"No key required";
    [_authorizationButton setTitle:@"Unlocked" forState:UIControlStateNormal];
    _authorizationButton.enabled = NO;
    _licenseValueLabel.text = @"Unlimited";
    _authValueLabel.text = @"Hoạt động";
    _authValueLabel.textColor = MDThemeAccent();
    _authorizationLabel.textColor = MDThemeText();
    _autoCleanSwitch.enabled = YES;
    _autoCleanLabel.alpha = 1.0;
    _startButton.alpha = 1.0;
}

#pragma mark - Build UI (tất cả trong 1 hàm)

- (void)buildUI {
    self.view.backgroundColor = MDThemeBg();

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:_scrollView];

    _contentView = [[UIView alloc] initWithFrame:CGRectZero];
    [_scrollView addSubview:_contentView];

    _settingsBtn = MDThemeMakeSettingsButton(self, @selector(openSettings));
    _trashBtn = MDThemeMakeTrashButton(self, @selector(openVarClean));
    [self.view addSubview:_settingsBtn];
    [self.view addSubview:_trashBtn];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.text = @"Trang chủ";
    _titleLabel.font = MDThemeFont(30, UIFontWeightBold);
    _titleLabel.textColor = MDThemeText();
    [_contentView addSubview:_titleLabel];

    // ===================== CONTROL CARD =====================
    _controlCard = [self makeCard];
    [_contentView addSubview:_controlCard];

    _controlIconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _controlIconView.contentMode = UIViewContentModeScaleAspectFill;
    _controlIconView.clipsToBounds = YES;
    _controlIconView.layer.cornerRadius = 12.0f;
    _controlIconView.image = [self imageNamedWebPOrPNG:@"ff"] ?: [UIImage imageNamed:@"logo"];
    _controlIconView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    [_controlCard addSubview:_controlIconView];

    _controlTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _controlTitleLabel.text = @"Điều khiển HUD";
    _controlTitleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _controlTitleLabel.textColor = [UIColor whiteColor];
    [_controlCard addSubview:_controlTitleLabel];

    _controlSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _controlSubtitleLabel.text = @"Nhấn Bắt đầu khi game đã mở";
    _controlSubtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _controlSubtitleLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    _controlSubtitleLabel.numberOfLines = 2;
    [_controlCard addSubview:_controlSubtitleLabel];

    _startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _startButton.backgroundColor = [self accentGreen];
    _startButton.layer.cornerRadius = 16.0f;
    _startButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
    [_startButton addTarget:self action:@selector(startButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_controlCard addSubview:_startButton];

    // ===================== ESP CARD =====================
    _espCard = [self makeCard];
    [_contentView addSubview:_espCard];
    _espTitleLabel = [self makeRowLabel:@"ESP"];
    [_espCard addSubview:_espTitleLabel];
    _espSwitch = [self makeSwitchOn:ESPPrefsBool(@"EnableESP", YES) action:@selector(espSwitchChanged:)];
    [_espCard addSubview:_espSwitch];

    _espBoxSwitch    = [self makeSwitchOn:ESPPrefsBool(@"Box", YES) action:@selector(espSubSwitchChanged:)];
    _espBoneSwitch   = [self makeSwitchOn:ESPPrefsBool(@"Bone", YES) action:@selector(espSubSwitchChanged:)];
    _espNameSwitch   = [self makeSwitchOn:ESPPrefsBool(@"Name", YES) action:@selector(espSubSwitchChanged:)];
    _espDistSwitch   = [self makeSwitchOn:ESPPrefsBool(@"Distance", YES) action:@selector(espSubSwitchChanged:)];
    _espLineSwitch   = [self makeSwitchOn:ESPPrefsBool(@"Line", YES) action:@selector(espSubSwitchChanged:)];
    _espHealthSwitch = [self makeSwitchOn:ESPPrefsBool(@"Health", YES) action:@selector(espSubSwitchChanged:)];
    _espCountSwitch  = [self makeSwitchOn:ESPPrefsBool(@"Count", YES) action:@selector(espSubSwitchChanged:)];
    _espWeaponSwitch = [self makeSwitchOn:ESPPrefsBool(@"Weapon", NO) action:@selector(espSubSwitchChanged:)];
    _espAlert360Switch = [self makeSwitchOn:ESPPrefsBool(@"Alert360", NO) action:@selector(espSubSwitchChanged:)];
    _espAlertNumSwitch = [self makeSwitchOn:ESPPrefsBool(@"AlertNum", NO) action:@selector(espSubSwitchChanged:)];
    _espCheckVisSwitch = [self makeSwitchOn:ESPPrefsBool(@"EspCheckVisible", NO) action:@selector(espSubSwitchChanged:)];
    _espBotSwitch      = [self makeSwitchOn:ESPPrefsBool(@"EspBot", NO) action:@selector(espSubSwitchChanged:)];
    for (UISwitch *sw in @[_espBoxSwitch, _espBoneSwitch, _espNameSwitch, _espDistSwitch,
                            _espLineSwitch, _espHealthSwitch, _espCountSwitch, _espWeaponSwitch,
                            _espAlert360Switch, _espAlertNumSwitch, _espCheckVisSwitch, _espBotSwitch]) {
        [_espCard addSubview:sw];
    }

    // ===================== AIM CARD =====================
    _aimCard = [self makeCard];
    [_contentView addSubview:_aimCard];
    _aimTitleLabel = [self makeRowLabel:@"AIM"];
    [_aimCard addSubview:_aimTitleLabel];
    _aimbotSwitch = [self makeSwitchOn:ESPPrefsBool(@"Aimbot", NO) action:@selector(aimbotSwitchChanged:)];
    [_aimCard addSubview:_aimbotSwitch];

    _aimPosSegment = [[UISegmentedControl alloc] initWithItems:@[@"Đầu", @"Cổ", @"Thân"]];
    _aimPosSegment.selectedSegmentIndex = (NSInteger)ESPPrefsFloat(@"AimPos", 0.0f);
    _aimPosSegment.selectedSegmentTintColor = [self accentGreen];
    [_aimPosSegment addTarget:self action:@selector(aimPosChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimPosSegment];

    _triggerSegment = [[UISegmentedControl alloc] initWithItems:@[@"Auto", @"Bắn", @"Ngắm", @"Cả hai"]];
    _triggerSegment.selectedSegmentIndex = (NSInteger)ESPPrefsFloat(@"TriggerMode", 0.0f);
    _triggerSegment.selectedSegmentTintColor = [self accentGreen];
    [_triggerSegment addTarget:self action:@selector(triggerChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_triggerSegment];

    _aimSilentSwitch = [self makeSwitchOn:ESPPrefsBool(@"AimSilent", NO) action:@selector(aimSilentSwitchChanged:)];
    [_aimCard addSubview:_aimSilentSwitch];
    _aimAssistSwitch = [self makeSwitchOn:ESPPrefsBool(@"AimAssist", NO) action:@selector(aimAssistSwitchChanged:)];
    [_aimCard addSubview:_aimAssistSwitch];

    _aimFovSlider = [self makeSliderMin:30.0f max:360.0f val:ESPPrefsFloat(@"Fov", 150.0f) action:@selector(aimFovChanged:)];
    [_aimCard addSubview:_aimFovSlider];
    _aimFovValueLabel = [self makeValueLabel:ESPPrefsFloat(@"Fov", 150.0f)];
    [_aimCard addSubview:_aimFovValueLabel];

    _aimDistanceSlider = [self makeSliderMin:20.0f max:500.0f val:ESPPrefsFloat(@"Distance", 200.0f) action:@selector(aimDistanceChanged:)];
    [_aimCard addSubview:_aimDistanceSlider];
    _aimDistanceValueLabel = [self makeValueLabel:ESPPrefsFloat(@"Distance", 200.0f)];
    [_aimCard addSubview:_aimDistanceValueLabel];

    // ===================== MOVE CARD =====================
    _moveCard = [self makeCard];
    [_contentView addSubview:_moveCard];
    _moveTitleLabel = [self makeRowLabel:@"MOVEMENT"];
    [_moveCard addSubview:_moveTitleLabel];
    _brutalSwitch = [self makeSwitchOn:ESPPrefsBool(@"Norecoil", NO) action:@selector(brutalSwitchChanged:)];
    [_moveCard addSubview:_brutalSwitch];
    _speedSwitch = [self makeSwitchOn:ESPPrefsBool(@"Speed", NO) action:@selector(speedSwitchChanged:)];
    [_moveCard addSubview:_speedSwitch];
    _speedSlider = [self makeSliderMin:1.0f max:1.45f val:ESPPrefsFloat(@"SpeedValue", 1.22f) action:@selector(speedSliderChanged:)];
    [_moveCard addSubview:_speedSlider];
    _speedValueLabel = [self makeValueLabel:ESPPrefsFloat(@"SpeedValue", 1.22f)];
    [_moveCard addSubview:_speedValueLabel];

    _fastReloadSwitch = [self makeSwitchOn:ESPPrefsBool(@"FastReload", NO) action:@selector(fastReloadSwitchChanged:)];
    [_moveCard addSubview:_fastReloadSwitch];
    _fastReloadSlider = [self makeSliderMin:1.0f max:5.0f val:ESPPrefsFloat(@"FastReloadSpeed", 1.0f) action:@selector(fastReloadSliderChanged:)];
    [_moveCard addSubview:_fastReloadSlider];
    _fastReloadValueLabel = [self makeValueLabel:ESPPrefsFloat(@"FastReloadSpeed", 1.0f)];
    [_moveCard addSubview:_fastReloadValueLabel];

    // ===================== CAM CARD =====================
    _camCard = [self makeCard];
    [_contentView addSubview:_camCard];
    _camTitleLabel = [self makeRowLabel:@"CAMERA XA (CamPC)"];
    [_camCard addSubview:_camTitleLabel];
    _camSwitch = [self makeSwitchOn:ESPPrefsBool(@"CamPC", NO) action:@selector(camSwitchChanged:)];
    [_camCard addSubview:_camSwitch];
    _camSlider = [self makeSliderMin:0.0f max:150.0f val:ESPPrefsFloat(@"CamPCValue", 30.0f) action:@selector(camSliderChanged:)];
    [_camCard addSubview:_camSlider];
    _camValueLabel = [self makeValueLabel:ESPPrefsFloat(@"CamPCValue", 30.0f)];
    [_camCard addSubview:_camValueLabel];

    // ===================== LOG CARD =====================
    _logCard = [self makeCard];
    [_contentView addSubview:_logCard];
    _logTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    _logTextView.editable = NO;
    _logTextView.scrollEnabled = YES;
    _logTextView.showsHorizontalScrollIndicator = NO;
    _logTextView.backgroundColor = [UIColor colorWithRed:0.02 green:0.05 blue:0.03 alpha:1.0];
    _logTextView.layer.cornerRadius = 10.0f;
    _logTextView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _logTextView.textColor = [UIColor colorWithRed:0.55 green:0.95 blue:0.6 alpha:1.0];
    _logTextView.text = @"[MINHDUC] ready.\nPress Bắt đầu to boot kernel.";
    [_logCard addSubview:_logTextView];

    // ===================== VERSION =====================
    _versionSectionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _versionSectionLabel.text = @"Lựa chọn phiên bản:";
    _versionSectionLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _versionSectionLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    [_contentView addSubview:_versionSectionLabel];

    _ffMaxCard = [self makeVersionCardCapturingIcon:&_ffMaxIconView nameLabel:&_ffMaxNameLabel];
    _ffMaxIconView.image = [self imageNamedWebPOrPNG:@"ffmax"] ?: [UIImage imageNamed:@"logo"];
    _ffMaxNameLabel.text = @"Free Fire MAX";
    _ffMaxCard.tag = 2;
    [_ffMaxCard addTarget:self action:@selector(versionCardTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_ffMaxCard];

    _ffCard = [self makeVersionCardCapturingIcon:&_ffIconView nameLabel:&_ffNameLabel];
    _ffIconView.image = [self imageNamedWebPOrPNG:@"ff"] ?: [UIImage imageNamed:@"logo"];
    _ffNameLabel.text = @"Free Fire";
    _ffCard.tag = 1;
    [_ffCard addTarget:self action:@selector(versionCardTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_ffCard];

    // ===================== STATUS =====================
    _statusCard = [self makeCard];
    [_contentView addSubview:_statusCard];
    _statusDot = [[UIView alloc] initWithFrame:CGRectZero];
    _statusDot.layer.cornerRadius = 5.0f;
    _statusDot.backgroundColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    [_statusCard addSubview:_statusDot];
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _statusLabel.textColor = [UIColor whiteColor];
    _statusLabel.text = @"Trạng thái · Game chưa chạy";
    [_statusCard addSubview:_statusLabel];
    _openGameButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _openGameButton.backgroundColor = [self accentOrange];
    _openGameButton.layer.cornerRadius = 14.0f;
    _openGameButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [_openGameButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_openGameButton setTitle:@"Vào Game" forState:UIControlStateNormal];
    [_openGameButton addTarget:self action:@selector(openGameTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_statusCard addSubview:_openGameButton];

    // ===================== LICENSE / AUTH =====================
    _licenseCard = [self makeCard];
    [_contentView addSubview:_licenseCard];
    _licenseTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _licenseTitleLabel.text = @"Giấy phép";
    _licenseTitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _licenseTitleLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    [_licenseCard addSubview:_licenseTitleLabel];
    _licenseValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _licenseValueLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _licenseValueLabel.textColor = [UIColor whiteColor];
    _licenseValueLabel.numberOfLines = 3;
    _licenseValueLabel.text = @"—";
    [_licenseCard addSubview:_licenseValueLabel];

    _authCard = [self makeCard];
    [_contentView addSubview:_authCard];
    _authTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authTitleLabel.text = @"Trạng thái";
    _authTitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _authTitleLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    [_authCard addSubview:_authTitleLabel];
    _authValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authValueLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _authValueLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    _authValueLabel.numberOfLines = 2;
    _authValueLabel.text = @"—";
    [_authCard addSubview:_authValueLabel];

    // ===================== SUPPORT =====================
    _supportCard = [self makeCard];
    [_contentView addSubview:_supportCard];
    _supportTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportTitleLabel.text = @"Liên hệ hỗ trợ";
    _supportTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _supportTitleLabel.textColor = [UIColor whiteColor];
    [_supportCard addSubview:_supportTitleLabel];
    _supportSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportSubtitleLabel.text = @"Nhấn Join để nhận hỗ trợ";
    _supportSubtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _supportSubtitleLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    [_supportCard addSubview:_supportSubtitleLabel];
    _joinButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _joinButton.backgroundColor = [self accentBlue];
    _joinButton.layer.cornerRadius = 14.0f;
    _joinButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [_joinButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_joinButton setTitle:@"Join" forState:UIControlStateNormal];
    [_joinButton addTarget:self action:@selector(joinSupportTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_supportCard addSubview:_joinButton];

    // ===================== EXTRA =====================
    _extraCard = [self makeCard];
    [_contentView addSubview:_extraCard];
    _autoCleanLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _autoCleanLabel.text = @"VarClean before HUD";
    _autoCleanLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _autoCleanLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1.0f];
    [_extraCard addSubview:_autoCleanLabel];
    _autoCleanSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _autoCleanSwitch.onTintColor = MDThemeAccent();
    _autoCleanSwitch.on = ESPPrefsBool(@"AutoVarCleanBeforeHUD", NO);
    [_autoCleanSwitch addTarget:self action:@selector(autoCleanSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_extraCard addSubview:_autoCleanSwitch];
    _authorizationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authorizationLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _authorizationLabel.textAlignment = NSTextAlignmentLeft;
    [_extraCard addSubview:_authorizationLabel];
    _authorizationButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _authorizationButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [_authorizationButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_authorizationButton addTarget:self action:@selector(retryAuthorization:) forControlEvents:UIControlEventTouchUpInside];
    [_extraCard addSubview:_authorizationButton];

    // ===== Nhãn phụ trong AIM/MOVE/CAM (add 1 lần) =====
    [self addAimMoveCamLabels];
}

- (void)addAimMoveCamLabels {
    // AIM labels
    UILabel *aimbotLbl = [self makeRowLabel:@"Aimbot"];
    aimbotLbl.tag = 2000;
    [_aimCard addSubview:aimbotLbl];

    UILabel *silentLbl = [self makeSubLabel:@"Silent"];
    silentLbl.tag = 2001;
    [_aimCard addSubview:silentLbl];

    UILabel *assistLbl = [self makeSubLabel:@"Assist"];
    assistLbl.tag = 2002;
    [_aimCard addSubview:assistLbl];

    UILabel *fovLbl = [self makeSubLabel:@"FOV"];
    fovLbl.tag = 2003;
    [_aimCard addSubview:fovLbl];

    UILabel *distLbl = [self makeSubLabel:@"Range"];
    distLbl.tag = 2004;
    [_aimCard addSubview:distLbl];

    // MOVE labels
    UILabel *brutalLbl = [self makeRowLabel:@"Brutal (Norecoil)"];
    brutalLbl.tag = 3000;
    [_moveCard addSubview:brutalLbl];

    UILabel *speedLbl = [self makeRowLabel:@"Speed"];
    speedLbl.tag = 3001;
    [_moveCard addSubview:speedLbl];

    UILabel *frLbl = [self makeRowLabel:@"Fast Reload"];
    frLbl.tag = 3002;
    [_moveCard addSubview:frLbl];
}

- (UIButton *)makeVersionCardCapturingIcon:(UIImageView * __strong *)outIcon
                                 nameLabel:(UILabel * __strong *)outName {
    UIButton *card = [UIButton buttonWithType:UIButtonTypeCustom];
    card.backgroundColor = [self cardBackground];
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
    name.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    name.textColor = [UIColor whiteColor];
    name.textAlignment = NSTextAlignmentCenter;
    name.userInteractionEnabled = NO;
    [card addSubview:name];

    if (outIcon) *outIcon = icon;
    if (outName) *outName = name;
    return card;
}

#pragma mark - Sync + Actions

- (void)syncAllSwitchesFromPrefs {
    _espSwitch.on = ESPPrefsBool(@"EnableESP", YES);
    _espBoxSwitch.on = ESPPrefsBool(@"Box", YES);
    _espBoneSwitch.on = ESPPrefsBool(@"Bone", YES);
    _espNameSwitch.on = ESPPrefsBool(@"Name", YES);
    _espDistSwitch.on = ESPPrefsBool(@"Distance", YES);
    _espLineSwitch.on = ESPPrefsBool(@"Line", YES);
    _espHealthSwitch.on = ESPPrefsBool(@"Health", YES);
    _espCountSwitch.on = ESPPrefsBool(@"Count", YES);
    _espWeaponSwitch.on = ESPPrefsBool(@"Weapon", NO);
    _espAlert360Switch.on = ESPPrefsBool(@"Alert360", NO);
    _espAlertNumSwitch.on = ESPPrefsBool(@"AlertNum", NO);
    _espCheckVisSwitch.on = ESPPrefsBool(@"EspCheckVisible", NO);
    _espBotSwitch.on = ESPPrefsBool(@"EspBot", NO);

    _aimbotSwitch.on = ESPPrefsBool(@"Aimbot", NO);
    _aimSilentSwitch.on = ESPPrefsBool(@"AimSilent", NO);
    _aimAssistSwitch.on = ESPPrefsBool(@"AimAssist", NO);
    _aimPosSegment.selectedSegmentIndex = (NSInteger)ESPPrefsFloat(@"AimPos", 0.0f);
    _triggerSegment.selectedSegmentIndex = (NSInteger)ESPPrefsFloat(@"TriggerMode", 0.0f);
    _aimFovSlider.value = ESPPrefsFloat(@"Fov", 150.0f);
    _aimFovValueLabel.text = [NSString stringWithFormat:@"%.0f", _aimFovSlider.value];
    _aimDistanceSlider.value = ESPPrefsFloat(@"Distance", 200.0f);
    _aimDistanceValueLabel.text = [NSString stringWithFormat:@"%.0f", _aimDistanceSlider.value];

    _brutalSwitch.on = ESPPrefsBool(@"Norecoil", NO);
    _speedSwitch.on = ESPPrefsBool(@"Speed", NO);
    _speedSlider.value = ESPPrefsFloat(@"SpeedValue", 1.22f);
    _speedValueLabel.text = [NSString stringWithFormat:@"%.2f", _speedSlider.value];
    _fastReloadSwitch.on = ESPPrefsBool(@"FastReload", NO);
    _fastReloadSlider.value = ESPPrefsFloat(@"FastReloadSpeed", 1.0f);
    _fastReloadValueLabel.text = [NSString stringWithFormat:@"%.1f", _fastReloadSlider.value];

    _camSwitch.on = ESPPrefsBool(@"CamPC", NO);
    _camSlider.value = ESPPrefsFloat(@"CamPCValue", 30.0f);
    _camValueLabel.text = [NSString stringWithFormat:@"%.0f", _camSlider.value];
}

- (void)espSwitchChanged:(UISwitch *)s {
    ESPPrefsSetBoolLive(@"EnableESP", s.on);
    ESPSyncFromPrefs();
}

- (void)espSubSwitchChanged:(UISwitch *)s {
    NSArray *keys = @[@"Box", @"Bone", @"Name", @"Distance", @"Line", @"Health",
                      @"Count", @"Weapon", @"Alert360", @"AlertNum",
                      @"EspCheckVisible", @"EspBot"];
    NSArray *switches = @[_espBoxSwitch, _espBoneSwitch, _espNameSwitch, _espDistSwitch,
                           _espLineSwitch, _espHealthSwitch, _espCountSwitch, _espWeaponSwitch,
                           _espAlert360Switch, _espAlertNumSwitch, _espCheckVisSwitch, _espBotSwitch];
    NSUInteger idx = [switches indexOfObject:s];
    if (idx == NSNotFound || idx >= keys.count) return;
    ESPPrefsSetBoolLive(keys[idx], s.on);
    ESPSyncFromPrefs();
}

- (void)aimbotSwitchChanged:(UISwitch *)s    { ESPPrefsSetBoolLive(@"Aimbot", s.on);    ESPSyncFromPrefs(); }
- (void)aimSilentSwitchChanged:(UISwitch *)s { ESPPrefsSetBoolLive(@"AimSilent", s.on); ESPSyncFromPrefs(); }
- (void)aimAssistSwitchChanged:(UISwitch *)s { ESPPrefsSetBoolLive(@"AimAssist", s.on); ESPSyncFromPrefs(); }

- (void)aimPosChanged:(UISegmentedControl *)seg {
    ESPPrefsSetFloat(@"AimPos", (float)seg.selectedSegmentIndex);
    ESPSyncFromPrefs();
}

- (void)triggerChanged:(UISegmentedControl *)seg {
    ESPPrefsSetFloat(@"TriggerMode", (float)seg.selectedSegmentIndex);
    ESPSyncFromPrefs();
}

- (void)aimFovChanged:(UISlider *)s {
    _aimFovValueLabel.text = [NSString stringWithFormat:@"%.0f", s.value];
    ESPPrefsSetFloat(@"Fov", s.value);
    ESPSyncFromPrefs();
}

- (void)aimDistanceChanged:(UISlider *)s {
    _aimDistanceValueLabel.text = [NSString stringWithFormat:@"%.0f", s.value];
    ESPPrefsSetFloat(@"Distance", s.value);
    ESPSyncFromPrefs();
}

- (void)brutalSwitchChanged:(UISwitch *)s     { ESPPrefsSetBoolLive(@"Norecoil", s.on); ESPSyncFromPrefs(); }
- (void)speedSwitchChanged:(UISwitch *)s      { ESPPrefsSetBoolLive(@"Speed", s.on);    ESPSyncFromPrefs(); }
- (void)fastReloadSwitchChanged:(UISwitch *)s { ESPPrefsSetBoolLive(@"FastReload", s.on); ESPSyncFromPrefs(); }

- (void)speedSliderChanged:(UISlider *)s {
    _speedValueLabel.text = [NSString stringWithFormat:@"%.2f", s.value];
    ESPPrefsSetFloat(@"SpeedValue", s.value);
    ESPSyncFromPrefs();
}

- (void)fastReloadSliderChanged:(UISlider *)s {
    _fastReloadValueLabel.text = [NSString stringWithFormat:@"%.1f", s.value];
    ESPPrefsSetFloat(@"FastReloadSpeed", s.value);
    ESPSyncFromPrefs();
}

- (void)camSwitchChanged:(UISwitch *)s { ESPPrefsSetBoolLive(@"CamPC", s.on); ESPSyncFromPrefs(); }

- (void)camSliderChanged:(UISlider *)s {
    _camValueLabel.text = [NSString stringWithFormat:@"%.0f", s.value];
    ESPPrefsSetFloat(@"CamPCValue", s.value);
    ESPSyncFromPrefs();
}

- (void)autoCleanSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBool(@"AutoVarCleanBeforeHUD", sender.on);
}

#pragma mark - Layout (tất cả trong 1 hàm)

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    _scrollView.frame = self.view.bounds;

    CGFloat gear = 36.0f;
    _settingsBtn.frame = CGRectMake(width - insets.right - 16 - gear, insets.top + 8, gear, gear);
    _trashBtn.frame = CGRectMake(CGRectGetMinX(_settingsBtn.frame) - 10 - gear, insets.top + 8, gear, gear);

    CGFloat contentW = width;
    CGFloat xPad = 16.0f;
    CGFloat cardW = contentW - xPad * 2.0f;
    CGFloat y = insets.top + 52.0f;

    _titleLabel.frame = CGRectMake(xPad + 6, y, cardW - 12 - 80, 40);
    y = CGRectGetMaxY(_titleLabel.frame) + 14;

    // ===== CONTROL =====
    CGFloat controlH = 86.0f;
    _controlCard.frame = CGRectMake(xPad, y, cardW, controlH);
    CGFloat iconSize = MAX(48.0f, MIN(kMenuButtonSize, MIN(cardW * 0.42f, controlH * 0.85f)));
    _controlIconView.frame = CGRectMake(14, (controlH - iconSize) * 0.5f, iconSize, iconSize);
    _startButton.frame = CGRectMake(cardW - 108, 26, 94, 34);
    _controlTitleLabel.frame = CGRectMake(80, 20, cardW - 108 - 88, 22);
    _controlSubtitleLabel.frame = CGRectMake(80, 44, cardW - 108 - 88, 28);
    y = CGRectGetMaxY(_controlCard.frame) + 12;

    // ===== ESP =====
    {
        CGFloat pad = 16.0f;
        CGFloat swW = 51.0f;
        CGFloat rowH = 40.0f;
        CGFloat headerH = 40.0f;
        NSInteger subRows = 6;
        CGFloat cardH = headerH + rowH + rowH * subRows + 10.0f;
        _espCard.frame = CGRectMake(xPad, y, cardW, cardH);

        _espTitleLabel.frame = CGRectMake(pad, 10, 200, 24);
        _espSwitch.frame = CGRectMake(cardW - swW - pad, 6, swW, 31);

        CGFloat colW = (cardW - pad * 3) * 0.5f;
        CGFloat colLeftX = pad;
        CGFloat colRightX = pad * 2 + colW;

        NSArray *labels = @[@"Box", @"Bone", @"Name", @"Distance", @"Line", @"Health",
                            @"Count", @"Weapon", @"Alert 360", @"Alert Num", @"Check Vis", @"Bot"];
        NSArray *sws = @[_espBoxSwitch, _espBoneSwitch, _espNameSwitch, _espDistSwitch,
                         _espLineSwitch, _espHealthSwitch, _espCountSwitch, _espWeaponSwitch,
                         _espAlert360Switch, _espAlertNumSwitch, _espCheckVisSwitch, _espBotSwitch];
        CGFloat startY = headerH + rowH;
        for (NSInteger i = 0; i < labels.count; i++) {
            NSInteger row = i / 2;
            NSInteger col = i % 2;
            CGFloat cx = (col == 0) ? colLeftX : colRightX;
            CGFloat cy = startY + rowH * row;

            UILabel *lbl = [self viewWithTag:1000 + i];
            if (!lbl) {
                lbl = [self makeSubLabel:labels[i]];
                lbl.tag = 1000 + i;
                [_espCard addSubview:lbl];
            }
            lbl.frame = CGRectMake(cx, cy + 8, colW - swW - 6, 24);

            UISwitch *sw = sws[i];
            sw.frame = CGRectMake(cx + colW - swW - 4, cy + 4, swW, 31);
        }
        y = CGRectGetMaxY(_espCard.frame) + 12;
    }

    // ===== AIM =====
    {
        CGFloat pad = 16.0f;
        CGFloat swW = 51.0f;
        CGFloat rowH = 44.0f;
        CGFloat cardH = rowH * 6 + 14.0f;
        _aimCard.frame = CGRectMake(xPad, y, cardW, cardH);

        CGFloat cy = 8.0f;
        UILabel *aimbotLbl = [self viewWithTag:2000];
        aimbotLbl.frame = CGRectMake(pad, cy + 8, 200, 24);
        _aimbotSwitch.frame = CGRectMake(cardW - swW - pad, cy + 4, swW, 31);
        cy += rowH;

        _aimPosSegment.frame = CGRectMake(pad, cy + 4, cardW - pad * 2, 32);
        cy += rowH;

        _triggerSegment.frame = CGRectMake(pad, cy + 4, cardW - pad * 2, 32);
        cy += rowH;

        UILabel *silentLbl = [self viewWithTag:2001];
        silentLbl.frame = CGRectMake(pad, cy + 8, 100, 24);
        _aimSilentSwitch.frame = CGRectMake(pad + 90, cy + 4, swW, 31);

        UILabel *assistLbl = [self viewWithTag:2002];
        assistLbl.frame = CGRectMake(cardW / 2.0f + 8, cy + 8, 100, 24);
        _aimAssistSwitch.frame = CGRectMake(cardW / 2.0f + 88, cy + 4, swW, 31);
        cy += rowH;

        UILabel *fovLbl = [self viewWithTag:2003];
        fovLbl.frame = CGRectMake(pad, cy + 8, 50, 24);
        _aimFovSlider.frame = CGRectMake(pad + 54, cy + 6, cardW - pad * 2 - 54 - 60, 30);
        _aimFovValueLabel.frame = CGRectMake(cardW - pad - 56, cy + 8, 56, 24);
        cy += rowH;

        UILabel *distLbl = [self viewWithTag:2004];
        distLbl.frame = CGRectMake(pad, cy + 8, 50, 24);
        _aimDistanceSlider.frame = CGRectMake(pad + 54, cy + 6, cardW - pad * 2 - 54 - 60, 30);
        _aimDistanceValueLabel.frame = CGRectMake(cardW - pad - 56, cy + 8, 56, 24);

        y = CGRectGetMaxY(_aimCard.frame) + 12;
    }

    // ===== MOVE =====
    {
        CGFloat pad = 16.0f;
        CGFloat swW = 51.0f;
        CGFloat rowH = 44.0f;
        CGFloat cardH = rowH * 5 + 14.0f;
        _moveCard.frame = CGRectMake(xPad, y, cardW, cardH);

        CGFloat cy = 8.0f;
        UILabel *brutalLbl = [self viewWithTag:3000];
        brutalLbl.frame = CGRectMake(pad, cy + 8, 250, 24);
        _brutalSwitch.frame = CGRectMake(cardW - swW - pad, cy + 4, swW, 31);
        cy += rowH;

        UILabel *speedLbl = [self viewWithTag:3001];
        speedLbl.frame = CGRectMake(pad, cy + 8, 200, 24);
        _speedSwitch.frame = CGRectMake(cardW - swW - pad, cy + 4, swW, 31);
        cy += rowH;

        _speedSlider.frame = CGRectMake(pad, cy + 6, cardW - pad * 2 - 60, 30);
        _speedValueLabel.frame = CGRectMake(cardW - pad - 56, cy + 8, 56, 24);
        cy += rowH;

        UILabel *frLbl = [self viewWithTag:3002];
        frLbl.frame = CGRectMake(pad, cy + 8, 200, 24);
        _fastReloadSwitch.frame = CGRectMake(cardW - swW - pad, cy + 4, swW, 31);
        cy += rowH;

        _fastReloadSlider.frame = CGRectMake(pad, cy + 6, cardW - pad * 2 - 60, 30);
        _fastReloadValueLabel.frame = CGRectMake(cardW - pad - 56, cy + 8, 56, 24);

        y = CGRectGetMaxY(_moveCard.frame) + 12;
    }

    // ===== CAM =====
    {
        CGFloat pad = 16.0f;
        CGFloat swW = 51.0f;
        CGFloat cardH = 90.0f;
        _camCard.frame = CGRectMake(xPad, y, cardW, cardH);
        _camTitleLabel.frame = CGRectMake(pad, 12, 300, 24);
        _camSwitch.frame = CGRectMake(cardW - swW - pad, 10, swW, 31);
        _camSlider.frame = CGRectMake(pad, 54, cardW - pad * 2 - 60, 30);
        _camValueLabel.frame = CGRectMake(cardW - pad - 56, 56, 56, 24);
        y = CGRectGetMaxY(_camCard.frame) + 12;
    }

    // ===== LOG =====
    CGFloat logH = 210.0f;
    _logCard.frame = CGRectMake(xPad, y, cardW, logH);
    _logTextView.frame = CGRectMake(10, 8, cardW - 20, logH - 16);
    y = CGRectGetMaxY(_logCard.frame) + 16;

    // ===== VERSION =====
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

    // ===== STATUS =====
    CGFloat statusH = 64.0f;
    _statusCard.frame = CGRectMake(xPad, y, cardW, statusH);
    _statusDot.frame = CGRectMake(16, 27, 10, 10);
    _openGameButton.frame = CGRectMake(cardW - 112, 15, 98, 34);
    _statusLabel.frame = CGRectMake(36, 18, cardW - 112 - 44, 28);
    y = CGRectGetMaxY(_statusCard.frame) + 12;

    // ===== LICENSE / AUTH =====
    CGFloat halfW = (cardW - gap) * 0.5f;
    CGFloat halfH = 92.0f;
    _licenseCard.frame = CGRectMake(xPad, y, halfW, halfH);
    _authCard.frame = CGRectMake(xPad + halfW + gap, y, halfW, halfH);
    _licenseTitleLabel.frame = CGRectMake(14, 12, halfW - 28, 18);
    _licenseValueLabel.frame = CGRectMake(14, 36, halfW - 28, 46);
    _authTitleLabel.frame = CGRectMake(14, 12, halfW - 28, 18);
    _authValueLabel.frame = CGRectMake(14, 40, halfW - 28, 36);
    y = CGRectGetMaxY(_licenseCard.frame) + 12;

    // ===== SUPPORT =====
    CGFloat supportH = 72.0f;
    _supportCard.frame = CGRectMake(xPad, y, cardW, supportH);
    _joinButton.frame = CGRectMake(cardW - 92, 19, 78, 34);
    _supportTitleLabel.frame = CGRectMake(16, 16, cardW - 120, 22);
    _supportSubtitleLabel.frame = CGRectMake(16, 40, cardW - 120, 18);
    y = CGRectGetMaxY(_supportCard.frame) + 12;

    // ===== EXTRA =====
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
    UIColor *selected = MDThemeAccent();
    _ffMaxCard.layer.borderWidth = 2.0f;
    _ffCard.layer.borderWidth = 2.0f;
    _ffMaxCard.layer.borderColor = (isMax ? selected : MDThemeLine()).CGColor;
    _ffCard.layer.borderColor = (!isMax ? selected : MDThemeLine()).CGColor;
    _ffMaxCard.backgroundColor = isMax ? MDThemePanel2() : MDThemePanel();
    _ffCard.backgroundColor = !isMax ? MDThemePanel2() : MDThemePanel();
    UIImage *icon = [self imageNamedWebPOrPNG:isMax ? @"ffmax" : @"ff"];
    if (icon) _controlIconView.image = icon;
}

#pragma mark - App lifecycle

- (void)appBecameActive {
    GameOffsetsReload();
    [self updateVersionSelectionUI];
    [self syncAllSwitchesFromPrefs];
    [self refreshHUDState];
}

#pragma mark - HUD / game

- (BOOL)isGameRunning { return GameTargetIsRunning(); }

- (void)startPollingGameState {
    __weak __typeof(self) weakSelf = self;
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshHUDState];
    }];
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Không mở được game"
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
        _statusDot.backgroundColor = [self accentGreen];
        NSString *name = GameTargetIsMax() ? @"Free Fire MAX" : @"Free Fire";
        _statusLabel.text = [NSString stringWithFormat:@"Trạng thái · %@ đang chạy", name];
    } else {
        _statusDot.backgroundColor = [UIColor colorWithRed:0.9 green:0.25 blue:0.25 alpha:1.0];
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
    BOOL isWithinGrace = _pendingHUDEnableUntil > 0 && now < _pendingHUDEnableUntil;
    if (!hudIsEnabled && isWithinGrace) {
        [_startButton setTitle:@"Đang bật…" forState:UIControlStateNormal];
        return;
    }

    if (hudIsEnabled) {
        _pendingHUDEnableUntil = 0;
        [_startButton setTitle:@"Tắt HUD" forState:UIControlStateNormal];
        _startButton.backgroundColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    } else {
        [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
        _startButton.backgroundColor = [self accentGreen];
    }
}

@end
