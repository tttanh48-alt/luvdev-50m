//
//  BootLogPopup.h — Fl0rk-style boot console popup
//
#import <UIKit/UIKit.h>

@interface BootLogPopup : UIView
+ (instancetype)shared;
+ (void)show;
- (void)appendLine:(NSString *)line;
- (void)dismissAfter:(NSTimeInterval)delay;
@end
