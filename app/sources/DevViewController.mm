#import "DevViewController.h"
#import "AppSettingsViewController.h"
#import "roothide/varCleanController.h"
#import <SafariServices/SafariServices.h>
#import <objc/runtime.h>

static const void *kDevSocialURLKey = &kDevSocialURLKey;

// ============ VN TOOL profile ============
static NSString *const kDevName    = @"VN TOOL";
static NSString *const kDevTagline = @"Free Fire iOS Companion";
static NSString *const kDevTelegram = @"https://t.me/vntool";

#pragma mark - VN TOOL iOS light theme (khớp HomeViewController)

static UIColor *VNBg(void)       { return [UIColor colorWithRed:0.949 green:0.949 blue:0.969 alpha:1.0]; }
static UIColor *VNCard(void)     { return [UIColor whiteColor]; }
static UIColor *VNPanel2(void)   { return [UIColor colorWithWhite:0.90 alpha:1.0]; }
static UIColor *VNLine(void)     { return [UIColor colorWithWhite:0.85 alpha:1.0]; }
static UIColor *VNText(void)     { return [UIColor blackColor]; }
static UIColor *VNMuted(void)    { return [UIColor colorWithWhite:0.42 alpha:1.0]; }
static UIColor *VNAccent(void)   { return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0]; }
static UIColor *VNRed(void)      { return [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0]; }

static UIFont *VNFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

static UIView *VNMakeCard(void) {
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = VNCard();
    v.layer.cornerRadius = 12.0f;
    v.layer.borderWidth = 0.0f;
    v.clipsToBounds = YES;
    return v;
}

static UIButton *VNMakeIconButton(NSString *systemName) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = VNPanel2();
    b.layer.cornerRadius = 10.0f;
    b.tintColor = VNAccent();
    UIImage *img = [UIImage systemImageNamed:systemName];
    if (img) [b setImage:img forState:UIControlStateNormal];
    return b;
}

@interface DevViewController ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIView *content;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *settingsBtn;
@property (nonatomic, strong) UIButton *trashBtn;

@property (nonatomic, strong) UIView *profileCard;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *tagLabel;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong) UILabel *socialSectionLabel;
@property (nonatomic, strong) UIButton *telegramBtn;

@property (nonatomic, strong) UILabel *infoSectionLabel;
@property (nonatomic, strong) UIView *infoCard;
@property (nonatomic, strong) NSArray<UILabel *> *infoLeft;
@property (nonatomic, strong) NSArray<UILabel *> *infoRight;

@property (nonatomic, strong) UIView *footerCard;
@property (nonatomic, strong) UILabel *footerLabel;
@end

@implementation DevViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleDarkContent; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VNBg();

    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.alwaysBounceVertical = YES;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.backgroundColor = VNBg();
    [self.view addSubview:_scroll];

    _content = [[UIView alloc] initWithFrame:CGRectZero];
    _content.backgroundColor = VNBg();
    [_scroll addSubview:_content];

    // Header
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.text = @"VN TOOL";
    _titleLabel.font = VNFont(30, UIFontWeightHeavy);
    _titleLabel.textColor = VNText();
    [_content addSubview:_titleLabel];

    _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _subtitleLabel.text = @"Developed by VN Team";
    _subtitleLabel.font = VNFont(13, UIFontWeightMedium);
    _subtitleLabel.textColor = VNMuted();
    [_content addSubview:_subtitleLabel];

    _settingsBtn = VNMakeIconButton(@"gearshape.fill");
    [_settingsBtn addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    _trashBtn = VNMakeIconButton(@"trash.fill");
    [_trashBtn addTarget:self action:@selector(openVarClean) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_settingsBtn];
    [self.view addSubview:_trashBtn];

    // ============ Profile card ============
    _profileCard = VNMakeCard();
    [_content addSubview:_profileCard];

    _avatarView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarView.clipsToBounds = YES;
    _avatarView.layer.cornerRadius = 36;
    _avatarView.layer.borderWidth = 2;
    _avatarView.layer.borderColor = VNAccent().CGColor;
    _avatarView.backgroundColor = VNPanel2();
    UIImage *av = [UIImage imageNamed:@"logo"] ?: [UIImage imageNamed:@"ff"];
    if (av) _avatarView.image = av;
    [_profileCard addSubview:_avatarView];

    _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _nameLabel.text = kDevName;
    _nameLabel.font = VNFont(22, UIFontWeightHeavy);
    _nameLabel.textColor = VNText();
    [_profileCard addSubview:_nameLabel];

    _tagLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _tagLabel.text = kDevTagline;
    _tagLabel.font = VNFont(13, UIFontWeightMedium);
    _tagLabel.textColor = VNMuted();
    _tagLabel.numberOfLines = 2;
    [_profileCard addSubview:_tagLabel];

    _statusDot = [[UIView alloc] initWithFrame:CGRectZero];
    _statusDot.layer.cornerRadius = 4;
    _statusDot.backgroundColor = VNAccent();
    [_profileCard addSubview:_statusDot];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.text = @"Đang hoạt động";
    _statusLabel.font = VNFont(12, UIFontWeightSemibold);
    _statusLabel.textColor = VNAccent();
    [_profileCard addSubview:_statusLabel];

    // ============ Social section ============
    _socialSectionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _socialSectionLabel.text = @"LIÊN HỆ";
    _socialSectionLabel.font = VNFont(13, UIFontWeightBold);
    _socialSectionLabel.textColor = VNMuted();
    [_content addSubview:_socialSectionLabel];

    _telegramBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _telegramBtn.backgroundColor = VNCard();
    _telegramBtn.layer.cornerRadius = 12;
    _telegramBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    _telegramBtn.titleLabel.font = VNFont(17, UIFontWeightSemibold);
    [_telegramBtn setTitle:@"  Telegram · @vntool" forState:UIControlStateNormal];
    [_telegramBtn setTitleColor:VNText() forState:UIControlStateNormal];
    _telegramBtn.tintColor = VNAccent();
    if (@available(iOS 13.0, *)) {
        UIImage *img = [UIImage systemImageNamed:@"paperplane.fill"];
        if (img) {
            [_telegramBtn setImage:img forState:UIControlStateNormal];
            _telegramBtn.imageEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 0);
            _telegramBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 24, 0, 0);
        }
    }
    [_telegramBtn addTarget:self action:@selector(telegramTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_content addSubview:_telegramBtn];

    // ============ Info section ============
    _infoSectionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _infoSectionLabel.text = @"THÔNG TIN BUILD";
    _infoSectionLabel.font = VNFont(13, UIFontWeightBold);
    _infoSectionLabel.textColor = VNMuted();
    [_content addSubview:_infoSectionLabel];

    _infoCard = VNMakeCard();
    [_content addSubview:_infoCard];

    NSDictionary *info = [NSBundle mainBundle].infoDictionary ?: @{};
    NSString *bundleName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: @"—";
    NSString *bundleID   = info[@"CFBundleIdentifier"] ?: @"—";
    NSString *shortVer   = info[@"CFBundleShortVersionString"] ?: @"—";
    NSString *buildVer   = info[@"CFBundleVersion"] ?: @"—";
    NSArray *pairs = @[
        @[ @"Build Name",   bundleName ],
        @[ @"Build Number", buildVer   ],
        @[ @"Product ID",   bundleID   ],
        @[ @"Version",      shortVer   ],
    ];
    NSMutableArray *L = [NSMutableArray array];
    NSMutableArray *R = [NSMutableArray array];
    for (NSArray *p in pairs) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
        l.text = p[0];
        l.font = VNFont(16, UIFontWeightSemibold);
        l.textColor = VNText();
        [_infoCard addSubview:l];
        [L addObject:l];

        UILabel *r = [[UILabel alloc] initWithFrame:CGRectZero];
        r.text = p[1];
        r.font = VNFont(15, UIFontWeightMedium);
        r.textColor = VNMuted();
        r.textAlignment = NSTextAlignmentRight;
        r.adjustsFontSizeToFitWidth = YES;
        r.minimumScaleFactor = 0.7;
        [_infoCard addSubview:r];
        [R addObject:r];
    }
    _infoLeft = L;
    _infoRight = R;

    // ============ Footer ============
    _footerCard = VNMakeCard();
    [_content addSubview:_footerCard];

    _footerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _footerLabel.text = @"© 2025 VN TOOL · All rights reserved";
    _footerLabel.font = VNFont(12, UIFontWeightMedium);
    _footerLabel.textColor = VNMuted();
    _footerLabel.textAlignment = NSTextAlignmentCenter;
    [_footerCard addSubview:_footerLabel];

    [self applyTheme];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyTheme];
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

- (void)applyTheme {
    self.view.backgroundColor = VNBg();
    _titleLabel.textColor = VNText();
    _subtitleLabel.textColor = VNMuted();

    _profileCard.backgroundColor = VNCard();
    _avatarView.layer.borderColor = VNAccent().CGColor;
    _avatarView.backgroundColor = VNPanel2();
    _nameLabel.textColor = VNText();
    _tagLabel.textColor = VNMuted();
    _statusDot.backgroundColor = VNAccent();
    _statusLabel.textColor = VNAccent();

    _socialSectionLabel.textColor = VNMuted();
    _telegramBtn.backgroundColor = VNCard();
    _telegramBtn.tintColor = VNAccent();
    [_telegramBtn setTitleColor:VNText() forState:UIControlStateNormal];

    _infoSectionLabel.textColor = VNMuted();
    _infoCard.backgroundColor = VNCard();
    for (UILabel *l in _infoLeft) l.textColor = VNText();
    for (UILabel *r in _infoRight) r.textColor = VNMuted();

    _footerCard.backgroundColor = VNCard();
    _footerLabel.textColor = VNMuted();

    _settingsBtn.backgroundColor = VNPanel2();
    _settingsBtn.tintColor = VNAccent();
    _trashBtn.backgroundColor = VNPanel2();
    _trashBtn.tintColor = VNAccent();
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

- (void)telegramTapped:(UIButton *)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:kDevTelegram];
    if (!url) return;
    if (@available(iOS 9.0, *)) {
        SFSafariViewController *svc = [[SFSafariViewController alloc] initWithURL:url];
        svc.preferredBarTintColor = VNCard();
        svc.preferredControlTintColor = VNAccent();
        [self presentViewController:svc animated:YES completion:nil];
    } else {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets in = self.view.safeAreaInsets;
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    _scroll.frame = self.view.bounds;

    CGFloat gear = 44;
    _settingsBtn.frame = CGRectMake(w - in.right - 16 - gear, in.top + 8, gear, gear);
    _trashBtn.frame = CGRectMake(CGRectGetMinX(_settingsBtn.frame) - 10 - gear, in.top + 8, gear, gear);

    CGFloat pad = 16;
    CGFloat cardW = w - pad * 2;
    CGFloat y = in.top + 20;

    // Header
    _titleLabel.frame = CGRectMake(pad + 4, y, cardW - 80, 40);
    _subtitleLabel.frame = CGRectMake(pad + 4, y + 42, cardW - 80, 20);
    y = y + 42 + 20 + 22;

    // ===== Profile card =====
    CGFloat profileH = 130;
    _profileCard.frame = CGRectMake(pad, y, cardW, profileH);
    CGFloat avatarSize = 80;
    _avatarView.frame = CGRectMake(20, (profileH - avatarSize) * 0.5f, avatarSize, avatarSize);
    CGFloat textX = 20 + avatarSize + 16;
    _nameLabel.frame = CGRectMake(textX, 30, cardW - textX - 20, 30);
    _tagLabel.frame  = CGRectMake(textX, 62, cardW - textX - 20, 20);
    _statusDot.frame = CGRectMake(textX, 96, 8, 8);
    _statusLabel.frame = CGRectMake(textX + 14, 90, cardW - textX - 30, 20);
    y = CGRectGetMaxY(_profileCard.frame) + 26;

    // ===== Social section =====
    _socialSectionLabel.frame = CGRectMake(pad + 4, y, cardW - 8, 20);
    y = CGRectGetMaxY(_socialSectionLabel.frame) + 10;

    CGFloat socialH = 60;
    _telegramBtn.frame = CGRectMake(pad, y, cardW, socialH);
    y = CGRectGetMaxY(_telegramBtn.frame) + 26;

    // ===== Info section =====
    _infoSectionLabel.frame = CGRectMake(pad + 4, y, cardW - 8, 20);
    y = CGRectGetMaxY(_infoSectionLabel.frame) + 10;

    CGFloat rowH = 52;
    CGFloat infoH = rowH * _infoLeft.count;
    _infoCard.frame = CGRectMake(pad, y, cardW, infoH);
    for (NSUInteger i = 0; i < _infoLeft.count; i++) {
        _infoLeft[i].frame  = CGRectMake(20, i * rowH, cardW * 0.42f, rowH);
        _infoRight[i].frame = CGRectMake(cardW * 0.44f, i * rowH, cardW * 0.56f - 20, rowH);
    }
    y = CGRectGetMaxY(_infoCard.frame) + 26;

    // ===== Footer =====
    CGFloat footerH = 56;
    _footerCard.frame = CGRectMake(pad, y, cardW, footerH);
    _footerLabel.frame = CGRectMake(0, 0, cardW, footerH);
    y = CGRectGetMaxY(_footerCard.frame) + 24 + in.bottom;

    _content.frame = CGRectMake(0, 0, w, MAX(y, h));
    _scroll.contentSize = _content.bounds.size;
}

@end
