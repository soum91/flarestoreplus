// Original FlareStorePlus b62: Library-only read-only refresh status.
// No fabricated last-success time. No window-floating badge, coordinate guesses,
// mutation of the native update ledger, certs, or auto-update selections.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <math.h>

@interface FSPRefreshReadout : NSObject
@property (nonatomic,strong) UILabel *label;
@property (nonatomic,weak) UIScrollView *host;
@property (nonatomic,weak) UIView *anchor;
@property (nonatomic,copy) NSString *tab;
@end

@implementation FSPRefreshReadout
+ (instancetype)shared {
    static FSPRefreshReadout *obj;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ obj = [FSPRefreshReadout new]; });
    return obj;
}
- (UIWindow *)keyWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (window.isKeyWindow) return window;
    }
    return nil;
}
- (NSString *)selectedTab:(UIView *)view depth:(NSInteger)depth {
    if (!view || depth > 24) return nil;
    if ([view isKindOfClass:UITabBar.class]) {
        NSString *name = ((UITabBar *)view).selectedItem.title ?: @"";
        if ([name localizedCaseInsensitiveContainsString:@"Repos"]) return @"Repos";
        if ([name localizedCaseInsensitiveContainsString:@"Library"]) return @"Library";
    }
    for (UIView *sub in view.subviews) {
        NSString *name = [self selectedTab:sub depth:depth+1];
        if (name) return name;
    }
    return nil;
}
- (BOOL)hasDetailScreen:(UIViewController *)controller depth:(NSInteger)depth {
    if (!controller || depth > 14) return NO;
    if (controller.presentedViewController) return YES;
    if ([controller isKindOfClass:UINavigationController.class] &&
        ((UINavigationController *)controller).viewControllers.count > 1) return YES;
    for (UIViewController *child in controller.childViewControllers)
        if ([self hasDetailScreen:child depth:depth+1]) return YES;
    return NO;
}
- (BOOL)isSearch:(UIView *)view {
    if ([view isKindOfClass:UISearchBar.class]) return YES;
    if (![view isKindOfClass:UITextField.class]) return NO;
    UITextField *field = (UITextField *)view;
    NSString *value = field.placeholder ?: field.accessibilityLabel ?: @"";
    return [value localizedCaseInsensitiveContainsString:@"Search"];
}
- (BOOL)isLibraryHeader:(UIView *)view {
    NSString *value = [view isKindOfClass:UILabel.class] ? ((UILabel *)view).text : nil;
    if (!value.length) value = view.accessibilityLabel;
    if (!value.length || !([view isKindOfClass:UILabel.class] || view.isAccessibilityElement))
        return NO;
    return [value localizedCaseInsensitiveContainsString:@"UPDATES AVAILABLE"] ||
        [value localizedCaseInsensitiveContainsString:@"SIGNED APPS"];
}
- (void)findAnchor:(UIView *)view tab:(NSString *)tab window:(UIWindow *)window
           depth:(NSInteger)depth best:(UIView * __strong *)best y:(CGFloat *)bestY {
    if (!view || depth > 28 || view.hidden || view.alpha < 0.05) return;
    BOOL isTarget = [self isLibraryHeader:view];
    if (isTarget && view.bounds.size.width >= 20 && view.bounds.size.height > 3) {
        CGRect position = [view convertRect:view.bounds toView:window];
        CGFloat minY = window.safeAreaInsets.top + 110;
        CGFloat maxY = window.bounds.size.height - window.safeAreaInsets.bottom - 130;
        if (CGRectGetMaxY(position) > minY && CGRectGetMaxY(position) < maxY &&
            position.size.width >= 20 && CGRectGetMaxY(position) < *bestY) {
            *best = view;
            *bestY = CGRectGetMaxY(position);
        }
    }
    for (UIView *sub in view.subviews)
        [self findAnchor:sub tab:tab window:window depth:depth+1 best:best y:bestY];
}
- (UIScrollView *)scrollHostFor:(UIView *)view window:(UIWindow *)window {
    for (UIView *v = view; v && v != window; v = v.superview) {
        if ([v isKindOfClass:UIScrollView.class] &&
            v.bounds.size.height >= 260 && v.bounds.size.width >= 270)
            return (UIScrollView *)v;
    }
    return nil;
}
- (NSDate *)dateFor:(id)value {
    NSDate *date = nil;
    if ([value isKindOfClass:NSDate.class]) date = value;
    else if ([value isKindOfClass:NSNumber.class]) {
        double raw = [value doubleValue];
        if (!isfinite(raw)) return nil;
        if (raw >= 978307200.0 && raw <= 4102444800.0)
            date = [NSDate dateWithTimeIntervalSince1970:raw];
        else if (raw >= 450000000 && raw < 978307200)
            date = [NSDate dateWithTimeIntervalSinceReferenceDate:raw];
    } else if ([value isKindOfClass:NSString.class]) {
        NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
        date = [iso dateFromString:value];
        if (!date) {
            NSString *s = (NSString *)value;
            NSScanner *scanner = [NSScanner scannerWithString:s];
            double n = 0;
            if ([scanner scanDouble:&n] && scanner.isAtEnd)
                date = [self dateFor:@(n)];
        }
    }
    if (!date || [date timeIntervalSinceNow] > 300 ||
        [date timeIntervalSince1970] < 1609459200) return nil;
    return date;
}
- (NSString *)shortDate:(NSDate *)date {
    if (!date) return @"unknown";
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = NSLocale.currentLocale;
    f.dateStyle = [NSCalendar.currentCalendar isDateInToday:date] ?
        NSDateFormatterNoStyle : NSDateFormatterShortStyle;
    f.timeStyle = NSDateFormatterShortStyle;
    return [f stringFromDate:date];
}
- (void)clear {
    [self.label removeFromSuperview];
    self.label = nil;
    self.anchor = nil;
    self.host = nil;
    self.tab = nil;
}
- (void)update {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self update]; });
        return;
    }
    UIWindow *window = [self keyWindow];
    NSString *tab = window ? [self selectedTab:window depth:0] : nil;
    // Repositories has no guaranteed safe layout slot. Do not inject any label there.
    if (![tab isEqualToString:@"Library"] ||
        [self hasDetailScreen:window.rootViewController depth:0]) {
        [self clear];
        return;
    }
    UIView *anchor = nil;
    CGFloat y = CGFLOAT_MAX;
    [self findAnchor:window tab:tab window:window depth:0 best:&anchor y:&y];
    UIScrollView *scroll = anchor ? [self scrollHostFor:anchor window:window] : nil;
    if (!scroll || !anchor) {
        [self clear]; // Never invent a screen coordinate and cover app content.
        return;
    }
    // Convert anchor bounds directly into its scroll-content coordinate system.
    // Critically: do not subtract contentOffset. UIView conversion already handles it.
    CGRect anchorBox = [scroll convertRect:anchor.bounds fromView:anchor];
    CGFloat width = MIN(scroll.bounds.size.width - 40, window.bounds.size.width - 56);
    if (width < 170) { [self clear]; return; }
    CGFloat top = CGRectGetMaxY(anchorBox) + 7;
    CGRect labelFrame = CGRectMake(MAX(16, CGRectGetMinX(anchorBox) + 5),
                                  top, width, 15);
    // Verify an actual 29-point blank region after the search/header.
    // If the next independently accessible content starts too close, hide.
    CGFloat bottomScreen = CGRectGetMaxY([scroll convertRect:labelFrame toView:window]);
    if (bottomScreen > window.bounds.size.height - 110 || bottomScreen < window.safeAreaInsets.top + 60) {
        [self clear]; return;
    }
    if (self.host != scroll || self.anchor != anchor || ![tab isEqualToString:self.tab]) {
        [self clear];
        self.label = [UILabel new];
        self.label.backgroundColor = UIColor.clearColor;
        self.label.textColor = UIColor.secondaryLabelColor;
        self.label.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
        self.label.numberOfLines = 1;
        self.label.adjustsFontSizeToFitWidth = YES;
        self.label.minimumScaleFactor = 0.78;
        self.label.textAlignment = NSTextAlignmentLeft;
        self.label.userInteractionEnabled = NO;
        self.label.accessibilityIdentifier = [NSString stringWithFormat:
            @"FlareStorePlus.%@.RefreshReadout", tab];
        self.host = scroll;
        self.anchor = anchor;
        self.tab = tab;
        [scroll addSubview:self.label];
    }
    self.label.frame = labelFrame;
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    NSDate *cache = [self dateFor:[prefs objectForKey:@"repositoryCacheDate"]];
    NSDate *bg = [self dateFor:[prefs objectForKey:@"backgroundRefreshLastRun"]];
    // Neither key means that every remote source was successfully downloaded.
    self.label.text = [NSString stringWithFormat:@"Cache saved: %@  |  BG ran: %@",
        [self shortDate:cache], [self shortDate:bg]];
    self.label.accessibilityLabel = [NSString stringWithFormat:
        @"Repository cache timestamp %@. Last recorded iOS background task %@. Neither proves a successful network refresh for every repository.",
        [self shortDate:cache], [self shortDate:bg]];
}
- (void)start {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self start]; });
        return;
    }
    [self update];
    [NSTimer scheduledTimerWithTimeInterval:2.0 target:self
        selector:@selector(update) userInfo:nil repeats:YES];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
            [[FSPRefreshReadout shared] update];
        }];
}
@end

__attribute__((constructor)) static void FSPStartReadout(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[FSPRefreshReadout shared] start]; });
}
