#import "Overlay.h"

// ---------- draw config ----------
#define BOX_COLOR   [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:0.9]
#define TEXT_COLOR  [UIColor whiteColor]
#define LINE_W      1.5f

// ---------- PassthroughWindow ----------
@interface PassthroughWindow : UIWindow @end
@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
@end

// ---------- ESPOverlayView ----------
@implementation ESPOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx || !self.entities.count) return;

    NSDictionary *attrs = @{
        NSFontAttributeName            : [UIFont boldSystemFontOfSize:11],
        NSForegroundColorAttributeName : TEXT_COLOR
    };

    for (NSDictionary *e in self.entities) {
        int team = [e[@"team"] intValue];
        UIColor *col = (team == 0) ? BOX_COLOR
                                   : [UIColor colorWithRed:0.2 green:0.8 blue:1 alpha:0.9];

        CGRect box = [e[@"box"] CGRectValue];

        // bounding box
        CGContextSetStrokeColorWithColor(ctx, col.CGColor);
        CGContextSetLineWidth(ctx, LINE_W);
        CGContextStrokeRect(ctx, box);

        // corner ticks
        float cw = box.size.width  * 0.2f;
        float ch = box.size.height * 0.2f;
        CGContextSetLineWidth(ctx, LINE_W * 2);

        // top-left
        CGContextMoveToPoint(ctx, box.origin.x, box.origin.y + ch);
        CGContextAddLineToPoint(ctx, box.origin.x, box.origin.y);
        CGContextAddLineToPoint(ctx, box.origin.x + cw, box.origin.y);
        // top-right
        CGContextMoveToPoint(ctx, CGRectGetMaxX(box) - cw, box.origin.y);
        CGContextAddLineToPoint(ctx, CGRectGetMaxX(box), box.origin.y);
        CGContextAddLineToPoint(ctx, CGRectGetMaxX(box), box.origin.y + ch);
        // bottom-left
        CGContextMoveToPoint(ctx, box.origin.x, CGRectGetMaxY(box) - ch);
        CGContextAddLineToPoint(ctx, box.origin.x, CGRectGetMaxY(box));
        CGContextAddLineToPoint(ctx, box.origin.x + cw, CGRectGetMaxY(box));
        // bottom-right
        CGContextMoveToPoint(ctx, CGRectGetMaxX(box) - cw, CGRectGetMaxY(box));
        CGContextAddLineToPoint(ctx, CGRectGetMaxX(box), CGRectGetMaxY(box));
        CGContextAddLineToPoint(ctx, CGRectGetMaxX(box), CGRectGetMaxY(box) - ch);
        CGContextStrokePath(ctx);

        // health bar
        float hp = [e[@"hp"] floatValue];
        if (hp > 0) {
            float barW = 3;
            float barH = box.size.height * hp;
            CGRect barBg = CGRectMake(box.origin.x - 5, box.origin.y,
                                      barW, box.size.height);
            CGRect barFg = CGRectMake(box.origin.x - 5,
                                      CGRectGetMaxY(box) - barH,
                                      barW, barH);
            CGContextSetFillColorWithColor(ctx,
                [UIColor colorWithWhite:0 alpha:0.5].CGColor);
            CGContextFillRect(ctx, barBg);

            UIColor *hpCol = [UIColor colorWithRed:(1.0f - hp)
                                             green:hp
                                              blue:0
                                             alpha:1];
            CGContextSetFillColorWithColor(ctx, hpCol.CGColor);
            CGContextFillRect(ctx, barFg);
        }

        // label
        NSString *label = [NSString stringWithFormat:@"%@  %.0fm",
                           e[@"name"] ?: @"?",
                           [e[@"dist"] floatValue]];
        CGSize sz = [label sizeWithAttributes:attrs];
        CGPoint pt = CGPointMake(box.origin.x + (box.size.width - sz.width) * 0.5f,
                                 box.origin.y - sz.height - 2);
        [label drawAtPoint:pt withAttributes:attrs];
    }
}

@end

// ---------- ESPOverlay ----------
@implementation ESPOverlay {
    PassthroughWindow *_window;
    ESPOverlayView    *_view;
    CADisplayLink     *_link;
    NSArray           *_entities;
    dispatch_queue_t   _lock;
}

+ (instancetype)shared {
    static ESPOverlay *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [ESPOverlay new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    _lock = dispatch_queue_create("esp.lock", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect screen = [UIScreen mainScreen].bounds;

        self->_window = [[PassthroughWindow alloc] initWithFrame:screen];
        self->_window.windowLevel        = UIWindowLevelAlert + 100;
        self->_window.backgroundColor    = [UIColor clearColor];
        self->_window.userInteractionEnabled = NO;
        self->_window.hidden             = NO;

        UIViewController *vc = [UIViewController new];
        vc.view.backgroundColor = [UIColor clearColor];
        self->_window.rootViewController = vc;

        self->_view = [[ESPOverlayView alloc] initWithFrame:screen];
        [self->_window addSubview:self->_view];

        self->_link = [CADisplayLink displayLinkWithTarget:self
                                                  selector:@selector(_tick:)];
        self->_link.preferredFramesPerSecond = 60;
        [self->_link addToRunLoop:[NSRunLoop mainRunLoop]
                          forMode:NSRunLoopCommonModes];

        NSLog(@"[ESP] overlay started");
    });
}

- (void)stop {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_link invalidate];
        self->_link = nil;
        self->_window.hidden = YES;
        self->_window = nil;
    });
}

- (void)updateEntities:(NSArray *)entities {
    dispatch_async(_lock, ^{
        self->_entities = [entities copy];
    });
}

- (void)_tick:(CADisplayLink *)link {
    __block NSArray *snap;
    dispatch_sync(_lock, ^{ snap = self->_entities; });
    self->_view.entities = snap;
    [self->_view setNeedsDisplay];
}

@end
