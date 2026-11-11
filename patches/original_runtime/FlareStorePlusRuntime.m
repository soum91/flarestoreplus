// Original FlareStorePlus, read-only inline repository refresh status.
// Does not intercept signing, installation, repositories, or auto-update storage.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface FSPOriginalRefreshStatus : NSObject
@property (nonatomic,strong) UILabel *status;
@property (nonatomic,weak) UIScrollView *host;
@property (nonatomic,weak) UIWindow *window;
@property (nonatomic,copy) NSString *tab;
@end

@implementation FSPOriginalRefreshStatus
+ (instancetype)shared {
    static FSPOriginalRefreshStatus *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [FSPOriginalRefreshStatus new]; });
    return instance;
}

- (UIWindow *)activeWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return nil;
}

- (NSString *)selectedTab:(UIView *)view depth:(NSUInteger)depth {
    if (!view || depth > 22) return nil;
    if ([view isKindOfClass:UITabBar.class]) {
        NSString *name = ((UITabBar *)view).selectedItem.title;
        if ([name localizedCaseInsensitiveContainsString:@"Library"]) return @"Library";
        if ([name localizedCaseInsensitiveContainsString:@"Repo"]) return @"Repos";
    }
    for (UIView *subview in view.subviews) {
        NSString *found = [self selectedTab:subview depth:depth+1];
        if (found) return found;
    }
    return nil;
}

- (BOOL)hasPushedNavigation:(UIViewController *)root depth:(NSUInteger)depth {
    if (!root || depth > 15) return NO;
    if ([root isKindOfClass:UINavigationController.class] &&
        ((UINavigationController *)root).viewControllers.count > 1) return YES;
    if (root.presentedViewController) return YES;
    for (UIViewController *child in root.childViewControllers) {
        if ([self hasPushedNavigation:child depth:depth+1]) return YES;
    }
    return NO;
}

- (void)findScroll:(UIView *)view depth:(NSUInteger)depth best:(UIScrollView * __strong *)best score:(CGFloat *)score {
    if (!view || depth > 22 || view.hidden || view.alpha < 0.05) return;
    if ([view isKindOfClass:UIScrollView.class] && ![view isKindOfClass:UITextView.class]) {
        UIScrollView *scroll = (UIScrollView *)view;
        CGFloat area = view.bounds.size.width * view.bounds.size.height;
        if (scroll.scrollEnabled && view.bounds.size.width > 260 && view.bounds.size.height > 280 && area > *score) {
            *best = scroll; *score = area;
        }
    }
    for (UIView *subview in view.subviews) {
        [self findScroll:subview depth:depth+1 best:best score:score];
    }
}

- (NSDate *)decodeDate:(id)value {
    if ([value isKindOfClass:NSDate.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) {
        double raw = [value doubleValue];
        if (!isfinite(raw)) return nil;
        NSDate *date;
        if (raw > 978307200.0 && raw < 4102444800.0) date = [NSDate dateWithTimeIntervalSince1970:raw];
        else if (raw > 0 && raw < 3124137600.0) date = [NSDate dateWithTimeIntervalSinceReferenceDate:raw];
        if (date && [date timeIntervalSinceNow] <= 300) return date;
    }
    if ([value isKindOfClass:NSString.class]) {
        NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
        NSDate *date = [iso dateFromString:(NSString *)value];
        if (date && [date timeIntervalSinceNow] <= 300) return date;
        NSNumberFormatter *number = [NSNumberFormatter new];
        number.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        NSNumber *seconds = [number numberFromString:(NSString *)value];
        if (seconds) return [self decodeDate:seconds];
    }
    return nil;
}

- (NSString *)brief:(NSDate *)date {
    if (!date) return @"not recorded";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = NSLocale.currentLocale;
    formatter.dateStyle = [NSCalendar.currentCalendar isDateInToday:date]
        ? NSDateFormatterNoStyle : NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

- (void)removeStatus {
    [self.status removeFromSuperview];
    self.status = nil;
    self.host = nil;
    self.window = nil;
    self.tab = nil;
}

- (void)tick {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self tick]; });
        return;
    }
    UIWindow *window = [self activeWindow];
    NSString *tab = window ? [self selectedTab:window depth:0] : nil;
    // A label must belong to the native Repos/Library scroll content, not
    // the UIWindow. It scrolls out with its page and cannot float over alerts.
    if (!tab || [self hasPushedNavigation:window.rootViewController depth:0]) {
        [self removeStatus];
        return;
    }
    UIScrollView *candidate = nil;
    CGFloat score = 0;
    [self findScroll:window depth:0 best:&candidate score:&score];
    if (!candidate) {
        [self removeStatus]; // Never fall back to the obstructive b59 window overlay.
        return;
    }
    BOOL moved = self.host != candidate || self.window != window || ![tab isEqualToString:self.tab];
    if (moved) {
        [self removeStatus];
        self.status = [UILabel new];
        self.status.backgroundColor = UIColor.clearColor;
        self.status.textColor = UIColor.secondaryLabelColor;
        self.status.textAlignment = NSTextAlignmentLeft;
        self.status.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
        self.status.numberOfLines = 1;
        self.status.minimumScaleFactor = 0.68;
        self.status.adjustsFontSizeToFitWidth = YES;
        self.status.userInteractionEnabled = NO;
        self.status.isAccessibilityElement = YES;
        self.status.accessibilityIdentifier = [NSString stringWithFormat:@"FlareStorePlus.%@.LastRepoRefresh",tab];
        self.host = candidate; self.window = window; self.tab = tab;
        // Match the existing transparent content style beneath the large title.
        // Anchoring to the scroll content, rather than screen coordinates, ensures
        // that this readout scrolls offscreen naturally.
        CGPoint place = [candidate convertPoint:CGPointMake(26, window.safeAreaInsets.top + 83) fromView:window];
        place.y -= candidate.contentOffset.y;
        self.status.frame = CGRectMake(MAX(8, place.x), place.y,
            MAX(170, MIN(window.bounds.size.width - 52, candidate.bounds.size.width - 40)), 17);
        [candidate addSubview:self.status];
    }
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    // repositoryCacheDate is updated when FlareStore saves its repository cache.
    // It is NOT the background-only timestamp which b59 mistakenly showed.
    NSDate *repoDate = [self decodeDate:[prefs objectForKey:@"repositoryCacheDate"]];
    NSDate *backgroundDate = [self decodeDate:[prefs objectForKey:@"backgroundRefreshLastRun"]];
    BOOL automaticEnabled = [prefs objectForKey:@"backgroundRefreshEnabled"]
        ? [prefs boolForKey:@"backgroundRefreshEnabled"] : YES;
    NSString *line = [NSString stringWithFormat:@"Repos: %@  |  Background: %@%@",
        [self brief:repoDate], automaticEnabled ? [self brief:backgroundDate] : @"off",
        automaticEnabled ? @"" : @""];
    self.status.text = line;
    self.status.accessibilityLabel = [NSString stringWithFormat:
        @"Repository cache last saved: %@. Background refresh: %@. Background last run: %@. The original app also checks repositories when opened if they are older than the configured interval.",
        [self brief:repoDate], automaticEnabled ? @"enabled" : @"disabled", [self brief:backgroundDate]];
}

- (void)start {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self start]; });
        return;
    }
    [self tick];
    [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(tick)
                                    userInfo:nil repeats:YES];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                    object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *note) {
        [[FSPOriginalRefreshStatus shared] tick];
    }];
}
@end

__attribute__((constructor)) static void FSPStartOriginalRefreshStatus(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[FSPOriginalRefreshStatus shared] start]; });
}
