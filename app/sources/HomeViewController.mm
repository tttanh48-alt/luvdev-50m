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
#import "../DSMemory.h"

static HomeViewController *g_activeLogVC = nil;
static void HomeVCBootLogSink(NSString *line);

#import <QuartzCore/QuartzCore.h>
#import <SafariServices/SafariServices.h>

static const CGFloat kMenuButtonSize = 56.0f;

@interface HomeViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *langBtn;
@property (nonatomic, strong) UIButton *themeBtn;
@property (nonatomic, strong) UIButton *modMenuBtn;

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
@property (nonatomic, strong) UILabel *statusAttachLabel;
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
@property (nonatomic, strong) UILabel *autoCleanPeriodicLabel;
@property (nonatomic, strong) UISwitch *autoCleanPeriodicSwitch;
@property (nonatomic, strong) UILabel *antiBanLabel;
@property (nonatomic, strong) UISwitch *antiBanSwitch;
@property (nonatomic, strong) UILabel *antiCrashLabel;
@property (nonatomic, strong) UISwitch *antiCrashSwitch;
@property (nonatomic, strong) UILabel *authorizationLabel;
@property (nonatomic, strong) UIButton *authorizationButton;
@property (nonatomic, strong) UIButton *settingsBtn;
@property (nonatomic, strong) UIView *logCard;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UIButton *trashBtn;
@property (nonatomic, strong) UILabel *versionFooterLabel;
@property (nonatomic, strong) UIButton *resetBtn;

// Extended quick toggles
@property (nonatomic, strong) UIView *functionsCard;
@property (nonatomic, strong) UILabel *brutalLabel;
@property (nonatomic, strong) UISwitch *brutalSwitch;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UISwitch *speedSwitch;
@property (nonatomic, strong) UILabel *fastReloadLabel;
@property (nonatomic, strong) UISwitch *fastReloadSwitch;
@property (nonatomic, strong) UILabel *aimSilentLabel;
@property (nonatomic, strong) UISwitch *aimSilentSwitch;
@property (nonatomic, strong) UILabel *aimBehindWallLabel;
@property (nonatomic, strong) UISwitch *aimBehindWallSwitch;
@property (nonatomic, strong) UILabel *streamerLabel;
@property (nonatomic, strong) UISwitch *streamerSwitch;

@property (nonatomic, strong) UIView *espTogglesCard;
@property (nonatomic, strong) UILabel *espBoxLabel;
@property (nonatomic, strong) UISwitch *espBoxSwitch;
@property (nonatomic, strong) UILabel *espLineLabel;
@property (nonatomic, strong) UISwitch *espLineSwitch;
@property (nonatomic, strong) UILabel *espBoneLabel;
@property (nonatomic, strong) UISwitch *espBoneSwitch;
@property (nonatomic, strong) UILabel *espHealthLabel;
@property (nonatomic, strong) UISwitch *espHealthSwitch;
@property (nonatomic, strong) UILabel *espNameLabel;
@property (nonatomic, strong) UISwitch *espNameSwitch;
@property (nonatomic, strong) UILabel *espDistanceLabel;
@property (nonatomic, strong) UISwitch *espDistanceSwitch;
@property (nonatomic, strong) UILabel *espBotLabel;
@property (nonatomic, strong) UISwitch *espBotSwitch;

@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) NSInteger gameMissingStreak;
@property (nonatomic, assign) CFTimeInterval pendingHUDEnableUntil;
@property (nonatomic, assign) NSInteger hudRequestSerial;
@property (nonatomic, assign) BOOL isVietnamese;

- (void)appendBootLog:(NSString *)line;
@end

@implementation HomeViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    MDThemeLoadFromPrefs();
    self.isVietnamese = ESPPrefsBool(@"AppLanguage", NO);
    [self buildUI];
    _gameMissingStreak = 0;
    _pendingHUDEnableUntil = 0;
    _hudRequestSerial = 0;

    GameOffsetsReload();
    [self updateVersionSelectionUI];
    [self updateAuthorizationPresentation];
    [self refreshHUDState];
    [self applyTheme];
    [self refreshLangThemeButtons];

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
    [self updateVersionSelectionUI];
    [self syncQuickTogglesFromPrefs];
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

- (NSString *)loc:(NSString *)en :(NSString *)vi {
    return self.isVietnamese ? vi : en;
}

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

- (void)openModMenuTapped:(id)sender {
    (void)sender;
    if (!IsHUDEnabled()) {
        SetHUDEnabled(YES);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"OpenModMenuNotification" object:nil];
        });
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"OpenModMenuNotification" object:nil];
    }
    [self refreshHUDState];
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
    if (_statusAttachLabel) _statusAttachLabel.textColor = MDThemeMuted();
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
    _autoCleanPeriodicLabel.textColor = MDThemeText();
    _autoCleanPeriodicSwitch.onTintColor = MDThemeAccent();
    _antiBanLabel.textColor = MDThemeText();
    _antiBanSwitch.onTintColor = MDThemeAccent();
    _antiCrashLabel.textColor = MDThemeText();
    _antiCrashSwitch.onTintColor = MDThemeAccent();
    [_authorizationButton setTitleColor:MDThemeAccent() forState:UIControlStateNormal];
    _settingsBtn.backgroundColor = MDThemePanel2();
    _settingsBtn.layer.borderColor = MDThemeLine().CGColor;
    _settingsBtn.tintColor = MDThemeText();
    _trashBtn.backgroundColor = MDThemePanel2();
    _trashBtn.layer.borderColor = MDThemeLine().CGColor;
    _trashBtn.tintColor = MDThemeText();
    if (_langBtn) {
        _langBtn.backgroundColor = MDThemePanel2();
        _langBtn.layer.borderColor = MDThemeLine().CGColor;
        [_langBtn setTitleColor:MDThemeText() forState:UIControlStateNormal];
    }
    if (_themeBtn) {
        _themeBtn.backgroundColor = MDThemePanel2();
        _themeBtn.layer.borderColor = MDThemeLine().CGColor;
        _themeBtn.tintColor = MDThemeText();
    }
    if (_modMenuBtn) {
        _modMenuBtn.backgroundColor = MDThemePanel2();
        _modMenuBtn.layer.borderColor = MDThemeLine().CGColor;
        _modMenuBtn.tintColor = MDThemeText();
    }
    if (_resetBtn) {
        _resetBtn.backgroundColor = MDThemePanel2();
        _resetBtn.layer.borderColor = MDThemeLine().CGColor;
        [_resetBtn setTitleColor:MDThemeText() forState:UIControlStateNormal];
    }
    if (_versionFooterLabel) {
        _versionFooterLabel.textColor = MDThemeMuted();
    }
    for (UISwitch *sw in @[
        _brutalSwitch, _speedSwitch, _fastReloadSwitch, _aimSilentSwitch,
        _aimBehindWallSwitch, _streamerSwitch,
        _espBoxSwitch, _espLineSwitch, _espBoneSwitch, _espHealthSwitch,
        _espNameSwitch, _espDistanceSwitch, _espBotSwitch
    ]) {
        if (sw) sw.onTintColor = MDThemeAccent();
    }
    for (UILabel *lb in @[
        _brutalLabel, _speedLabel, _fastReloadLabel, _aimSilentLabel,
        _aimBehindWallLabel, _streamerLabel,
        _espBoxLabel, _espLineLabel, _espBoneLabel, _espHealthLabel,
        _espNameLabel, _espDistanceLabel, _espBotLabel
    ]) {
        if (lb) lb.textColor = MDThemeText();
    }
    if (_functionsCard) {
        _functionsCard.backgroundColor = MDThemePanel();
        _functionsCard.layer.borderColor = MDThemeLine().CGColor;
        _functionsCard.layer.borderWidth = 1.0f;
    }
    if (_espTogglesCard) {
        _espTogglesCard.backgroundColor = MDThemePanel();
        _espTogglesCard.layer.borderColor = MDThemeLine().CGColor;
        _espTogglesCard.layer.borderWidth = 1.0f;
    }
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
    if (path.length) {
        img = [UIImage imageWithContentsOfFile:path];
    }
    return img;
}

- (UIView *)makeCard {
    return MDThemeMakeCard();
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

#pragma mark - Authorization

- (void)retryAuthorization:(id)sender { (void)sender; [self beginAuthorization]; }
- (void)beginAuthorization { [self updateAuthorizationPresentation]; [self refreshHUDState]; }
- (void)revokeAuthorization { SetHUDEnabled(NO); [self updateAuthorizationPresentation]; [self refreshHUDState]; }

- (void)updateAuthorizationPresentation {
    if (!self.isViewLoaded) return;
    _authorizationLabel.text = @"No key required";
    [_authorizationButton setTitle:@"Unlocked" forState:UIControlStateNormal];
    _authorizationButton.enabled = NO;
    _licenseValueLabel.text = @"Unlimited";
    _authValueLabel.text = [self loc:@"Active" :@"Hoạt động"];
    _authValueLabel.textColor = MDThemeAccent();
    _authorizationLabel.textColor = MDThemeText();
    _autoCleanSwitch.enabled = YES;
    _autoCleanLabel.alpha = 1.0;
    _startButton.alpha = 1.0;
}

#pragma mark - UI

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

    _modMenuBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _modMenuBtn.backgroundColor = MDThemePanel2();
    _modMenuBtn.layer.cornerRadius = 10.0f;
    _modMenuBtn.layer.borderWidth = 1.0f;
    _modMenuBtn.layer.borderColor = MDThemeLine().CGColor;
    _modMenuBtn.tintColor = MDThemeText();
    [_modMenuBtn setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    [_modMenuBtn addTarget:self action:@selector(openModMenuTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_modMenuBtn];

    _langBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _langBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    _langBtn.layer.cornerRadius = 9.0f;
    _langBtn.layer.borderWidth = 1.0f;
    _langBtn.clipsToBounds = YES;
    [_langBtn addTarget:self action:@selector(langBtnTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_langBtn];

    _themeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _themeBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _themeBtn.layer.cornerRadius = 9.0f;
    _themeBtn.layer.borderWidth = 1.0f;
    _themeBtn.clipsToBounds = YES;
    [_themeBtn addTarget:self action:@selector(themeBtnTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_themeBtn];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.text = [self loc:@"Home" :@"Trang chủ"];
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
    _controlTitleLabel.text = [self loc:@"HUD Control" :@"Điều khiển HUD"];
    _controlTitleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _controlTitleLabel.textColor = [UIColor whiteColor];
    [_controlCard addSubview:_controlTitleLabel];

    _controlSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _controlSubtitleLabel.text = [self loc:@"Press Start when game is open" :@"Nhấn Bắt đầu khi game đã mở"];
    _controlSubtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _controlSubtitleLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    _controlSubtitleLabel.numberOfLines = 2;
    [_controlCard addSubview:_controlSubtitleLabel];

    _startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _startButton.backgroundColor = [self accentGreen];
    _startButton.layer.cornerRadius = 16.0f;
    _startButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_startButton setTitle:[self loc:@"Start" :@"Bắt đầu"] forState:UIControlStateNormal];
    [_startButton addTarget:self action:@selector(startButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_controlCard addSubview:_startButton];

    // Quick toggles card (Aimbot / ESP / CamPC)
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
    _camLabel.text = [self loc:@"Camera Zoom (CamPC)" :@"Camera Xa (CamPC)"];
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

    // Boot log card
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
    _logTextView.text = @"[MINHDUC] ready.\nPress Start to boot kernel.";
    [_logCard addSubview:_logTextView];

    // Version section
    _versionSectionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _versionSectionLabel.text = [self loc:@"Game selection:" :@"Lựa chọn phiên bản:"];
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
    _statusLabel.text = [self loc:@"Status · Game not running" :@"Trạng thái · Game chưa chạy"];
    [_statusCard addSubview:_statusLabel];

    _statusAttachLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusAttachLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    _statusAttachLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    _statusAttachLabel.text = @"[attach: —]";
    [_statusCard addSubview:_statusAttachLabel];

    _openGameButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _openGameButton.backgroundColor = [self accentOrange];
    _openGameButton.layer.cornerRadius = 14.0f;
    _openGameButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [_openGameButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_openGameButton setTitle:[self loc:@"Open Game" :@"Vào Game"] forState:UIControlStateNormal];
    [_openGameButton addTarget:self action:@selector(openGameTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_statusCard addSubview:_openGameButton];

    // License + auth
    _licenseCard = [self makeCard];
    [_contentView addSubview:_licenseCard];
    _licenseTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _licenseTitleLabel.text = [self loc:@"License" :@"Giấy phép"];
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
    _authTitleLabel.text = [self loc:@"Status" :@"Trạng thái"];
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
    _supportTitleLabel.text = [self loc:@"Contact support" :@"Liên hệ hỗ trợ"];
    _supportTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _supportTitleLabel.textColor = [UIColor whiteColor];
    [_supportCard addSubview:_supportTitleLabel];
    _supportSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportSubtitleLabel.text = [self loc:@"Press Join for support" :@"Nhấn Join để nhận hỗ trợ"];
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

    // Extra card
    _extraCard = [self makeCard];
    [_contentView addSubview:_extraCard];

    _autoCleanLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _autoCleanLabel.text = [self loc:@"VarClean before HUD" :@"Dọn Var trước khi bật HUD"];
    _autoCleanLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _autoCleanLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1.0f];
    [_extraCard addSubview:_autoCleanLabel];

    _autoCleanSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _autoCleanSwitch.onTintColor = MDThemeAccent();
    _autoCleanSwitch.on = ESPPrefsBool(@"AutoVarCleanBeforeHUD", NO);
    [_autoCleanSwitch addTarget:self action:@selector(autoCleanSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_extraCard addSubview:_autoCleanSwitch];

    _autoCleanPeriodicLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _autoCleanPeriodicLabel.text = [self loc:@"Auto clean RAM periodic" :@"Tự dọn RAM định kỳ"];
    _autoCleanPeriodicLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _autoCleanPeriodicLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1.0f];
    [_extraCard addSubview:_autoCleanPeriodicLabel];

    _autoCleanPeriodicSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _autoCleanPeriodicSwitch.onTintColor = MDThemeAccent();
    _autoCleanPeriodicSwitch.on = ESPPrefsBool(@"AutoCleanRAMPeriodic", NO);
    [_autoCleanPeriodicSwitch addTarget:self action:@selector(autoCleanPeriodicChanged:) forControlEvents:UIControlEventValueChanged];
    [_extraCard addSubview:_autoCleanPeriodicSwitch];

    _antiBanLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _antiBanLabel.text = [self loc:@"Anti-ban mode" :@"Chế độ chống ban"];
    _antiBanLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _antiBanLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1.0f];
    [_extraCard addSubview:_antiBanLabel];

    _antiBanSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _antiBanSwitch.onTintColor = MDThemeAccent();
    _antiBanSwitch.on = ESPPrefsBool(@"AntiBanMax", NO);
    [_antiBanSwitch addTarget:self action:@selector(antiBanChanged:) forControlEvents:UIControlEventValueChanged];
    [_extraCard addSubview:_antiBanSwitch];

    _antiCrashLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _antiCrashLabel.text = [self loc:@"Anti-crash RAM" :@"Chống crash RAM"];
    _antiCrashLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _antiCrashLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1.0f];
    [_extraCard addSubview:_antiCrashLabel];

    _antiCrashSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _antiCrashSwitch.onTintColor = MDThemeAccent();
    _antiCrashSwitch.on = ESPPrefsBool(@"AntiCrashRAM", NO);
    [_antiCrashSwitch addTarget:self action:@selector(antiCrashChanged:) forControlEvents:UIControlEventValueChanged];
    [_extraCard addSubview:_antiCrashSwitch];

    _authorizationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authorizationLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _authorizationLabel.textAlignment = NSTextAlignmentLeft;
    [_extraCard addSubview:_authorizationLabel];

    _authorizationButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _authorizationButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [_authorizationButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_authorizationButton addTarget:self action:@selector(retryAuthorization:) forControlEvents:UIControlEventTouchUpInside];
    [_extraCard addSubview:_authorizationButton];

    _resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _resetBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _resetBtn.layer.cornerRadius = 10.0f;
    _resetBtn.layer.borderWidth = 1.0f;
    _resetBtn.clipsToBounds = YES;
    [_resetBtn setTitle:[self loc:@"Reset all settings" :@"Reset toàn bộ cài đặt"] forState:UIControlStateNormal];
    [_resetBtn addTarget:self action:@selector(resetAllTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_extraCard addSubview:_resetBtn];

    // Functions card
    _functionsCard = [self makeCard];
    [_contentView addSubview:_functionsCard];

    _brutalLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _brutalLabel.text = @"Brutal (Speed)";
    _brutalLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _brutalLabel.textColor = [UIColor whiteColor];
    [_functionsCard addSubview:_brutalLabel];

    _brutalSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _brutalSwitch.onTintColor = MDThemeAccent();
    _brutalSwitch.on = ESPPrefsBool(@"Norecoil", NO);
    [_brutalSwitch addTarget:self action:@selector(brutalSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_functionsCard addSubview:_brutalSwitch];

    _speedLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _speedLabel.text = @"Speed Boost";
    _speedLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _speedLabel.textColor = [UIColor whiteColor];
    [_functionsCard addSubview:_speedLabel];

    _speedSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _speedSwitch.onTintColor = MDThemeAccent();
    _speedSwitch.on = ESPPrefsBool(@"Speed", NO) && !ESPPrefsBool(@"Norecoil", NO);
    [_speedSwitch addTarget:self action:@selector(speedSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_functionsCard addSubview:_speedSwitch];

    _fastReloadLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _fastReloadLabel.text = @"Fast Reload";
    _fastReloadLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _fastReloadLabel.textColor = [UIColor whiteColor];
    [_functionsCard addSubview:_fastReloadLabel];

    _fastReloadSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _fastReloadSwitch.onTintColor = MDThemeAccent();
    _fastReloadSwitch.on = ESPPrefsBool(@"FastReload", NO);
    [_fastReloadSwitch addTarget:self action:@selector(fastReloadSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_functionsCard addSubview:_fastReloadSwitch];

    _aimSilentLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimSilentLabel.text = @"Aim Silent (Magic)";
    _aimSilentLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _aimSilentLabel.textColor = [UIColor whiteColor];
    [_functionsCard addSubview:_aimSilentLabel];

    _aimSilentSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _aimSilentSwitch.onTintColor = MDThemeAccent();
    _aimSilentSwitch.on = ESPPrefsBool(@"AimSilent", NO);
    [_aimSilentSwitch addTarget:self action:@selector(aimSilentSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_functionsCard addSubview:_aimSilentSwitch];

    _aimBehindWallLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimBehindWallLabel.text = @"Aim Behind Wall";
    _aimBehindWallLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _aimBehindWallLabel.textColor = [UIColor whiteColor];
    [_functionsCard addSubview:_aimBehindWallLabel];

    _aimBehindWallSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _aimBehindWallSwitch.onTintColor = MDThemeAccent();
    _aimBehindWallSwitch.on = ESPPrefsBool(@"AimBehindWall", NO);
    [_aimBehindWallSwitch addTarget:self action:@selector(aimBehindWallSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_functionsCard addSubview:_aimBehindWallSwitch];

    _streamerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _streamerLabel.text = @"Streamer Mode";
    _streamerLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _streamerLabel.textColor = [UIColor whiteColor];
    [_functionsCard addSubview:_streamerLabel];

    _streamerSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _streamerSwitch.onTintColor = MDThemeAccent();
    _streamerSwitch.on = ESPPrefsBool(@"StreamerMode", NO);
    [_streamerSwitch addTarget:self action:@selector(streamerSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_functionsCard addSubview:_streamerSwitch];

    // ESP sub-toggles card
    _espTogglesCard = [self makeCard];
    [_contentView addSubview:_espTogglesCard];

    _espBoxLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espBoxLabel.text = @"Box";
    _espBoxLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _espBoxLabel.textColor = [UIColor whiteColor];
    [_espTogglesCard addSubview:_espBoxLabel];

    _espBoxSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espBoxSwitch.onTintColor = MDThemeAccent();
    _espBoxSwitch.on = ESPPrefsBool(@"Box", YES);
    [_espBoxSwitch addTarget:self action:@selector(espBoxSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_espTogglesCard addSubview:_espBoxSwitch];

    _espLineLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espLineLabel.text = @"Line";
    _espLineLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _espLineLabel.textColor = [UIColor whiteColor];
    [_espTogglesCard addSubview:_espLineLabel];

    _espLineSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espLineSwitch.onTintColor = MDThemeAccent();
    _espLineSwitch.on = ESPPrefsBool(@"Line", YES);
    [_espLineSwitch addTarget:self action:@selector(espLineSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_espTogglesCard addSubview:_espLineSwitch];

    _espBoneLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espBoneLabel.text = @"Bone";
    _espBoneLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _espBoneLabel.textColor = [UIColor whiteColor];
    [_espTogglesCard addSubview:_espBoneLabel];

    _espBoneSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espBoneSwitch.onTintColor = MDThemeAccent();
    _espBoneSwitch.on = ESPPrefsBool(@"Bone", YES);
    [_espBoneSwitch addTarget:self action:@selector(espBoneSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_espTogglesCard addSubview:_espBoneSwitch];

    _espHealthLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espHealthLabel.text = @"Health";
    _espHealthLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _espHealthLabel.textColor = [UIColor whiteColor];
    [_espTogglesCard addSubview:_espHealthLabel];

    _espHealthSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espHealthSwitch.onTintColor = MDThemeAccent();
    _espHealthSwitch.on = ESPPrefsBool(@"Health", YES);
    [_espHealthSwitch addTarget:self action:@selector(espHealthSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_espTogglesCard addSubview:_espHealthSwitch];

    _espNameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espNameLabel.text = @"Name";
    _espNameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _espNameLabel.textColor = [UIColor whiteColor];
    [_espTogglesCard addSubview:_espNameLabel];

    _espNameSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espNameSwitch.onTintColor = MDThemeAccent();
    _espNameSwitch.on = ESPPrefsBool(@"Name", YES);
    [_espNameSwitch addTarget:self action:@selector(espNameSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_espTogglesCard addSubview:_espNameSwitch];

    _espDistanceLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espDistanceLabel.text = @"Distance";
    _espDistanceLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _espDistanceLabel.textColor = [UIColor whiteColor];
    [_espTogglesCard addSubview:_espDistanceLabel];

    _espDistanceSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espDistanceSwitch.onTintColor = MDThemeAccent();
    _espDistanceSwitch.on = ESPPrefsBool(@"Distance", YES);
    [_espDistanceSwitch addTarget:self action:@selector(espDistanceSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_espTogglesCard addSubview:_espDistanceSwitch];

    _espBotLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espBotLabel.text = @"Draw Bots";
    _espBotLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _espBotLabel.textColor = [UIColor whiteColor];
    [_espTogglesCard addSubview:_espBotLabel];

    _espBotSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espBotSwitch.onTintColor = MDThemeAccent();
    _espBotSwitch.on = ESPPrefsBool(@"EspBot", NO);
    [_espBotSwitch addTarget:self action:@selector(espBotSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_espTogglesCard addSubview:_espBotSwitch];

    // Footer version label
    _versionFooterLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    NSString *appVer = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (!appVer.length) appVer = @"1.0.0";
    _versionFooterLabel.text = [NSString stringWithFormat:@"MinhDuc-FF v%@ • @Bolaminhduc", appVer];
    _versionFooterLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    _versionFooterLabel.textColor = MDThemeMuted();
    _versionFooterLabel.textAlignment = NSTextAlignmentCenter;
    _versionFooterLabel.numberOfLines = 2;
    [_contentView addSubview:_versionFooterLabel];

    [self refreshLangThemeButtons];
}

- (void)refreshLangThemeButtons {
    if (_langBtn) [_langBtn setTitle:(self.isVietnamese ? @"VI" : @"EN") forState:UIControlStateNormal];
    if (_themeBtn) {
        BOOL isLight = ESPPrefsBool(@"AppThemeMode", NO);
        [_themeBtn setTitle:(isLight ? @"☀" : @"🌙") forState:UIControlStateNormal];
    }
}

- (void)langBtnTapped:(UIButton *)sender {
    (void)sender;
    self.isVietnamese = !self.isVietnamese;
    ESPPrefsSetBool(@"AppLanguage", self.isVietnamese);
    ESPPrefsSync();
    [self refreshLangThemeButtons];
    _titleLabel.text = [self loc:@"Home" :@"Trang chủ"];
    _controlTitleLabel.text = [self loc:@"HUD Control" :@"Điều khiển HUD"];
    _controlSubtitleLabel.text = [self loc:@"Press Start when game is open" :@"Nhấn Bắt đầu khi game đã mở"];
    [_startButton setTitle:[self loc:@"Start" :@"Bắt đầu"] forState:UIControlStateNormal];
    _camLabel.text = [self loc:@"Camera Zoom (CamPC)" :@"Camera Xa (CamPC)"];
    _versionSectionLabel.text = [self loc:@"Game selection:" :@"Lựa chọn phiên bản:"];
    [_openGameButton setTitle:[self loc:@"Open Game" :@"Vào Game"] forState:UIControlStateNormal];
    _licenseTitleLabel.text = [self loc:@"License" :@"Giấy phép"];
    _authTitleLabel.text = [self loc:@"Status" :@"Trạng thái"];
    _supportTitleLabel.text = [self loc:@"Contact support" :@"Liên hệ hỗ trợ"];
    _supportSubtitleLabel.text = [self loc:@"Press Join for support" :@"Nhấn Join để nhận hỗ trợ"];
    _autoCleanLabel.text = [self loc:@"VarClean before HUD" :@"Dọn Var trước khi bật HUD"];
    _autoCleanPeriodicLabel.text = [self loc:@"Auto clean RAM periodic" :@"Tự dọn RAM định kỳ"];
    _antiBanLabel.text = [self loc:@"Anti-ban mode" :@"Chế độ chống ban"];
    _antiCrashLabel.text = [self loc:@"Anti-crash RAM" :@"Chống crash RAM"];
    [_resetBtn setTitle:[self loc:@"Reset all settings" :@"Reset toàn bộ cài đặt"] forState:UIControlStateNormal];
    [self refreshHUDState];
}

- (void)themeBtnTapped:(UIButton *)sender {
    (void)sender;
    BOOL isLight = ESPPrefsBool(@"AppThemeMode", NO);
    ESPPrefsSetBool(@"AppThemeMode", !isLight);
    ESPPrefsSync();
    [[NSNotificationCenter defaultCenter] postNotificationName:MDThemeDidChangeNotification object:nil];
    [self refreshLangThemeButtons];
    [self applyTheme];
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
    _modMenuBtn.frame = CGRectMake(CGRectGetMinX(_trashBtn.frame) - 10 - gear, insets.top + 8, gear, gear);
    _themeBtn.frame = CGRectMake(CGRectGetMinX(_modMenuBtn.frame) - 10 - gear, insets.top + 8, gear, gear);
    _langBtn.frame = CGRectMake(CGRectGetMinX(_themeBtn.frame) - 10 - 42, insets.top + 8, 42, gear);

    CGFloat contentW = width;
    CGFloat xPad = 16.0f;
    CGFloat cardW = contentW - xPad * 2.0f;
    CGFloat y = insets.top + 52.0f;

    _titleLabel.frame = CGRectMake(xPad + 6, y, cardW - 12 - 80, 40);
    y = CGRectGetMaxY(_titleLabel.frame) + 14;

    // Control card
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

    // Boot log
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

    // Status
    CGFloat statusH = 80.0f;
    _statusCard.frame = CGRectMake(xPad, y, cardW, statusH);
    _statusDot.frame = CGRectMake(16, 24, 10, 10);
    _openGameButton.frame = CGRectMake(cardW - 112, 22, 98, 34);
    _statusLabel.frame = CGRectMake(36, 16, cardW - 112 - 44, 24);
    _statusAttachLabel.frame = CGRectMake(36, 42, cardW - 112 - 44, 18);
    y = CGRectGetMaxY(_statusCard.frame) + 12;

    // License / auth
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

    // Extra card (4 switches + auth + reset)
    CGFloat extraH = 260.0f;
    _extraCard.frame = CGRectMake(xPad, y, cardW, extraH);
    CGFloat swW = 51.0f, swH = 31.0f;
    _autoCleanLabel.frame = CGRectMake(16, 14, cardW - 90, 24);
    _autoCleanSwitch.frame = CGRectMake(cardW - swW - 16, 12, swW, swH);
    _autoCleanPeriodicLabel.frame = CGRectMake(16, 54, cardW - 90, 24);
    _autoCleanPeriodicSwitch.frame = CGRectMake(cardW - swW - 16, 52, swW, swH);
    _antiBanLabel.frame = CGRectMake(16, 94, cardW - 90, 24);
    _antiBanSwitch.frame = CGRectMake(cardW - swW - 16, 92, swW, swH);
    _antiCrashLabel.frame = CGRectMake(16, 134, cardW - 90, 24);
    _antiCrashSwitch.frame = CGRectMake(cardW - swW - 16, 132, swW, swH);
    _authorizationLabel.frame = CGRectMake(16, 172, cardW - 150, 28);
    _authorizationButton.frame = CGRectMake(cardW - 132, 172, 116, 28);
    _resetBtn.frame = CGRectMake(16, 210, cardW - 32, 38);
    y = CGRectGetMaxY(_extraCard.frame) + 12;

    // Functions card (6 rows)
    CGFloat functionsH = 6 * 40.0f + 16.0f;
    _functionsCard.frame = CGRectMake(xPad, y, cardW, functionsH);
    CGFloat rowY = 8.0f;
    CGFloat switchX = cardW - 68;
    CGFloat rowH = 40.0f;
    _brutalLabel.frame        = CGRectMake(16, rowY + 8, cardW - 90, 24);
    _brutalSwitch.frame       = CGRectMake(switchX, rowY + 4, 51, 31); rowY += rowH;
    _speedLabel.frame         = CGRectMake(16, rowY + 8, cardW - 90, 24);
    _speedSwitch.frame        = CGRectMake(switchX, rowY + 4, 51, 31); rowY += rowH;
    _fastReloadLabel.frame    = CGRectMake(16, rowY + 8, cardW - 90, 24);
    _fastReloadSwitch.frame   = CGRectMake(switchX, rowY + 4, 51, 31); rowY += rowH;
    _aimSilentLabel.frame     = CGRectMake(16, rowY + 8, cardW - 90, 24);
    _aimSilentSwitch.frame    = CGRectMake(switchX, rowY + 4, 51, 31); rowY += rowH;
    _aimBehindWallLabel.frame = CGRectMake(16, rowY + 8, cardW - 90, 24);
    _aimBehindWallSwitch.frame= CGRectMake(switchX, rowY + 4, 51, 31); rowY += rowH;
    _streamerLabel.frame      = CGRectMake(16, rowY + 8, cardW - 90, 24);
    _streamerSwitch.frame     = CGRectMake(switchX, rowY + 4, 51, 31);
    y = CGRectGetMaxY(_functionsCard.frame) + 12;

    // ESP toggles card (7 rows)
    CGFloat espTogglesH = 7 * 40.0f + 16.0f;
    _espTogglesCard.frame = CGRectMake(xPad, y, cardW, espTogglesH);
    rowY = 8.0f;
    _espBoxLabel.frame      = CGRectMake(16, rowY + 8, cardW - 90, 24);
    _espBoxSwitch.frame     = CGRectMake(switchX, rowY + 4, 51, 31); rowY += rowH;
    _espLineLabel.frame     = CGRectMake(16, rowY + 8, cardW - 90, 24);
    _espLineSwitch.frame    = CGRectMake(switchX, rowY + 4, 51, 31); rowY += rowH;
    _espBoneLabel.frame     = CGRectMake(16, rowY + 8, cardW - 90, 24);
    _espBoneSwitch.frame    = CGRectMake(switchX, rowY + 4, 51, 31); rowY += rowH;
    _espHealthLabel.frame   = CGRectMake(16, rowY + 8, cardW - 90, 24);
    _espHealthSwitch.frame  = CGRectMake(switchX, rowY + 4, 51, 31); rowY += rowH;
    _espNameLabel.frame     = CGRectMake(16, rowY + 8, cardW - 90, 24);
    _espNameSwitch.frame    = CGRectMake(switchX, rowY + 4, 51, 31); rowY += rowH;
    _espDistanceLabel.frame = CGRectMake(16, rowY + 8, cardW - 90, 24);
    _espDistanceSwitch.frame= CGRectMake(switchX, rowY + 4, 51, 31); rowY += rowH;
    _espBotLabel.frame      = CGRectMake(16, rowY + 8, cardW - 90, 24);
    _espBotSwitch.frame     = CGRectMake(switchX, rowY + 4, 51, 31);
    y = CGRectGetMaxY(_espTogglesCard.frame) + 16;

    _versionFooterLabel.frame = CGRectMake(xPad, y, cardW, 36);
    y = CGRectGetMaxY(_versionFooterLabel.frame) + 24 + insets.bottom;

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
    [self refreshHUDState];
    [self refreshLangThemeButtons];
    [self syncQuickTogglesFromPrefs];
}

#pragma mark - HUD / game

- (BOOL)isGameRunning { return GameTargetIsRunning(); }

- (void)startPollingGameState {
    __weak __typeof(self) weakSelf = self;
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshHUDState];
    }];
}

#pragma mark - Original toggle handlers

- (void)autoCleanSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBool(@"AutoVarCleanBeforeHUD", sender.on);
    ESPPrefsSync();
}

- (void)autoCleanPeriodicChanged:(UISwitch *)sender {
    ESPPrefsSetBool(@"AutoCleanRAMPeriodic", sender.on);
    ESPPrefsSync();
}

- (void)antiBanChanged:(UISwitch *)sender {
    ESPPrefsSetBool(@"AntiBanMax", sender.on);
    ESPPrefsSync();
}

- (void)antiCrashChanged:(UISwitch *)sender {
    ESPPrefsSetBool(@"AntiCrashRAM", sender.on);
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

#pragma mark - Extended quick toggle handlers

- (void)brutalSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Norecoil", sender.on);
    if (sender.on) {
        ESPPrefsSetBoolLive(@"Speed", NO);
        _speedSwitch.on = NO;
    }
    ESPSyncFromPrefs();
}

- (void)speedSwitchChanged:(UISwitch *)sender {
    if (sender.on && ESPPrefsBool(@"Norecoil", NO)) {
        sender.on = NO;
        return;
    }
    ESPPrefsSetBoolLive(@"Speed", sender.on);
    ESPSyncFromPrefs();
}

- (void)fastReloadSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"FastReload", sender.on);
    if (sender.on && ESPPrefsFloat(@"FastReloadSpeed", 1.0f) <= 1.0f) {
        ESPPrefsSetFloat(@"FastReloadSpeed", 5.0f);
    }
    ESPSyncFromPrefs();
}

- (void)aimSilentSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"AimSilent", sender.on);
    ESPSyncFromPrefs();
}

- (void)aimBehindWallSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"AimBehindWall", sender.on);
    ESPSetAimBehindWallLive(sender.on);
    ESPSyncFromPrefs();
}

- (void)streamerSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"StreamerMode", sender.on);
    ESPSyncFromPrefs();
}

- (void)espBoxSwitchChanged:(UISwitch *)sender      { ESPPrefsSetBoolLive(@"Box", sender.on); ESPSyncFromPrefs(); }
- (void)espLineSwitchChanged:(UISwitch *)sender     { ESPPrefsSetBoolLive(@"Line", sender.on); ESPSyncFromPrefs(); }
- (void)espBoneSwitchChanged:(UISwitch *)sender     { ESPPrefsSetBoolLive(@"Bone", sender.on); ESPSyncFromPrefs(); }
- (void)espHealthSwitchChanged:(UISwitch *)sender   { ESPPrefsSetBoolLive(@"Health", sender.on); ESPSyncFromPrefs(); }
- (void)espNameSwitchChanged:(UISwitch *)sender     { ESPPrefsSetBoolLive(@"Name", sender.on); ESPSyncFromPrefs(); }
- (void)espDistanceSwitchChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"Distance", sender.on); ESPSyncFromPrefs(); }
- (void)espBotSwitchChanged:(UISwitch *)sender      { ESPPrefsSetBoolLive(@"EspBot", sender.on); ESPSyncFromPrefs(); }

#pragma mark - Sync

- (void)syncQuickTogglesFromPrefs {
    if (!self.isViewLoaded) return;
    _aimbotSwitch.on = ESPPrefsBool(@"Aimbot", NO);
    _espSwitch.on    = ESPPrefsBool(@"EnableESP", YES);
    _camSwitch.on    = ESPPrefsBool(@"CamPC", NO);
    _camSlider.value = ESPPrefsFloat(@"CamPCValue", 30.0f);
    _camValueLabel.text = [NSString stringWithFormat:@"%.0f", _camSlider.value];
    _autoCleanSwitch.on = ESPPrefsBool(@"AutoVarCleanBeforeHUD", NO);
    _autoCleanPeriodicSwitch.on = ESPPrefsBool(@"AutoCleanRAMPeriodic", NO);
    _antiBanSwitch.on = ESPPrefsBool(@"AntiBanMax", NO);
    _antiCrashSwitch.on = ESPPrefsBool(@"AntiCrashRAM", NO);

    _brutalSwitch.on        = ESPPrefsBool(@"Norecoil", NO);
    _speedSwitch.on         = ESPPrefsBool(@"Speed", NO) && !ESPPrefsBool(@"Norecoil", NO);
    _fastReloadSwitch.on    = ESPPrefsBool(@"FastReload", NO);
    _aimSilentSwitch.on     = ESPPrefsBool(@"AimSilent", NO);
    _aimBehindWallSwitch.on = ESPPrefsBool(@"AimBehindWall", NO);
    _streamerSwitch.on      = ESPPrefsBool(@"StreamerMode", NO);

    _espBoxSwitch.on      = ESPPrefsBool(@"Box", YES);
    _espLineSwitch.on     = ESPPrefsBool(@"Line", YES);
    _espBoneSwitch.on     = ESPPrefsBool(@"Bone", YES);
    _espHealthSwitch.on   = ESPPrefsBool(@"Health", YES);
    _espNameSwitch.on     = ESPPrefsBool(@"Name", YES);
    _espDistanceSwitch.on = ESPPrefsBool(@"Distance", YES);
    _espBotSwitch.on      = ESPPrefsBool(@"EspBot", NO);
}

#pragma mark - Reset

- (void)resetAllTapped:(UIButton *)sender {
    (void)sender;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[self loc:@"Reset all settings?" :@"Reset toàn bộ cài đặt?"]
                                                                   message:[self loc:@"All toggles, colors, name will be reset." :@"Toàn bộ toggle, màu, tên sẽ về mặc định."]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[self loc:@"Cancel" :@"Hủy"] style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:[self loc:@"Reset" :@"Reset"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        NSArray *keys = @[
            @"EnableESP", @"EnableESP2", @"Box", @"BoxMode", @"Bone", @"Health", @"Name",
            @"Distance", @"Line", @"EspBot", @"Weapon", @"Count", @"Alert360", @"AlertNum",
            @"EspCheckVisible", @"EspDistanceLimit",
            @"Aimbot", @"AimAssist", @"AimLegit", @"AimSilent", @"AimMaster", @"AimTypeMode",
            @"AimOnBot", @"AimIgnoreBot", @"AimIgnoreKnock", @"AimBehindWall",
            @"AimSphereMode", @"Aim360", @"TriggerMode", @"AimPos", @"AimTargetMode",
            @"Fov", @"AimDistance", @"AimSpeed", @"AimMode", @"ShowFovCircle",
            @"Norecoil", @"BrutalSpeed", @"Speed", @"SpeedValue",
            @"FastReload", @"FastReloadSpeed", @"CamPC", @"CamPCValue",
            @"StreamerMode", @"SetName", @"CustomName",
            @"BoxThickness", @"BoneThickness", @"LineThickness", @"FovThickness", @"AimAssistThickness",
            @"BoxColorMode", @"BoxColorR", @"BoxColorG", @"BoxColorB",
            @"BoneColorMode", @"BoneColorR", @"BoneColorG", @"BoneColorB",
            @"LineColorMode", @"LineColorR", @"LineColorG", @"LineColorB",
            @"FovColorMode", @"FovColorR", @"FovColorG", @"FovColorB",
            @"AimAssistColorR", @"AimAssistColorG", @"AimAssistColorB"
        ];
        AppSettingsRemoveKeys(keys);
        ESPPrefsSync();
        ESPSyncFromPrefs();
        [self syncQuickTogglesFromPrefs];
        [self applyTheme];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Start / Open game

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
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[self loc:@"Cannot open game" :@"Không mở được game"]
                         message:[self loc:@"Open Free Fire manually, then return and press Start."
                                   :@"Hãy mở Free Fire / Free Fire MAX thủ công, rồi quay lại nhấn Bắt đầu."]
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

    BOOL attached = ds_attached();
    int pid = attached ? (int)ds_pid() : 0;
    if (attached && pid > 0) {
        _statusAttachLabel.text = [NSString stringWithFormat:@"[attach: OK pid=%d]", pid];
    } else {
        _statusAttachLabel.text = @"[attach: —]";
    }

    _gameMissingStreak = gameIsRunning ? 0 : _gameMissingStreak + 1;
    BOOL gameIsAvailable = gameIsRunning || _gameMissingStreak < 8;

    if (gameIsRunning) {
        _statusDot.backgroundColor = [self accentGreen];
        NSString *name = GameTargetIsMax() ? @"Free Fire MAX" : @"Free Fire";
        _statusLabel.text = [NSString stringWithFormat:[self loc:@"Status · %@ running" :@"Trạng thái · %@ đang chạy"], name];
    } else {
        _statusDot.backgroundColor = [UIColor colorWithRed:0.9 green:0.25 blue:0.25 alpha:1.0];
        _statusLabel.text = [self loc:@"Status · Game not running" :@"Trạng thái · Game chưa chạy"];
    }

    if (!gameIsAvailable) {
        [_startButton setTitle:[self loc:@"Start" :@"Bắt đầu"] forState:UIControlStateNormal];
        _startButton.enabled = YES;
        _startButton.alpha = 1.0;
        _controlSubtitleLabel.alpha = 1.0;
        _pendingHUDEnableUntil = 0;
    } else {
        _startButton.enabled = YES;
        _startButton.alpha = 1.0;
        _controlSubtitleLabel.alpha = 1.0;

        CFTimeInterval now = CACurrentMediaTime();
        BOOL grace = _pendingHUDEnableUntil > 0 && now < _pendingHUDEnableUntil;
        if (!hudIsEnabled && grace) {
            [_startButton setTitle:[self loc:@"Enabling…" :@"Đang bật…"] forState:UIControlStateNormal];
        } else if (hudIsEnabled) {
            _pendingHUDEnableUntil = 0;
            [_startButton setTitle:[self loc:@"Stop HUD" :@"Tắt HUD"] forState:UIControlStateNormal];
            _startButton.backgroundColor = [UIColor colorWithWhite:0.35 alpha:1.0];
        } else {
            [_startButton setTitle:[self loc:@"Start" :@"Bắt đầu"] forState:UIControlStateNormal];
            _startButton.backgroundColor = [self accentGreen];
        }
    }

    // Poll sync mỗi 1s — nếu user đổi bên ModMenu thì Home switch tự cập nhật
    static CFTimeInterval s_lastSync = 0;
    CFTimeInterval nowSync = CACurrentMediaTime();
    if (nowSync - s_lastSync > 1.0) {
        s_lastSync = nowSync;
        [self syncQuickTogglesFromPrefs];
    }
}

@end
