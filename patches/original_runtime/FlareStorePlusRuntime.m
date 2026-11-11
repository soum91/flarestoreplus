// Optional UI extension for the user's supplied FlareStore binary.
// Does not hook installation, signing, certificates, or the update ledger.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface FSPOriginalLibraryStatus : NSObject
@property (nonatomic, strong) UILabel *badge;
@property (nonatomic, weak) UIWindow *badgeWindow;
@property (nonatomic, strong) NSDate *lastObservedRefresh;
@end

@implementation FSPOriginalLibraryStatus

+ (instancetype)shared {
    static FSPOriginalLibraryStatus *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [FSPOriginalLibraryStatus new]; });
    return shared;
}

- (UIWindow *)activeWindow {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return app.keyWindow;
}

- (BOOL)librarySelectedInController:(UIViewController *)controller {
    if (!controller) return NO;
    if ([controller isKindOfClass:UITabBarController.class]) {
        UITabBarController *tabs = (UITabBarController *)controller;
        NSString *name = tabs.selectedViewController.tabBarItem.title ?: tabs.selectedViewController.title;
        if ([name localizedCaseInsensitiveContainsString:@"Library"]) return YES;
        NSString *itemName = tabs.tabBar.selectedItem.title;
        if ([itemName localizedCaseInsensitiveContainsString:@"Library"]) return YES;
    }
    for (UIViewController *child in controller.childViewControllers) {
        if ([self librarySelectedInController:child]) return YES;
    }
    return NO;
}

- (BOOL)selectedLibraryTabInView:(UIView *)view depth:(NSUInteger)depth {
    if (!view || depth > 16) return NO;
    if ([view isKindOfClass:UITabBar.class]) {
        UITabBar *bar = (UITabBar *)view;
        if ([bar.selectedItem.title localizedCaseInsensitiveContainsString:@"Library"]) return YES;
    }
    for (UIView *child in view.subviews) {
        if ([self selectedLibraryTabInView:child depth:depth + 1]) return YES;
    }
    return NO;
}

- (NSDate *)validatedRefreshDate {
    // This is the original app's *actual background run*, never the time at
    // which we examined the UI or requested a run.
    id value = [NSUserDefaults.standardUserDefaults objectForKey:@"backgroundRefreshLastRun"];
    if ([value isKindOfClass:NSDate.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) {
        NSTimeInterval time = [value doubleValue];
        if (time > 978307200.0 && time < 4102444800.0) return [NSDate dateWithTimeIntervalSince1970:time];
        if (time > 0.0 && time < 3124137600.0) return [NSDate dateWithTimeIntervalSinceReferenceDate:time];
    }
    if ([value isKindOfClass:NSString.class]) {
        NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
        NSDate *parsed = [formatter dateFromString:value];
        if (parsed) return parsed;
        NSTimeInterval number = [value doubleValue];
        if (number > 978307200.0 && number < 4102444800.0) return [NSDate dateWithTimeIntervalSince1970:number];
    }
    return nil;
}

- (void)refreshBadge {
    NSAssert(NSThread.isMainThread, @"UI must update on the main thread");
    UIWindow *window = [self activeWindow];
    if (!window) return;
    BOOL visible = [self librarySelectedInController:window.rootViewController]
        || [self selectedLibraryTabInView:window depth:0];
    if (!visible) {
        self.badge.hidden = YES;
        return;
    }
    if (!self.badge || self.badgeWindow != window) {
        [self.badge removeFromSuperview];
        self.badge = [[UILabel alloc] initWithFrame:CGRectZero];
        self.badge.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
        self.badge.textColor = UIColor.secondaryLabelColor;
        self.badge.backgroundColor = UIColor.secondarySystemBackgroundColor;
        self.badge.textAlignment = NSTextAlignmentCenter;
        self.badge.layer.cornerRadius = 9;
        self.badge.layer.masksToBounds = YES;
        self.badge.adjustsFontSizeToFitWidth = YES;
        self.badge.minimumScaleFactor = 0.8;
        self.badge.accessibilityIdentifier = @"FlareStorePlus.Library.LastBackgroundRefresh";
        [window addSubview:self.badge];
        self.badgeWindow = window;
    }
    CGFloat top = window.safeAreaInsets.top;
    self.badge.frame = CGRectMake(MAX(8, window.bounds.size.width - 229), top + 44, 221, 25);
    NSDate *lastRun = [self validatedRefreshDate];
    if (lastRun) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateStyle = NSDateFormatterShortStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        self.badge.text = [NSString stringWithFormat:@"Background: %@", [formatter stringFromDate:lastRun]];
        self.badge.accessibilityLabel = [NSString stringWithFormat:@"Last background refresh %@", [formatter stringFromDate:lastRun]];
    } else {
        self.badge.text = @"Background: Not run yet";
        self.badge.accessibilityLabel = @"No completed background refresh recorded";
    }
    [window bringSubviewToFront:self.badge];
    self.badge.hidden = NO;
}

- (void)start {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self start]; });
        return;
    }
    [self refreshBadge];
    [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(refreshBadge) userInfo:nil repeats:YES];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                    object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *note) {
        [[FSPOriginalLibraryStatus shared] refreshBadge];
    }];
}

@end

__attribute__((constructor)) static void FSPStartLibraryStatus(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[FSPOriginalLibraryStatus shared] start]; });
}
