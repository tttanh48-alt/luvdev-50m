//
//  BootLogPopup.m — Fl0rk-style boot console popup
//  Dark card, green monospace text. Now with COPY LOG + ẨN buttons, and a
//  300-line ring buffer so a 20-second run doesn't blow up the UITextView.
//
#import "BootLogPopup.h"

@implementation BootLogPopup {
    UITextView *_tv;
    NSMutableString *_text;
}

+ (instancetype)shared {
    static BootLogPopup *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [BootLogPopup new]; });
    return s;
}

+ (void)show {
    BootLogPopup *p = [self shared];
    if (p.superview) return;

    UIWindow *window = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            window = scene.windows.firstObject;
            break;
        }
    }
    if (!window) window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;

    CGFloat w = 340, h = 480;
    p.frame = CGRectMake((window.bounds.size.width - w) / 2,
                         (window.bounds.size.height - h) / 2, w, h);
    p.layer.cornerRadius = 14;
    p.layer.shadowOpacity = 0.5;
    p.layer.shadowRadius = 20;
    p.alpha = 0;
    [window addSubview:p];
    [UIView animateWithDuration:0.25 animations:^{ p.alpha = 1; }];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.02 green:0.03 blue:0.02 alpha:0.97];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, 200, 18)];
        title.text = @"@MINHDUC";
        title.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightBold];
        title.textColor = [UIColor whiteColor];
        [self addSubview:title];

        UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(14, 30, 270, 14)];
        sub.text = @"External for Free Fire — ESP diagnostic";
        sub.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
        sub.textColor = [UIColor colorWithWhite:0.6 alpha:1];
        [self addSubview:sub];

        _text = [NSMutableString new];

        // Reserve 40px at the bottom for the two buttons.
        CGFloat tvH = frame.size.height - 52 - 44;
        _tv = [[UITextView alloc] initWithFrame:CGRectMake(10, 52, frame.size.width - 20, tvH)];
        _tv.editable = NO;
        _tv.scrollEnabled = YES;
        _tv.backgroundColor = [UIColor clearColor];
        _tv.font = [UIFont monospacedSystemFontOfSize:9.5 weight:UIFontWeightRegular];
        _tv.textColor = [UIColor colorWithRed:0.55 green:0.95 blue:0.6 alpha:1];
        [self addSubview:_tv];

        CGFloat btnY = frame.size.height - 38;
        CGFloat btnH = 28;
        CGFloat gap = 8;
        CGFloat btnW = (frame.size.width - 20 - gap) / 2.0;

        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(10, btnY, btnW, btnH);
        copyBtn.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        copyBtn.layer.cornerRadius = 8;
        copyBtn.titleLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
        [copyBtn setTitle:@"COPY LOG" forState:UIControlStateNormal];
        [copyBtn setTitleColor:[UIColor colorWithRed:0.55 green:0.95 blue:0.6 alpha:1]
                      forState:UIControlStateNormal];
        [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:copyBtn];

        UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        hideBtn.frame = CGRectMake(10 + btnW + gap, btnY, btnW, btnH);
        hideBtn.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        hideBtn.layer.cornerRadius = 8;
        hideBtn.titleLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
        [hideBtn setTitle:@"ẨN" forState:UIControlStateNormal];
        [hideBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [hideBtn addTarget:self action:@selector(hideSelf) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:hideBtn];
    }
    return self;
}

- (void)copyLog {
    UIPasteboard.generalPasteboard.string = _text;
    // Tiny flash to confirm the copy landed.
    UIColor *orig = self.backgroundColor;
    self.backgroundColor = [UIColor colorWithRed:0.1 green:0.3 blue:0.1 alpha:1];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.backgroundColor = orig;
    });
}

- (void)hideSelf {
    [UIView animateWithDuration:0.25 animations:^{ self.alpha = 0; }
        completion:^(BOOL finished) { [self removeFromSuperview]; }];
}

- (void)appendLine:(NSString *)line {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_text appendFormat:@"%@\n", line];

        // Ring buffer. 60 Hz publish × 20 s is 1200 lines, and an unbounded
        // UITextView with 1200 lines lags the whole main thread. 300 is
        // enough for the last five seconds at every gate, which is what
        // matters for the diagnosis.
        static const NSUInteger kMaxLines = 300;
        NSUInteger lineCount = 0;
        for (NSUInteger i = 0; i < self->_text.length; i++) {
            if ([self->_text characterAtIndex:i] == '\n') lineCount++;
        }
        while (lineCount > kMaxLines) {
            NSRange r = [self->_text rangeOfString:@"\n"];
            if (r.location == NSNotFound) break;
            [self->_text deleteCharactersInRange:NSMakeRange(0, r.location + 1)];
            lineCount--;
        }

        self->_tv.text = self->_text;
        [self->_tv scrollRangeToVisible:NSMakeRange(self->_text.length, 0)];
    });
}

- (void)dismissAfter:(NSTimeInterval)delay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{ self.alpha = 0; }
            completion:^(BOOL finished) { [self removeFromSuperview]; }];
    });
}

@end


//
//  BootLogPopup.m — Fl0rk-style boot console popup
//  Dark card, green monospace text. Now with COPY LOG + ẨN buttons, and a
//  300-line ring buffer so a 20-second run doesn't blow up the UITextView.
//
#import "BootLogPopup.h"

@implementation BootLogPopup {
    UITextView *_tv;
    NSMutableString *_text;
}

+ (instancetype)shared {
    static BootLogPopup *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [BootLogPopup new]; });
    return s;
}

+ (void)show {
    BootLogPopup *p = [self shared];
    if (p.superview) return;

    UIWindow *window = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            window = scene.windows.firstObject;
            break;
        }
    }
    if (!window) window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;

    CGFloat w = 340, h = 480;
    p.frame = CGRectMake((window.bounds.size.width - w) / 2,
                         (window.bounds.size.height - h) / 2, w, h);
    p.layer.cornerRadius = 14;
    p.layer.shadowOpacity = 0.5;
    p.layer.shadowRadius = 20;
    p.alpha = 0;
    [window addSubview:p];
    [UIView animateWithDuration:0.25 animations:^{ p.alpha = 1; }];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.02 green:0.03 blue:0.02 alpha:0.97];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, 200, 18)];
        title.text = @"@MINHDUC";
        title.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightBold];
        title.textColor = [UIColor whiteColor];
        [self addSubview:title];

        UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(14, 30, 270, 14)];
        sub.text = @"External for Free Fire — ESP diagnostic";
        sub.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
        sub.textColor = [UIColor colorWithWhite:0.6 alpha:1];
        [self addSubview:sub];

        _text = [NSMutableString new];

        // Reserve 40px at the bottom for the two buttons.
        CGFloat tvH = frame.size.height - 52 - 44;
        _tv = [[UITextView alloc] initWithFrame:CGRectMake(10, 52, frame.size.width - 20, tvH)];
        _tv.editable = NO;
        _tv.scrollEnabled = YES;
        _tv.backgroundColor = [UIColor clearColor];
        _tv.font = [UIFont monospacedSystemFontOfSize:9.5 weight:UIFontWeightRegular];
        _tv.textColor = [UIColor colorWithRed:0.55 green:0.95 blue:0.6 alpha:1];
        [self addSubview:_tv];

        CGFloat btnY = frame.size.height - 38;
        CGFloat btnH = 28;
        CGFloat gap = 8;
        CGFloat btnW = (frame.size.width - 20 - gap) / 2.0;

        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(10, btnY, btnW, btnH);
        copyBtn.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        copyBtn.layer.cornerRadius = 8;
        copyBtn.titleLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
        [copyBtn setTitle:@"COPY LOG" forState:UIControlStateNormal];
        [copyBtn setTitleColor:[UIColor colorWithRed:0.55 green:0.95 blue:0.6 alpha:1]
                      forState:UIControlStateNormal];
        [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:copyBtn];

        UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        hideBtn.frame = CGRectMake(10 + btnW + gap, btnY, btnW, btnH);
        hideBtn.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        hideBtn.layer.cornerRadius = 8;
        hideBtn.titleLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
        [hideBtn setTitle:@"ẨN" forState:UIControlStateNormal];
        [hideBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [hideBtn addTarget:self action:@selector(hideSelf) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:hideBtn];
    }
    return self;
}

- (void)copyLog {
    UIPasteboard.generalPasteboard.string = _text;
    // Tiny flash to confirm the copy landed.
    UIColor *orig = self.backgroundColor;
    self.backgroundColor = [UIColor colorWithRed:0.1 green:0.3 blue:0.1 alpha:1];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.backgroundColor = orig;
    });
}

- (void)hideSelf {
    [UIView animateWithDuration:0.25 animations:^{ self.alpha = 0; }
        completion:^(BOOL finished) { [self removeFromSuperview]; }];
}

- (void)appendLine:(NSString *)line {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_text appendFormat:@"%@\n", line];

        // Ring buffer. 60 Hz publish × 20 s is 1200 lines, and an unbounded
        // UITextView with 1200 lines lags the whole main thread. 300 is
        // enough for the last five seconds at every gate, which is what
        // matters for the diagnosis.
        static const NSUInteger kMaxLines = 300;
        NSUInteger lineCount = 0;
        for (NSUInteger i = 0; i < self->_text.length; i++) {
            if ([self->_text characterAtIndex:i] == '\n') lineCount++;
        }
        while (lineCount > kMaxLines) {
            NSRange r = [self->_text rangeOfString:@"\n"];
            if (r.location == NSNotFound) break;
            [self->_text deleteCharactersInRange:NSMakeRange(0, r.location + 1)];
            lineCount--;
        }

        self->_tv.text = self->_text;
        [self->_tv scrollRangeToVisible:NSMakeRange(self->_text.length, 0)];
    });
}

- (void)dismissAfter:(NSTimeInterval)delay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{ self.alpha = 0; }
            completion:^(BOOL finished) { [self removeFromSuperview]; }];
    });
}

@end
