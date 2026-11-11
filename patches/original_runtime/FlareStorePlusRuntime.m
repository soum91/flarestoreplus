// Original FlareStorePlus b63: search-anchored Repositories and Library refresh status.
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

- (NSString *)visiblePageTitle:(UIView *)view window:(UIWindow *)window depth:(NSInteger)depth {
    if (!view || depth > 35 || view.hidden || view.alpha < 0.05) return nil;
    NSString *value = [view isKindOfClass:UILabel.class] ? ((UILabel *)view).text : nil;
    if (!value.length && view.isAccessibilityElement) value = view.accessibilityLabel;
    NSString *trimmed = [value stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *tab = nil;
    if ([trimmed isEqualToString:@"Repositories"]) tab = @"Repos";
    else if ([trimmed isEqualToString:@"Library"]) tab = @"Library";
    if (tab) {
        CGRect r = [view convertRect:view.bounds toView:window];
        CGFloat top = window.safeAreaInsets.top;
        if (r.size.width > 80 && r.size.height >= 22 &&
            r.origin.y > top + 15 && r.origin.y < top + 175) return tab;
    }
    for (UIView *v in view.subviews) {
        NSString *t = [self visiblePageTitle:v window:window depth:depth+1];
        if (t) return t;
    }
    return nil;
}
- (BOOL)isSearchAnchor:(UIView *)view {
    if ([view isKindOfClass:UISearchBar.class]) return YES;
    if ([view isKindOfClass:UITextField.class]) {
        UITextField *field = (UITextField *)view;
        NSString *value = field.placeholder ?: field.accessibilityLabel ?: @"";
        return [value localizedCaseInsensitiveContainsString:@"Search"];
    }
    // SwiftUI can expose the native search field only as an accessibility element.
    if (!view.isAccessibilityElement) return NO;
    NSString *label = view.accessibilityLabel ?: @"";
    NSString *klass = NSStringFromClass(view.class);
    return ([label localizedCaseInsensitiveContainsString:@"Search Library"] ||
            [label localizedCaseInsensitiveContainsString:@"Search Repositories"] ||
            ([klass localizedCaseInsensitiveContainsString:@"SearchField"] &&
             [label localizedCaseInsensitiveContainsString:@"Search"]));
}
- (void)findSearch:(UIView *)view window:(UIWindow *)window depth:(NSInteger)depth
             best:(UIView * __strong *)best score:(CGFloat *)bestScore {
    if (!view || depth > 35 || view.hidden || view.alpha < 0.05) return;
    if ([self isSearchAnchor:view]) {
        CGRect r = [view convertRect:view.bounds toView:window];
        CGFloat top = window.safeAreaInsets.top;
        if (r.size.width >= window.bounds.size.width * 0.58 &&
            r.size.height >= 24 && r.size.height <= 86 &&
            CGRectGetMinY(r) > top + 55 && CGRectGetMinY(r) < top + 265 &&
            CGRectGetMaxY(r) < window.bounds.size.height * 0.56) {
            // Prefer the precise text-field rectangle over its enclosing search bar.
            CGFloat score = ([view isKindOfClass:UITextField.class] ? 1000 : 0)
                - fabs(r.size.height - 42) - fabs(CGRectGetMidX(r) - CGRectGetMidX(window.bounds));
            if (score > *bestScore) { *best = view; *bestScore = score; }
        }
    }
    for (UIView *sub in view.subviews)
        [self findSearch:sub window:window depth:depth+1 best:best score:bestScore];
}
- (UIView *)inlineHostForSearch:(UIView *)search labelRect:(CGRect)rect window:(UIWindow *)window {
    // Choose the closest ancestor whose visible coordinate space contains the
    // gap below the search control. Unlike a fixed HUD, this follows scrolling.
    for (UIView *v = search.superview; v && v != window; v = v.superview) {
        CGRect candidate = [v convertRect:rect fromView:window];
        if (CGRectContainsRect(CGRectInset(v.bounds, -1, -1), candidate))
            return v;
    }
    return window;
}
- (void)update {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self update]; });
        return;
    }
    UIWindow *window = [self keyWindow];
    if (!window || [self hasDetailScreen:window.rootViewController depth:0]) {
        [self clear]; return;
    }
    // The previous Library-only build looked for a SwiftUI "SIGNED APPS" UILabel.
    // SwiftUI did not expose a stable UIKit view, so the label disappeared.
    // Anchor both pages to their actual visible native search control instead.
    NSString *tab = [self selectedTab:window depth:0];
    NSString *heading = [self visiblePageTitle:window window:window depth:0];
    if (heading) tab = heading;
    if (![tab isEqualToString:@"Repos"] && ![tab isEqualToString:@"Library"]) {
        [self clear]; return;
    }
    UIView *search = nil;
    CGFloat score = -CGFLOAT_MAX;
    [self findSearch:window window:window depth:0 best:&search score:&score];
    if (!search) { [self clear]; return; }

    CGRect field = [search convertRect:search.bounds toView:window];
    CGFloat width = MIN(field.size.width - 14, window.bounds.size.width - 50);
    // Screenshot-verified native gap: search bottom -> first list card ~26pt.
    // This 12pt readout starts 4pt below search and ends well before cards.
    CGRect rect = CGRectMake(MAX(20, CGRectGetMinX(field) + 6),
                             CGRectGetMaxY(field) + 4, width, 12);
    if (width < 200 || CGRectGetMaxY(rect) > window.bounds.size.height * 0.65 ||
        CGRectGetMinY(field) < window.safeAreaInsets.top + 55 ||
        CGRectGetMaxY(field) > window.bounds.size.height * 0.56) {
        [self clear]; return;
    }
    UIView *host = [self inlineHostForSearch:search labelRect:rect window:window];
    if (self.label.superview != host || self.anchor != search ||
        ![self.tab isEqualToString:tab]) {
        [self clear];
        self.label = [UILabel new];
        self.label.backgroundColor = UIColor.clearColor;
        self.label.textColor = UIColor.secondaryLabelColor;
        self.label.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
        self.label.numberOfLines = 1;
        self.label.adjustsFontSizeToFitWidth = YES;
        self.label.minimumScaleFactor = 0.8;
        self.label.textAlignment = NSTextAlignmentLeft;
        self.label.userInteractionEnabled = NO;
        self.label.accessibilityIdentifier = [NSString stringWithFormat:
            @"FlareStorePlus.%@.RefreshReadout",tab];
        self.anchor = search;
        self.tab = tab;
        [host addSubview:self.label];
    }
    self.label.frame = [host convertRect:rect fromView:window];
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    NSDate *cache = [self dateFor:[prefs objectForKey:@"repositoryCacheDate"]];
    NSDate *bg = [self dateFor:[prefs objectForKey:@"backgroundRefreshLastRun"]];
    // Never fabricate a successful network-refresh timestamp.
    self.label.text = [NSString stringWithFormat:@"Cache saved: %@  |  BG ran: %@",
        [self shortDate:cache], [self shortDate:bg]];
    self.label.accessibilityLabel = [NSString stringWithFormat:
        @"Repository cache saved %@. Background task last ran %@. These do not prove all sources refreshed.",
        [self shortDate:cache], [self shortDate:bg]];
}
- (void)start {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self start]; });
        return;
    }
    [self update];
    [NSTimer scheduledTimerWithTimeInterval:0.75 target:self
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
