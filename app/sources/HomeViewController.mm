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

static HomeViewController *g_activeLogVC = nil;
static void HomeVCBootLogSink(NSString *line);

#import <QuartzCore/QuartzCore.h>
#import <SafariServices/SafariServices.h>

static const CGFloat kMenuButtonSize = 56.0f;

static NSString *const kBrandName = @"VN TOOL";
static NSString *const kBrandDev  = @"@VNTool";

@interface HomeViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
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
@property (nonatomic, strong) UILabel *aimModeTitleLabel;
@property (nonatomic, strong) UISegmentedControl *aimModeSegment;
@property (nonatomic, strong) UILabel *aimPosTitleLabel;
@property (nonatomic, strong) UISegmentedControl *aimPosSegment;
@property (nonatomic, strong) UILabel *aimSphereTitleLabel;
@property (nonatomic, strong) UISegmentedControl *aimSphereSegment;
@property (nonatomic, strong) UILabel *aimFovTitleLabel;
@property (nonatomic, strong) UISlider *aimFovSlider;
@property (nonatomic, strong) UILabel *aimFovValueLabel;
@property (nonatomic, strong) UILabel *aimDistTitleLabel;
@property (nonatomic, strong) UISlider *aimDistSlider;
@property (nonatomic, strong) UILabel *aimDistValueLabel;

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
@property (nonatomic, strong) UILabel *footerLabel;

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

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appBecameActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyTheme)
                                                 name:MDThemeDidChangeNotification
                                               object:nil];
    [self startPollingGameState];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refreshHUDState];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_pollTimer invalidate];
}

#pragma mark - Helpers

- (UIColor *)cardBackground { return MDThemePanel(); }
- (UIColor *)accentGreen { return MDThemeAccent(); }
- (UIColor *)accentBlue { return MDThemeBlue(); }
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
    _controlCard.backgroundColor = MDThemePanel();
    _controlCard.layer.borderColor = MDThemeLine().CGColor;
    _controlCard.layer.borderWidth = 1.0f;
    _controlTitleLabel.textColor = MDThemeText();
    _controlSubtitleLabel.textColor = MDThemeMuted();
    _startButton.backgroundColor = MDThemeAccent();
    _versionSectionLabel.textColor = MDThemeMuted();
    _ffMaxCard.backgroundColor = MDThemePanel();
    _ffCard.backgroundColor = MDThemePanel();
    _ffMaxNameLabel.textColor = MDThemeText();
    _ffNameLabel.textColor = MDThemeText();
    _statusCard.backgroundColor = MDThemePanel();
    _statusCard.layer.borderColor = MDThemeLine().CGColor;
    _statusCard.layer.borderWidth = 1.0f;
    _statusLabel.textColor = MDThemeText();
    _openGameButton.backgroundColor = MDThemeOrange();
    _licenseCard.backgroundColor = MDThemePanel();
    _licenseCard.layer.borderColor = MDThemeLine().CGColor;
    _licenseCard.layer.borderWidth = 1.0f;
    _authCard.backgroundColor = MDThemePanel();
    _authCard.layer.borderColor = MDThemeLine().CGColor;
    _authCard.layer.borderWidth = 1.0f;
    _licenseTitleLabel.textColor = MDThemeMuted();
    _licenseValueLabel.textColor = MDThemeText();
    _authTitleLabel.textColor = MDThemeMuted();
    _supportCard.backgroundColor = MDThemePanel();
    _supportCard.layer.borderColor = MDThemeLine().CGColor;
    _supportCard.layer.borderWidth = 1.0f;
    _supportTitleLabel.textColor = MDThemeText();
    _supportSubtitleLabel.textColor = MDThemeMuted();
    _joinButton.backgroundColor = MDThemeBlue();
    _extraCard.backgroundColor = MDThemePanel();
    _extraCard.layer.borderColor = MDThemeLine().CGColor;
    _extraCard.layer.borderWidth = 1.0f;
    _autoCleanLabel.textColor = MDThemeText();
    _autoCleanSwitch.onTintColor = MDThemeAccent();
    [_authorizationButton setTitleColor:MDThemeAccent() forState:UIControlStateNormal];
    _settingsBtn.backgroundColor = MDThemePanel2();
    _settingsBtn.layer.borderColor = MDThemeLine().CGColor;
    _settingsBtn.tintColor = MDThemeText();
    _trashBtn.backgroundColor = MDThemePanel2();
    _trashBtn.layer.borderColor = MDThemeLine().CGColor;
    _trashBtn.tintColor = MDThemeText();

    if (_aimCard) {
        _aimCard.backgroundColor = MDThemePanel();
        _aimCard.layer.borderColor = MDThemeLine().CGColor;
        _aimCard.layer.borderWidth = 1.0f;
        _aimModeTitleLabel.textColor = MDThemeText();
        _aimPosTitleLabel.textColor = MDThemeText();
        _aimSphereTitleLabel.textColor = MDThemeText();
        _aimFovTitleLabel.textColor = MDThemeText();
        _aimDistTitleLabel.textColor = MDThemeText();
        _aimFovValueLabel.textColor = MDThemeMuted();
        _aimDistValueLabel.textColor = MDThemeMuted();
        _aimModeSegment.tintColor = MDThemeAccent();
        _aimPosSegment.tintColor = MDThemeAccent();
        _aimSphereSegment.tintColor = MDThemeAccent();
        if (@available(iOS 13.0, *)) {
            _aimModeSegment.selectedSegmentTintColor = MDThemeAccent();
            _aimPosSegment.selectedSegmentTintColor = MDThemeAccent();
            _aimSphereSegment.selectedSegmentTintColor = MDThemeAccent();
        }
        _aimFovSlider.minimumTrackTintColor = MDThemeAccent();
        _aimDistSlider.minimumTrackTintColor = MDThemeAccent();
    }
    if (_footerLabel) _footerLabel.textColor = MDThemeMuted();
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

#pragma mark - UI

// FIX: dùng method setTitleTextAttributes:forState: (không phải property)
static void MDSegmentStyle(UISegmentedControl *seg, CGFloat fontSize) {
    NSDictionary *attrs = @{
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSFontAttributeName: [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold]
    };
    [seg setTitleTextAttributes:attrs forState:UIControlStateNormal];
    [seg setTitleTextAttributes:attrs forState:UIControlStateSelected];
    [seg setTitleTextAttributes:attrs forState:UIControlStateHighlighted];
    [seg setTitleTextAttributes:attrs forState:UIControlStateDisabled];
}

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

    // Control card
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

    // Quick toggles card
    _togglesCard = [self makeCard];
    [_contentView addSubview:_togglesCard];

    _aimbotLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimbotLabel.text = @"Aimbot";
    _aimbotLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _aimbotLabel.textColor = [UIColor whiteColor];
    [_togglesCard addSubview:_aimbotLabel];

    _aimbotSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _aimbotSwitch.onTintColor = [self accentGreen];
    _aimbotSwitch.on = ESPPrefsBool(@"Aimbot", NO);
    [_aimbotSwitch addTarget:self action:@selector(aimbotSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_aimbotSwitch];

    _espLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espLabel.text = @"ESP";
    _espLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _espLabel.textColor = [UIColor whiteColor];
    [_togglesCard addSubview:_espLabel];

    _espSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espSwitch.onTintColor = [self accentGreen];
    _espSwitch.on = ESPPrefsBool(@"EnableESP", YES);
    [_espSwitch addTarget:self action:@selector(espSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_espSwitch];

    _camLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camLabel.text = @"Camera Xa (CamPC)";
    _camLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _camLabel.textColor = [UIColor whiteColor];
    [_togglesCard addSubview:_camLabel];

    _camSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _camSwitch.onTintColor = [self accentGreen];
    _camSwitch.on = ESPPrefsBool(@"CamPC", NO);
    [_camSwitch addTarget:self action:@selector(camSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_camSwitch];

    _camSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _camSlider.minimumValue = 0.0f;
    _camSlider.maximumValue = 150.0f;
    _camSlider.value = ESPPrefsFloat(@"CamPCValue", 30.0f);
    _camSlider.minimumTrackTintColor = [self accentGreen];
    [_camSlider addTarget:self action:@selector(camSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_camSlider];

    _camValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camValueLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _camValueLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    _camValueLabel.text = [NSString stringWithFormat:@"%.0f", _camSlider.value];
    [_togglesCard addSubview:_camValueLabel];

    // ══════════════════════════════════════════════════════════════
    // AIM CARD
    // ══════════════════════════════════════════════════════════════
    _aimCard = [self makeCard];
    [_contentView addSubview:_aimCard];

    // Chế độ Aim: Luôn luôn / Bắn / Ngắm / Bắn & Ngắm
    _aimModeTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimModeTitleLabel.text = @"Chế độ Aim";
    _aimModeTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _aimModeTitleLabel.textColor = MDThemeText();
    [_aimCard addSubview:_aimModeTitleLabel];

    _aimModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Luôn luôn", @"Bắn", @"Ngắm", @"Bắn & Ngắm"]];
    _aimModeSegment.selectedSegmentIndex = (int)ESPPrefsFloat(@"TriggerMode", 0.0f);
    if (_aimModeSegment.selectedSegmentIndex < 0) _aimModeSegment.selectedSegmentIndex = 0;
    if (_aimModeSegment.selectedSegmentIndex > 3) _aimModeSegment.selectedSegmentIndex = 3;
    _aimModeSegment.tintColor = MDThemeAccent();
    if (@available(iOS 13.0, *)) {
        _aimModeSegment.selectedSegmentTintColor = MDThemeAccent();
    }
    MDSegmentStyle(_aimModeSegment, 11.0);
    [_aimModeSegment addTarget:self action:@selector(aimModeChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimModeSegment];

    // Vị trí Aim: Đầu / Cổ / Thân
    _aimPosTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimPosTitleLabel.text = @"Vị trí Aim";
    _aimPosTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _aimPosTitleLabel.textColor = MDThemeText();
    [_aimCard addSubview:_aimPosTitleLabel];

    _aimPosSegment = [[UISegmentedControl alloc] initWithItems:@[@"Đầu", @"Cổ", @"Thân"]];
    _aimPosSegment.selectedSegmentIndex = (int)ESPPrefsFloat(@"AimPos", 0.0f);
    if (_aimPosSegment.selectedSegmentIndex < 0) _aimPosSegment.selectedSegmentIndex = 0;
    if (_aimPosSegment.selectedSegmentIndex > 2) _aimPosSegment.selectedSegmentIndex = 2;
    _aimPosSegment.tintColor = MDThemeAccent();
    if (@available(iOS 13.0, *)) {
        _aimPosSegment.selectedSegmentTintColor = MDThemeAccent();
    }
    MDSegmentStyle(_aimPosSegment, 12.0);
    [_aimPosSegment addTarget:self action:@selector(aimPosChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimPosSegment];

    // Phạm vi Aim: FOV / 180° / 360°
    _aimSphereTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimSphereTitleLabel.text = @"Phạm vi Aim";
    _aimSphereTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _aimSphereTitleLabel.textColor = MDThemeText();
    [_aimCard addSubview:_aimSphereTitleLabel];

    _aimSphereSegment = [[UISegmentedControl alloc] initWithItems:@[@"FOV", @"180°", @"360°"]];
    int sphereMode = (int)ESPPrefsFloat(@"AimSphereMode", 0.0f);
    if (sphereMode < 0) sphereMode = 0;
    if (sphereMode > 2) sphereMode = 2;
    _aimSphereSegment.selectedSegmentIndex = sphereMode;
    _aimSphereSegment.tintColor = MDThemeAccent();
    if (@available(iOS 13.0, *)) {
        _aimSphereSegment.selectedSegmentTintColor = MDThemeAccent();
    }
    MDSegmentStyle(_aimSphereSegment, 12.0);
    [_aimSphereSegment addTarget:self action:@selector(aimSphereChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimSphereSegment];

    // FOV slider
    _aimFovTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimFovTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _aimFovTitleLabel.textColor = MDThemeText();
    CGFloat fovVal = ESPPrefsFloat(@"Fov", 150.0f);
    _aimFovTitleLabel.text = [NSString stringWithFormat:@"Vòng FOV: %.0f", fovVal];
    [_aimCard addSubview:_aimFovTitleLabel];

    _aimFovSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _aimFovSlider.minimumValue = 10.0f;
    _aimFovSlider.maximumValue = 500.0f;
    _aimFovSlider.value = fovVal;
    _aimFovSlider.minimumTrackTintColor = MDThemeAccent();
    [_aimFovSlider addTarget:self action:@selector(aimFovChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimFovSlider];

    _aimFovValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimFovValueLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _aimFovValueLabel.textColor = MDThemeMuted();
    _aimFovValueLabel.text = [NSString stringWithFormat:@"%.0f", fovVal];
    _aimFovValueLabel.textAlignment = NSTextAlignmentRight;
    [_aimCard addSubview:_aimFovValueLabel];

    // Cự ly Aim slider
    _aimDistTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimDistTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _aimDistTitleLabel.textColor = MDThemeText();
    CGFloat distVal = ESPPrefsFloat(@"AimDistance", 200.0f);
    if (distVal < 1.0f) distVal = 200.0f;
    _aimDistTitleLabel.text = [NSString stringWithFormat:@"Cự ly Aim: %.0fm", distVal];
    [_aimCard addSubview:_aimDistTitleLabel];

    _aimDistSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _aimDistSlider.minimumValue = 10.0f;
    _aimDistSlider.maximumValue = 400.0f;
    _aimDistSlider.value = distVal;
    _aimDistSlider.minimumTrackTintColor = MDThemeAccent();
    [_aimDistSlider addTarget:self action:@selector(aimDistChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimDistSlider];

    _aimDistValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimDistValueLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _aimDistValueLabel.textColor = MDThemeMuted();
    _aimDistValueLabel.text = [NSString stringWithFormat:@"%.0f", distVal];
    _aimDistValueLabel.textAlignment = NSTextAlignmentRight;
    [_aimCard addSubview:_aimDistValueLabel];

    // Hide FOV slider nếu đang ở 180/360
    if (sphereMode != 0) {
        _aimFovTitleLabel.hidden = YES;
        _aimFovSlider.hidden = YES;
        _aimFovValueLabel.hidden = YES;
    }

    // Log card
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
    _logTextView.text = @"[VN TOOL] ready.\nPress Bắt đầu to boot kernel.";
    [_logCard addSubview:_logTextView];

    // Version section
    _versionSectionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _versionSectionLabel.text = @"Lựa chọn phiên bản:";
    _versionSectionLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _versionSectionLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
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

    // License + Auth
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

    // Support
    _supportCard = [self makeCard];
    [_contentView addSubview:_supportCard];
    _supportTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportTitleLabel.text = @"Liên hệ hỗ trợ";
    _supportTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _supportTitleLabel.textColor = [UIColor whiteColor];
    [_supportCard addSubview:_supportTitleLabel];
    _supportSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportSubtitleLabel.text = @"Nhấn Join để nhận hỗ trợ từ VN TOOL";
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

    // Extra
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

    // Footer brand
    _footerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    NSString *appVer = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (!appVer.length) appVer = @"1.0.0";
    _footerLabel.text = [NSString stringWithFormat:@"%@ v%@ • dev: %@", kBrandName, appVer, kBrandDev];
    _footerLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    _footerLabel.textColor = MDThemeMuted();
    _footerLabel.textAlignment = NSTextAlignmentCenter;
    _footerLabel.numberOfLines = 2;
    [_contentView addSubview:_footerLabel];
}

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

static HomeViewController *g_activeLogVC = nil;
static void HomeVCBootLogSink(NSString *line);

#import <QuartzCore/QuartzCore.h>
#import <SafariServices/SafariServices.h>

static const CGFloat kMenuButtonSize = 56.0f;

static NSString *const kBrandName = @"VN TOOL";
static NSString *const kBrandDev  = @"@VNTool";

@interface HomeViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
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
@property (nonatomic, strong) UILabel *aimModeTitleLabel;
@property (nonatomic, strong) UISegmentedControl *aimModeSegment;
@property (nonatomic, strong) UILabel *aimPosTitleLabel;
@property (nonatomic, strong) UISegmentedControl *aimPosSegment;
@property (nonatomic, strong) UILabel *aimSphereTitleLabel;
@property (nonatomic, strong) UISegmentedControl *aimSphereSegment;
@property (nonatomic, strong) UILabel *aimFovTitleLabel;
@property (nonatomic, strong) UISlider *aimFovSlider;
@property (nonatomic, strong) UILabel *aimFovValueLabel;
@property (nonatomic, strong) UILabel *aimDistTitleLabel;
@property (nonatomic, strong) UISlider *aimDistSlider;
@property (nonatomic, strong) UILabel *aimDistValueLabel;

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
@property (nonatomic, strong) UILabel *footerLabel;

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

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appBecameActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyTheme)
                                                 name:MDThemeDidChangeNotification
                                               object:nil];
    [self startPollingGameState];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refreshHUDState];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_pollTimer invalidate];
}

#pragma mark - Helpers

- (UIColor *)cardBackground { return MDThemePanel(); }
- (UIColor *)accentGreen { return MDThemeAccent(); }
- (UIColor *)accentBlue { return MDThemeBlue(); }
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
    _controlCard.backgroundColor = MDThemePanel();
    _controlCard.layer.borderColor = MDThemeLine().CGColor;
    _controlCard.layer.borderWidth = 1.0f;
    _controlTitleLabel.textColor = MDThemeText();
    _controlSubtitleLabel.textColor = MDThemeMuted();
    _startButton.backgroundColor = MDThemeAccent();
    _versionSectionLabel.textColor = MDThemeMuted();
    _ffMaxCard.backgroundColor = MDThemePanel();
    _ffCard.backgroundColor = MDThemePanel();
    _ffMaxNameLabel.textColor = MDThemeText();
    _ffNameLabel.textColor = MDThemeText();
    _statusCard.backgroundColor = MDThemePanel();
    _statusCard.layer.borderColor = MDThemeLine().CGColor;
    _statusCard.layer.borderWidth = 1.0f;
    _statusLabel.textColor = MDThemeText();
    _openGameButton.backgroundColor = MDThemeOrange();
    _licenseCard.backgroundColor = MDThemePanel();
    _licenseCard.layer.borderColor = MDThemeLine().CGColor;
    _licenseCard.layer.borderWidth = 1.0f;
    _authCard.backgroundColor = MDThemePanel();
    _authCard.layer.borderColor = MDThemeLine().CGColor;
    _authCard.layer.borderWidth = 1.0f;
    _licenseTitleLabel.textColor = MDThemeMuted();
    _licenseValueLabel.textColor = MDThemeText();
    _authTitleLabel.textColor = MDThemeMuted();
    _supportCard.backgroundColor = MDThemePanel();
    _supportCard.layer.borderColor = MDThemeLine().CGColor;
    _supportCard.layer.borderWidth = 1.0f;
    _supportTitleLabel.textColor = MDThemeText();
    _supportSubtitleLabel.textColor = MDThemeMuted();
    _joinButton.backgroundColor = MDThemeBlue();
    _extraCard.backgroundColor = MDThemePanel();
    _extraCard.layer.borderColor = MDThemeLine().CGColor;
    _extraCard.layer.borderWidth = 1.0f;
    _autoCleanLabel.textColor = MDThemeText();
    _autoCleanSwitch.onTintColor = MDThemeAccent();
    [_authorizationButton setTitleColor:MDThemeAccent() forState:UIControlStateNormal];
    _settingsBtn.backgroundColor = MDThemePanel2();
    _settingsBtn.layer.borderColor = MDThemeLine().CGColor;
    _settingsBtn.tintColor = MDThemeText();
    _trashBtn.backgroundColor = MDThemePanel2();
    _trashBtn.layer.borderColor = MDThemeLine().CGColor;
    _trashBtn.tintColor = MDThemeText();

    if (_aimCard) {
        _aimCard.backgroundColor = MDThemePanel();
        _aimCard.layer.borderColor = MDThemeLine().CGColor;
        _aimCard.layer.borderWidth = 1.0f;
        _aimModeTitleLabel.textColor = MDThemeText();
        _aimPosTitleLabel.textColor = MDThemeText();
        _aimSphereTitleLabel.textColor = MDThemeText();
        _aimFovTitleLabel.textColor = MDThemeText();
        _aimDistTitleLabel.textColor = MDThemeText();
        _aimFovValueLabel.textColor = MDThemeMuted();
        _aimDistValueLabel.textColor = MDThemeMuted();
        _aimModeSegment.tintColor = MDThemeAccent();
        _aimPosSegment.tintColor = MDThemeAccent();
        _aimSphereSegment.tintColor = MDThemeAccent();
        if (@available(iOS 13.0, *)) {
            _aimModeSegment.selectedSegmentTintColor = MDThemeAccent();
            _aimPosSegment.selectedSegmentTintColor = MDThemeAccent();
            _aimSphereSegment.selectedSegmentTintColor = MDThemeAccent();
        }
        _aimFovSlider.minimumTrackTintColor = MDThemeAccent();
        _aimDistSlider.minimumTrackTintColor = MDThemeAccent();
    }
    if (_footerLabel) _footerLabel.textColor = MDThemeMuted();
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

#pragma mark - UI

// FIX: dùng method setTitleTextAttributes:forState: (không phải property)
static void MDSegmentStyle(UISegmentedControl *seg, CGFloat fontSize) {
    NSDictionary *attrs = @{
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSFontAttributeName: [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold]
    };
    [seg setTitleTextAttributes:attrs forState:UIControlStateNormal];
    [seg setTitleTextAttributes:attrs forState:UIControlStateSelected];
    [seg setTitleTextAttributes:attrs forState:UIControlStateHighlighted];
    [seg setTitleTextAttributes:attrs forState:UIControlStateDisabled];
}

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

    // Control card
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

    // Quick toggles card
    _togglesCard = [self makeCard];
    [_contentView addSubview:_togglesCard];

    _aimbotLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimbotLabel.text = @"Aimbot";
    _aimbotLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _aimbotLabel.textColor = [UIColor whiteColor];
    [_togglesCard addSubview:_aimbotLabel];

    _aimbotSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _aimbotSwitch.onTintColor = [self accentGreen];
    _aimbotSwitch.on = ESPPrefsBool(@"Aimbot", NO);
    [_aimbotSwitch addTarget:self action:@selector(aimbotSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_aimbotSwitch];

    _espLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espLabel.text = @"ESP";
    _espLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _espLabel.textColor = [UIColor whiteColor];
    [_togglesCard addSubview:_espLabel];

    _espSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espSwitch.onTintColor = [self accentGreen];
    _espSwitch.on = ESPPrefsBool(@"EnableESP", YES);
    [_espSwitch addTarget:self action:@selector(espSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_espSwitch];

    _camLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camLabel.text = @"Camera Xa (CamPC)";
    _camLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _camLabel.textColor = [UIColor whiteColor];
    [_togglesCard addSubview:_camLabel];

    _camSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _camSwitch.onTintColor = [self accentGreen];
    _camSwitch.on = ESPPrefsBool(@"CamPC", NO);
    [_camSwitch addTarget:self action:@selector(camSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_camSwitch];

    _camSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _camSlider.minimumValue = 0.0f;
    _camSlider.maximumValue = 150.0f;
    _camSlider.value = ESPPrefsFloat(@"CamPCValue", 30.0f);
    _camSlider.minimumTrackTintColor = [self accentGreen];
    [_camSlider addTarget:self action:@selector(camSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_camSlider];

    _camValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camValueLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _camValueLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    _camValueLabel.text = [NSString stringWithFormat:@"%.0f", _camSlider.value];
    [_togglesCard addSubview:_camValueLabel];

    // ══════════════════════════════════════════════════════════════
    // AIM CARD
    // ══════════════════════════════════════════════════════════════
    _aimCard = [self makeCard];
    [_contentView addSubview:_aimCard];

    // Chế độ Aim: Luôn luôn / Bắn / Ngắm / Bắn & Ngắm
    _aimModeTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimModeTitleLabel.text = @"Chế độ Aim";
    _aimModeTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _aimModeTitleLabel.textColor = MDThemeText();
    [_aimCard addSubview:_aimModeTitleLabel];

    _aimModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Luôn luôn", @"Bắn", @"Ngắm", @"Bắn & Ngắm"]];
    _aimModeSegment.selectedSegmentIndex = (int)ESPPrefsFloat(@"TriggerMode", 0.0f);
    if (_aimModeSegment.selectedSegmentIndex < 0) _aimModeSegment.selectedSegmentIndex = 0;
    if (_aimModeSegment.selectedSegmentIndex > 3) _aimModeSegment.selectedSegmentIndex = 3;
    _aimModeSegment.tintColor = MDThemeAccent();
    if (@available(iOS 13.0, *)) {
        _aimModeSegment.selectedSegmentTintColor = MDThemeAccent();
    }
    MDSegmentStyle(_aimModeSegment, 11.0);
    [_aimModeSegment addTarget:self action:@selector(aimModeChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimModeSegment];

    // Vị trí Aim: Đầu / Cổ / Thân
    _aimPosTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimPosTitleLabel.text = @"Vị trí Aim";
    _aimPosTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _aimPosTitleLabel.textColor = MDThemeText();
    [_aimCard addSubview:_aimPosTitleLabel];

    _aimPosSegment = [[UISegmentedControl alloc] initWithItems:@[@"Đầu", @"Cổ", @"Thân"]];
    _aimPosSegment.selectedSegmentIndex = (int)ESPPrefsFloat(@"AimPos", 0.0f);
    if (_aimPosSegment.selectedSegmentIndex < 0) _aimPosSegment.selectedSegmentIndex = 0;
    if (_aimPosSegment.selectedSegmentIndex > 2) _aimPosSegment.selectedSegmentIndex = 2;
    _aimPosSegment.tintColor = MDThemeAccent();
    if (@available(iOS 13.0, *)) {
        _aimPosSegment.selectedSegmentTintColor = MDThemeAccent();
    }
    MDSegmentStyle(_aimPosSegment, 12.0);
    [_aimPosSegment addTarget:self action:@selector(aimPosChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimPosSegment];

    // Phạm vi Aim: FOV / 180° / 360°
    _aimSphereTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimSphereTitleLabel.text = @"Phạm vi Aim";
    _aimSphereTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _aimSphereTitleLabel.textColor = MDThemeText();
    [_aimCard addSubview:_aimSphereTitleLabel];

    _aimSphereSegment = [[UISegmentedControl alloc] initWithItems:@[@"FOV", @"180°", @"360°"]];
    int sphereMode = (int)ESPPrefsFloat(@"AimSphereMode", 0.0f);
    if (sphereMode < 0) sphereMode = 0;
    if (sphereMode > 2) sphereMode = 2;
    _aimSphereSegment.selectedSegmentIndex = sphereMode;
    _aimSphereSegment.tintColor = MDThemeAccent();
    if (@available(iOS 13.0, *)) {
        _aimSphereSegment.selectedSegmentTintColor = MDThemeAccent();
    }
    MDSegmentStyle(_aimSphereSegment, 12.0);
    [_aimSphereSegment addTarget:self action:@selector(aimSphereChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimSphereSegment];

    // FOV slider
    _aimFovTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimFovTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _aimFovTitleLabel.textColor = MDThemeText();
    CGFloat fovVal = ESPPrefsFloat(@"Fov", 150.0f);
    _aimFovTitleLabel.text = [NSString stringWithFormat:@"Vòng FOV: %.0f", fovVal];
    [_aimCard addSubview:_aimFovTitleLabel];

    _aimFovSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _aimFovSlider.minimumValue = 10.0f;
    _aimFovSlider.maximumValue = 500.0f;
    _aimFovSlider.value = fovVal;
    _aimFovSlider.minimumTrackTintColor = MDThemeAccent();
    [_aimFovSlider addTarget:self action:@selector(aimFovChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimFovSlider];

    _aimFovValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimFovValueLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _aimFovValueLabel.textColor = MDThemeMuted();
    _aimFovValueLabel.text = [NSString stringWithFormat:@"%.0f", fovVal];
    _aimFovValueLabel.textAlignment = NSTextAlignmentRight;
    [_aimCard addSubview:_aimFovValueLabel];

    // Cự ly Aim slider
    _aimDistTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimDistTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _aimDistTitleLabel.textColor = MDThemeText();
    CGFloat distVal = ESPPrefsFloat(@"AimDistance", 200.0f);
    if (distVal < 1.0f) distVal = 200.0f;
    _aimDistTitleLabel.text = [NSString stringWithFormat:@"Cự ly Aim: %.0fm", distVal];
    [_aimCard addSubview:_aimDistTitleLabel];

    _aimDistSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _aimDistSlider.minimumValue = 10.0f;
    _aimDistSlider.maximumValue = 400.0f;
    _aimDistSlider.value = distVal;
    _aimDistSlider.minimumTrackTintColor = MDThemeAccent();
    [_aimDistSlider addTarget:self action:@selector(aimDistChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimDistSlider];

    _aimDistValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimDistValueLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _aimDistValueLabel.textColor = MDThemeMuted();
    _aimDistValueLabel.text = [NSString stringWithFormat:@"%.0f", distVal];
    _aimDistValueLabel.textAlignment = NSTextAlignmentRight;
    [_aimCard addSubview:_aimDistValueLabel];

    // Hide FOV slider nếu đang ở 180/360
    if (sphereMode != 0) {
        _aimFovTitleLabel.hidden = YES;
        _aimFovSlider.hidden = YES;
        _aimFovValueLabel.hidden = YES;
    }

    // Log card
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
    _logTextView.text = @"[VN TOOL] ready.\nPress Bắt đầu to boot kernel.";
    [_logCard addSubview:_logTextView];

    // Version section
    _versionSectionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _versionSectionLabel.text = @"Lựa chọn phiên bản:";
    _versionSectionLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _versionSectionLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
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

    // License + Auth
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

    // Support
    _supportCard = [self makeCard];
    [_contentView addSubview:_supportCard];
    _supportTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportTitleLabel.text = @"Liên hệ hỗ trợ";
    _supportTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _supportTitleLabel.textColor = [UIColor whiteColor];
    [_supportCard addSubview:_supportTitleLabel];
    _supportSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportSubtitleLabel.text = @"Nhấn Join để nhận hỗ trợ từ VN TOOL";
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

    // Extra
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

    // Footer brand
    _footerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    NSString *appVer = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (!appVer.length) appVer = @"1.0.0";
    _footerLabel.text = [NSString stringWithFormat:@"%@ v%@ • dev: %@", kBrandName, appVer, kBrandDev];
    _footerLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    _footerLabel.textColor = MDThemeMuted();
    _footerLabel.textAlignment = NSTextAlignmentCenter;
    _footerLabel.numberOfLines = 2;
    [_contentView addSubview:_footerLabel];
}
