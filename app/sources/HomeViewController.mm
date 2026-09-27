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

// Quick toggles
@property (nonatomic, strong) UIView *togglesCard;
@property (nonatomic, strong) UILabel *aimbotLabel;
@property (nonatomic, strong) UISwitch *aimbotSwitch;
@property (nonatomic, strong) UILabel *espLabel;
@property (nonatomic, strong) UISwitch *espSwitch;
@property (nonatomic, strong) UILabel *camLabel;
@property (nonatomic, strong) UISwitch *camSwitch;
@property (nonatomic, strong) UISlider *camSlider;
@property (nonatomic, strong) UILabel *camValueLabel;

// AIM card
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

// Functions card
@property (nonatomic, strong) UIView *functionsCard;
@property (nonatomic, strong) UILabel *silentLabel;
@property (nonatomic, strong) UISwitch *silentSwitch;
@property (nonatomic, strong) UILabel *brutalLabel;
@property (nonatomic, strong) UISwitch *brutalSwitch;
@property (nonatomic, strong) UILabel *fakeNameLabel;
@property (nonatomic, strong) UISwitch *fakeNameSwitch;
@property (nonatomic, strong) UILabel *fastReloadLabel;
@property (nonatomic, strong) UISwitch *fastReloadSwitch;
@property (nonatomic, strong) UILabel *streamerLabel;
@property (nonatomic, strong) UISwitch *streamerSwitch;
@property (nonatomic, strong) UILabel *behindWallLabel;
@property (nonatomic, strong) UISwitch *behindWallSwitch;

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
@property (nonatomic, strong) UIButton *trashBtn;
@property (nonatomic, strong) UILabel *footerLabel;

@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) NSInteger gameMissingStreak;
@property (nonatomic, assign) CFTimeInterval pendingHUDEnableUntil;
@property (nonatomic, assign) NSInteger hudRequestSerial;

- (void)appendBootLog:(NSString * _Nullable)line;
- (void)refreshHUDState;
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appBecameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:MDThemeDidChangeNotification object:nil];
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
    // Chuyển toàn bộ nút chính sang tone xanh dương/xanh ngọc dễ nhìn
    _startButton.backgroundColor = MDThemeBlue();
    _versionSectionLabel.textColor = MDThemeMuted();
    _ffMaxCard.backgroundColor = MDThemePanel();
    _ffCard.backgroundColor = MDThemePanel();
    _ffMaxNameLabel.textColor = MDThemeText();
    _ffNameLabel.textColor = MDThemeText();
    _statusCard.backgroundColor = MDThemePanel();
    _statusCard.layer.borderColor = MDThemeLine().CGColor;
    _statusCard.layer.borderWidth = 1.0f;
    _statusLabel.textColor = MDThemeText();
    _openGameButton.backgroundColor = MDThemeBlue();
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
    _autoCleanSwitch.onTintColor = MDThemeBlue();
    [_authorizationButton setTitleColor:MDThemeBlue() forState:UIControlStateNormal];
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
        _aimModeSegment.tintColor = MDThemeBlue();
        _aimPosSegment.tintColor = MDThemeBlue();
        _aimSphereSegment.tintColor = MDThemeBlue();
        if (@available(iOS 13.0, *)) {
            _aimModeSegment.selectedSegmentTintColor = MDThemeBlue();
            _aimPosSegment.selectedSegmentTintColor = MDThemeBlue();
            _aimSphereSegment.selectedSegmentTintColor = MDThemeBlue();
        }
        _aimFovSlider.minimumTrackTintColor = MDThemeBlue();
        _aimDistSlider.minimumTrackTintColor = MDThemeBlue();
    }
    if (_functionsCard) {
        _functionsCard.backgroundColor = MDThemePanel();
        _functionsCard.layer.borderColor = MDThemeLine().CGColor;
        _functionsCard.layer.borderWidth = 1.0f;
        NSArray *funcLabels = @[_silentLabel, _brutalLabel, _fakeNameLabel, _fastReloadLabel, _streamerLabel, _behindWallLabel];
        for (UILabel *l in funcLabels) if (l) l.textColor = MDThemeText();
        NSArray *funcSwitches = @[_silentSwitch, _brutalSwitch, _fakeNameSwitch, _fastReloadSwitch, _streamerSwitch, _behindWallSwitch];
        for (UISwitch *s in funcSwitches) if (s) s.onTintColor = MDThemeBlue();
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
    if (path.length) { img = [UIImage imageWithContentsOfFile:path]; if (img) return img; }
    path = [[NSBundle mainBundle] pathForResource:baseName ofType:@"png"];
    if (path.length) img = [UIImage imageWithContentsOfFile:path];
    return img;
}

- (UIView *)makeCard { return MDThemeMakeCard(); }

- (UIButton *)makeVersionCardCapturingIcon:(UIImageView * __strong *)outIcon nameLabel:(UILabel * __strong *)outName {
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
    _authValueLabel.textColor = MDThemeBlue();
    _authorizationLabel.textColor = MDThemeText();
    _autoCleanSwitch.enabled = YES;
    _autoCleanLabel.alpha = 1.0;
    _startButton.alpha = 1.0;
}

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

#pragma mark - buildUI

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

    // ─── Control card ───
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
    _startButton.backgroundColor = [self accentBlue];
    _startButton.layer.cornerRadius = 16.0f;
    _startButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
    [_startButton addTarget:self action:@selector(startButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_controlCard addSubview:_startButton];

    // ─── Quick toggles ───
    _togglesCard = [self makeCard];
    [_contentView addSubview:_togglesCard];
    _aimbotLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimbotLabel.text = @"Aimbot";
    _aimbotLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _aimbotLabel.textColor = [UIColor whiteColor];
    [_togglesCard addSubview:_aimbotLabel];
    _aimbotSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _aimbotSwitch.onTintColor = [self accentBlue];
    _aimbotSwitch.on = ESPPrefsBool(@"Aimbot", NO);
    [_aimbotSwitch addTarget:self action:@selector(aimbotSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_aimbotSwitch];
    _espLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espLabel.text = @"ESP";
    _espLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _espLabel.textColor = [UIColor whiteColor];
    [_togglesCard addSubview:_espLabel];
    _espSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espSwitch.onTintColor = [self accentBlue];
    _espSwitch.on = ESPPrefsBool(@"EnableESP", YES);
    [_espSwitch addTarget:self action:@selector(espSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_espSwitch];
    _camLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camLabel.text = @"Camera Xa";
    _camLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _camLabel.textColor = [UIColor whiteColor];
    [_togglesCard addSubview:_camLabel];
    _camSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _camSwitch.onTintColor = [self accentBlue];
    _camSwitch.on = ESPPrefsBool(@"CamPC", NO);
    [_camSwitch addTarget:self action:@selector(camSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_camSwitch];
    _camSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _camSlider.minimumValue = 0.0f;
    _camSlider.maximumValue = 150.0f;
    _camSlider.value = ESPPrefsFloat(@"CamPCValue", 30.0f);
    _camSlider.minimumTrackTintColor = [self accentBlue];
    [_camSlider addTarget:self action:@selector(camSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_camSlider];
    _camValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camValueLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _camValueLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    _camValueLabel.text = [NSString stringWithFormat:@"%.0f", _camSlider.value];
    [_togglesCard addSubview:_camValueLabel];

    // ─── AIM card ───
    _aimCard = [self makeCard];
    [_contentView addSubview:_aimCard];

    _aimModeTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimModeTitleLabel.text = @"Chế độ Aim";
    _aimModeTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _aimModeTitleLabel.textColor = MDThemeText();
    [_aimCard addSubview:_aimModeTitleLabel];
    _aimModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Luôn luôn", @"Bắn", @"Ngắm", @"Bắn & Ngắm"]];
    _aimModeSegment.selectedSegmentIndex = (int)ESPPrefsFloat(@"TriggerMode", 0.0f);
    if (_aimModeSegment.selectedSegmentIndex < 0) _aimModeSegment.selectedSegmentIndex = 0;
    if (_aimModeSegment.selectedSegmentIndex > 3) _aimModeSegment.selectedSegmentIndex = 3;
    _aimModeSegment.tintColor = MDThemeBlue();
    if (@available(iOS 13.0, *)) _aimModeSegment.selectedSegmentTintColor = MDThemeBlue();
    MDSegmentStyle(_aimModeSegment, 11.0);
    [_aimModeSegment addTarget:self action:@selector(aimModeChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimModeSegment];

    _aimPosTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimPosTitleLabel.text = @"Vị trí Aim";
    _aimPosTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _aimPosTitleLabel.textColor = MDThemeText();
    [_aimCard addSubview:_aimPosTitleLabel];
    _aimPosSegment = [[UISegmentedControl alloc] initWithItems:@[@"Đầu", @"Cổ", @"Thân"]];
    _aimPosSegment.selectedSegmentIndex = (int)ESPPrefsFloat(@"AimPos", 0.0f);
    if (_aimPosSegment.selectedSegmentIndex < 0) _aimPosSegment.selectedSegmentIndex = 0;
    if (_aimPosSegment.selectedSegmentIndex > 2) _aimPosSegment.selectedSegmentIndex = 2;
    _aimPosSegment.tintColor = MDThemeBlue();
    if (@available(iOS 13.0, *)) _aimPosSegment.selectedSegmentTintColor = MDThemeBlue();
    MDSegmentStyle(_aimPosSegment, 12.0);
    [_aimPosSegment addTarget:self action:@selector(aimPosChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimPosSegment];

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
    _aimSphereSegment.tintColor = MDThemeBlue();
    if (@available(iOS 13.0, *)) _aimSphereSegment.selectedSegmentTintColor = MDThemeBlue();
    MDSegmentStyle(_aimSphereSegment, 12.0);
    [_aimSphereSegment addTarget:self action:@selector(aimSphereChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimSphereSegment];

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
    _aimFovSlider.minimumTrackTintColor = MDThemeBlue();
    [_aimFovSlider addTarget:self action:@selector(aimFovChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimFovSlider];
    _aimFovValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimFovValueLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _aimFovValueLabel.textColor = MDThemeMuted();
    _aimFovValueLabel.text = [NSString stringWithFormat:@"%.0f", fovVal];
    _aimFovValueLabel.textAlignment = NSTextAlignmentRight;
    [_aimCard addSubview:_aimFovValueLabel];

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
    _aimDistSlider.minimumTrackTintColor = MDThemeBlue();
    [_aimDistSlider addTarget:self action:@selector(aimDistChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimDistSlider];
    _aimDistValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimDistValueLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _aimDistValueLabel.textColor = MDThemeMuted();
    _aimDistValueLabel.text = [NSString stringWithFormat:@"%.0f", distVal];
    _aimDistValueLabel.textAlignment = NSTextAlignmentRight;
    [_aimCard addSubview:_aimDistValueLabel];

    if (sphereMode != 0) {
        _aimFovTitleLabel.hidden = YES;
        _aimFovSlider.hidden = YES;
        _aimFovValueLabel.hidden = YES;
    }

    // ─── Functions card (Đã xóa bỏ các tên chức năng phụ trong ngoặc) ───
    _functionsCard = [self makeCard];
    [_contentView addSubview:_functionsCard];

    _silentLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _silentLabel.text = @"Silent Aim";
    _silentLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _silentLabel.textColor = [UIColor whiteColor];
    [_functionsCard addSubview:_silentLabel];
    _silentSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _silentSwitch.onTintColor = MDThemeBlue();
    _silentSwitch.on = ESPPrefsBool(@"AimSilent", NO);
    [_silentSwitch addTarget:self action:@selector(silentSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_functionsCard addSubview:_silentSwitch];

    _brutalLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _brutalLabel.text = @"Brutal";
    _brutalLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _brutalLabel.textColor = [UIColor whiteColor];
    [_functionsCard addSubview:_brutalLabel];
    _brutalSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _brutalSwitch.onTintColor = MDThemeBlue();
    _brutalSwitch.on = ESPPrefsBool(@"Norecoil", NO);
    [_brutalSwitch addTarget:self action:@selector(brutalSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_functionsCard addSubview:_brutalSwitch];

    _fakeNameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _fakeNameLabel.text = @"Fake Name";
    _fakeNameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _fakeNameLabel.textColor = [UIColor whiteColor];
    [_functionsCard addSubview:_fakeNameLabel];
    _fakeNameSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _fakeNameSwitch.onTintColor = MDThemeBlue();
    _fakeNameSwitch.on = ESPPrefsBool(@"SetName", NO);
    [_fakeNameSwitch addTarget:self action:@selector(fakeNameSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_functionsCard addSubview:_fakeNameSwitch];

    _fastReloadLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _fastReloadLabel.text = @"Fast Reload";
    _fastReloadLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _fastReloadLabel.textColor = [UIColor whiteColor];
    [_functionsCard addSubview:_fastReloadLabel];
    _fastReloadSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _fastReloadSwitch.onTintColor = MDThemeBlue();
    _fastReloadSwitch.on = ESPPrefsBool(@"FastReload", NO);
    [_fastReloadSwitch addTarget:self action:@selector(fastReloadSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_functionsCard addSubview:_fastReloadSwitch];

    _streamerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _streamerLabel.text = @"Streamer Mode";
    _streamerLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _streamerLabel.textColor = [UIColor whiteColor];
    [_functionsCard addSubview:_streamerLabel];
    _streamerSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _streamerSwitch.onTintColor = MDThemeBlue();
    _streamerSwitch.on = ESPPrefsBool(@"StreamerMode", NO);
    [_streamerSwitch addTarget:self action:@selector(streamerSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_functionsCard addSubview:_streamerSwitch];

    _behindWallLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _behindWallLabel.text = @"Aim sau tường";
    _behindWallLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _behindWallLabel.textColor = [UIColor whiteColor];
    [_functionsCard addSubview:_behindWallLabel];
    _behindWallSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _behindWallSwitch.onTintColor = MDThemeBlue();
    _behindWallSwitch.on = ESPPrefsBool(@"AimBehindWall", NO);
    [_behindWallSwitch addTarget:self action:@selector(behindWallSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_functionsCard addSubview:_behindWallSwitch];

    // ─── Log card ───
    _logCard = [self makeCard];
    [_contentView addSubview:_logCard];
    _logTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    _logTextView.editable = NO;
    _logTextView.scrollEnabled = YES;
    _logTextView.showsHorizontalScrollIndicator = NO;
    _logTextView.backgroundColor = [UIColor colorWithRed:0.02 green:0.04 blue:0.08 alpha:1.0];
    _logTextView.layer.cornerRadius = 10.0f;
    _logTextView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _logTextView.textColor = [UIColor colorWithRed:0.5 green:0.8 blue:1.0 alpha:1.0];
    _logTextView.text = @"[VN TOOL] ready.\nPress Bắt đầu to boot kernel.";
    [_logCard addSubview:_logTextView];

    // ─── Version section ───
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

    // ─── Status card ───
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
    _openGameButton.backgroundColor = [self accentBlue];
    _openGameButton.layer.cornerRadius = 14.0f;
    _openGameButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [_openGameButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_openGameButton setTitle:@"Vào Game" forState:UIControlStateNormal];
    [_openGameButton addTarget:self action:@selector(openGameTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_statusCard addSubview:_openGameButton];

    // ─── License + Auth ───
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

    // ─── Support ───
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

    // ─── Extra card ───
    _extraCard = [self makeCard];
    [_contentView addSubview:_extraCard];
    _autoCleanLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _autoCleanLabel.text = @"VarClean before HUD";
    _autoCleanLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _autoCleanLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1.0f];
    [_extraCard addSubview:_autoCleanLabel];
    _autoCleanSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _autoCleanSwitch.onTintColor = MDThemeBlue();
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

    // ─── Footer ───
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

#pragma mark - Layout

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

    // Control
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

    // Quick toggles
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

    // AIM card
    CGFloat aimCardH = 340.0f;
    _aimCard.frame = CGRectMake(xPad, y, cardW, aimCardH);
    CGFloat aimY = 12.0f;
    CGFloat aimInnerW = cardW - 32.0f;
    _aimModeTitleLabel.frame = CGRectMake(16, aimY, aimInnerW, 20);
    aimY += 22;
    _aimModeSegment.frame = CGRectMake(16, aimY, aimInnerW, 34);
    aimY += 42;
    _aimPosTitleLabel.frame = CGRectMake(16, aimY, aimInnerW, 20);
    aimY += 22;
    _aimPosSegment.frame = CGRectMake(16, aimY, aimInnerW, 34);
    aimY += 42;
    _aimSphereTitleLabel.frame = CGRectMake(16, aimY, aimInnerW, 20);
    aimY += 22;
    _aimSphereSegment.frame = CGRectMake(16, aimY, aimInnerW, 34);
    aimY += 42;
    _aimFovTitleLabel.frame = CGRectMake(16, aimY, aimInnerW - 60, 20);
    _aimFovValueLabel.frame = CGRectMake(16 + aimInnerW - 58, aimY, 58, 20);
    aimY += 22;
    _aimFovSlider.frame = CGRectMake(16, aimY, aimInnerW, 30);
    aimY += 38;
    _aimDistTitleLabel.frame = CGRectMake(16, aimY, aimInnerW - 60, 20);
    _aimDistValueLabel.frame = CGRectMake(16 + aimInnerW - 58, aimY, 58, 20);
    aimY += 22;
    _aimDistSlider.frame = CGRectMake(16, aimY, aimInnerW, 30);
    aimY += 30;
    y = CGRectGetMaxY(_aimCard.frame) + 12;

    // Functions card
    CGFloat funcH = 6 * 44.0f + 16.0f;
    _functionsCard.frame = CGRectMake(xPad, y, cardW, funcH);
    CGFloat rowY = 8.0f;
    CGFloat swX = cardW - 68;
    CGFloat rowH = 44.0f;
    _silentLabel.frame        = CGRectMake(16, rowY + 10, cardW - 90, 24);
    _silentSwitch.frame       = CGRectMake(swX, rowY + 6, 51, 31); rowY += rowH;
    _brutalLabel.frame        = CGRectMake(16, rowY + 10, cardW - 90, 24);
    _brutalSwitch.frame       = CGRectMake(swX, rowY + 6, 51, 31); rowY += rowH;
    _fakeNameLabel.frame      = CGRectMake(16, rowY + 10, cardW - 90, 24);
    _fakeNameSwitch.frame     = CGRectMake(swX, rowY + 6, 51, 31); rowY += rowH;
    _fastReloadLabel.frame    = CGRectMake(16, rowY + 10, cardW - 90, 24);
    _fastReloadSwitch.frame   = CGRectMake(swX, rowY + 6, 51, 31); rowY += rowH;
    _streamerLabel.frame      = CGRectMake(16, rowY + 10, cardW - 90, 24);
    _streamerSwitch.frame     = CGRectMake(swX, rowY + 6, 51, 31); rowY += rowH;
    _behindWallLabel.frame    = CGRectMake(16, rowY + 10, cardW - 90, 24);
    _behindWallSwitch.frame   = CGRectMake(swX, rowY + 6, 51, 31);
    y = CGRectGetMaxY(_functionsCard.frame) + 12;

    // Log
    CGFloat logH = 180.0f;
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

    // Status
    CGFloat statusH = 64.0f;
    _statusCard.frame = CGRectMake(xPad, y, cardW, statusH);
    _statusDot.frame = CGRectMake(16, 27, 10, 10);
    _openGameButton.frame = CGRectMake(cardW - 112, 15, 98, 34);
    _statusLabel.frame = CGRectMake(36, 18, cardW - 112 - 44, 28);
    y = CGRectGetMaxY(_statusCard.frame) + 12;

    // License + Auth
    CGFloat halfW = (cardW - gap) * 0.5f;
    CGFloat halfH = 92.0f;
    _licenseCard.frame = CGRectMake(xPad, y, halfW, halfH);
    _authCard.frame = CGRectMake(xPad + halfW + gap, y, halfW, halfH);
    _licenseTitleLabel.frame = CGRectMake(14, 12, halfW - 28, 18);
    _licenseValueLabel.frame = CGRectMake(14, 36, halfW - 28, 46);
    _authTitleLabel.frame = CGRectMake(14, 12, halfW - 28, 18);
    _authValueLabel.frame = CGRectMake(14, 40, halfW - 28, 36);
    y = CGRectGetMaxY(_licenseCard.frame) + 12;

    // Support
    CGFloat supportH = 72.0f;
    _supportCard.frame = CGRectMake(xPad, y, cardW, supportH);
    _joinButton.frame = CGRectMake(cardW - 92, 19, 78, 34);
    _supportTitleLabel.frame = CGRectMake(16, 16, cardW - 120, 22);
    _supportSubtitleLabel.frame = CGRectMake(16, 40, cardW - 120, 18);
    y = CGRectGetMaxY(_supportCard.frame) + 12;

    // Extra
    CGFloat extraH = 96.0f;
    _extraCard.frame = CGRectMake(xPad, y, cardW, extraH);
    _autoCleanLabel.frame = CGRectMake(16, 16, cardW - 90, 22);
    CGSize sw = _autoCleanSwitch.intrinsicContentSize;
    _autoCleanSwitch.frame = CGRectMake(cardW - sw.width - 16, 14, sw.width, sw.height);
    _authorizationLabel.frame = CGRectMake(16, 52, cardW - 150, 28);
    _authorizationButton.frame = CGRectMake(cardW - 132, 52, 116, 28);
    y = CGRectGetMaxY(_extraCard.frame) + 16;

    _footerLabel.frame = CGRectMake(xPad, y, cardW, 36);
    y = CGRectGetMaxY(_footerLabel.frame) + 24 + insets.bottom;

    _contentView.frame = CGRectMake(0, 0, contentW, MAX(y, height));
    _scrollView.contentSize = _contentView.bounds.size;
}

#pragma mark - Version

- (void)versionCardTapped:(UIButton *)sender {
    BOOL pickMax = (sender.tag == 2);
    GameTargetSetSelectedId(pickMax ? @"ffmax" : @"ff");
    [self updateVersionSelectionUI];
    [self refreshHUDState];
}

- (void)updateVersionSelectionUI {
    BOOL isMax = GameTargetIsMax();
    UIColor *selected = MDThemeBlue();
    _ffMaxCard.layer.borderWidth = 2.0f;
    _ffCard.layer.borderWidth = 2.0f;
    _ffMaxCard.layer.borderColor = (isMax ? selected : MDThemeLine()).CGColor;
    _ffCard.layer.borderColor = (!isMax ? selected : MDThemeLine()).CGColor;
    _ffMaxCard.backgroundColor = isMax ? MDThemePanel2() : MDThemePanel();
    _ffCard.backgroundColor = !isMax ? MDThemePanel2() : MDThemePanel();
    UIImage *icon = [self imageNamedWebPOrPNG:isMax ? @"ffmax" : @"ff"];
    if (icon) _controlIconView.image = icon;
}

- (void)appBecameActive {
    GameOffsetsReload();
    [self updateVersionSelectionUI];
    [self refreshHUDState];
}

- (BOOL)isGameRunning { return GameTargetIsRunning(); }

- (void)startPollingGameState {
    __weak __typeof(self) weakSelf = self;
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshHUDState];
    }];
}

#pragma mark - Toggle handlers

- (void)autoCleanSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBool(@"AutoVarCleanBeforeHUD", sender.on);
    ESPPrefsSync();
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
    ESPPrefsSetFloat(@"CamPCValue", v);
    ESPSyncFromPrefs();
}

- (void)silentSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"AimSilent", sender.on);
    ESPSyncFromPrefs();
}

- (void)brutalSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Norecoil", sender.on);
    if (sender.on) {
        ESPPrefsSetBoolLive(@"Speed", NO);
    }
    ESPSyncFromPrefs();
}

- (void)fakeNameSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"SetName", sender.on);
    ESPSyncFromPrefs();
}

- (void)fastReloadSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"FastReload", sender.on);
    if (sender.on && ESPPrefsFloat(@"FastReloadSpeed", 1.0f) <= 1.0f) {
        ESPPrefsSetFloat(@"FastReloadSpeed", 5.0f);
    }
    ESPSyncFromPrefs();
}

- (void)streamerSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"StreamerMode", sender.on);
    ESPSyncFromPrefs();
}

- (void)behindWallSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"AimBehindWall", sender.on);
    ESPSetAimBehindWallLive(sender.on);
    ESPSyncFromPrefs();
}

#pragma mark - AIM handlers

- (void)aimModeChanged:(UISegmentedControl *)sender {
    int idx = (int)sender.selectedSegmentIndex;
    if (idx < 0) idx = 0;
    if (idx > 3) idx = 3;
    ESPPrefsSetFloat(@"TriggerMode", (float)idx);
    ESPPrefsSync();
    ESPSyncFromPrefs();
}

- (void)aimPosChanged:(UISegmentedControl *)sender {
    int idx = (int)sender.selectedSegmentIndex;
    if (idx < 0) idx = 0;
    if (idx > 2) idx = 2;
    ESPPrefsSetFloat(@"AimPos", (float)idx);
    ESPPrefsSync();
    ESPSyncFromPrefs();
}

- (void)aimSphereChanged:(UISegmentedControl *)sender {
    int idx = (int)sender.selectedSegmentIndex;
    if (idx < 0) idx = 0;
    if (idx > 2) idx = 2;
    ESPPrefsSetFloat(@"AimSphereMode", (float)idx);
    ESPPrefsSetBool(@"Aim360", idx == 2);
    ESPPrefsSync();
    ESPSyncFromPrefs();
    BOOL hideFov = (idx != 0);
    _aimFovTitleLabel.hidden = hideFov;
    _aimFovSlider.hidden = hideFov;
    _aimFovValueLabel.hidden = hideFov;
}

- (void)aimFovChanged:(UISlider *)sender {
    float v = sender.value;
    _aimFovTitleLabel.text = [NSString stringWithFormat:@"Vòng FOV: %.0f", v];
    _aimFovValueLabel.text = [NSString stringWithFormat:@"%.0f", v];
    ESPPrefsSetFloat(@"Fov", v);
    ESPSyncFromPrefs();
}

- (void)aimDistChanged:(UISlider *)sender {
    float v = sender.value;
    _aimDistTitleLabel.text = [NSString stringWithFormat:@"Cự ly Aim: %.0fm", v];
    _aimDistValueLabel.text = [NSString stringWithFormat:@"%.0f", v];
    ESPPrefsSetFloat(@"AimDistance", v);
    ESPSyncFromPrefs();
}

#pragma mark - Start / Open game

- (void)startButtonTapped:(UIButton *)sender {
    (void)sender;
    if (IsHUDEnabled()) {
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
    if ([app canOpenURL:url]) { [app openURL:url options:@{} completionHandler:nil]; return; }
    NSArray<NSString *> *fallbacks = GameTargetIsMax() ? @[ @"freefiremax://", @"ffmax://" ] : @[ @"freefireth://", @"freefire://" ];
    for (NSString *scheme in fallbacks) {
        NSURL *u = [NSURL URLWithString:scheme];
        if ([app canOpenURL:u]) { [app openURL:u options:@{} completionHandler:nil]; return; }
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Không mở được game" message:@"Hãy mở Free Fire / Free Fire MAX thủ công, rồi quay lại nhấn Bắt đầu." preferredStyle:UIAlertControllerStyleAlert];
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

#pragma mark - Log

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

#pragma mark - refreshHUDState

- (void)refreshHUDState {
    if (!self.isViewLoaded) return;
    GameOffsetsReload();
    BOOL gameIsRunning = [self isGameRunning];
    BOOL hudIsEnabled = IsHUDEnabled();
    _gameMissingStreak = gameIsRunning ? 0 : _gameMissingStreak + 1;
    BOOL gameIsAvailable = gameIsRunning || _gameMissingStreak < 8;
    if (gameIsRunning) {
        _statusDot.backgroundColor = [self accentBlue];
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
        _startButton.backgroundColor = [self accentBlue];
    }

    static CFTimeInterval s_lastSync = 0;
    if (now - s_lastSync > 1.0) {
        s_lastSync = now;
        int trig = (int)ESPPrefsFloat(@"TriggerMode", 0.0f);
        if (trig >= 0 && trig <= 3 && _aimModeSegment.selectedSegmentIndex != trig) {
            _aimModeSegment.selectedSegmentIndex = trig;
        }
        int pos = (int)ESPPrefsFloat(@"AimPos", 0.0f);
        if (pos >= 0 && pos <= 2 && _aimPosSegment.selectedSegmentIndex != pos) {
            _aimPosSegment.selectedSegmentIndex = pos;
        }
        int sphere = (int)ESPPrefsFloat(@"AimSphereMode", 0.0f);
        if (sphere >= 0 && sphere <= 2 && _aimSphereSegment.selectedSegmentIndex != sphere) {
            _aimSphereSegment.selectedSegmentIndex = sphere;
            BOOL hideFov = (sphere != 0);
            _aimFovTitleLabel.hidden = hideFov;
            _aimFovSlider.hidden = hideFov;
            _aimFovValueLabel.hidden = hideFov;
        }
        _silentSwitch.on     = ESPPrefsBool(@"AimSilent", NO);
        _brutalSwitch.on     = ESPPrefsBool(@"Norecoil", NO);
        _fakeNameSwitch.on   = ESPPrefsBool(@"SetName", NO);
        _fastReloadSwitch.on = ESPPrefsBool(@"FastReload", NO);
        _streamerSwitch.on   = ESPPrefsBool(@"StreamerMode", NO);
        _behindWallSwitch.on = ESPPrefsBool(@"AimBehindWall", NO);
    }
}

@end
