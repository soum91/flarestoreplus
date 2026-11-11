// Optional UI extension for the user's supplied FlareStore binary.
// Does not hook installation, signing, certificates, or the update ledger.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface FSPOriginalLibraryStatus : NSObject
@property (nonatomic, strong) UIButton *badge;
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
    for (UIWindow *window in app.windows) {
        if (window.isKeyWindow) return window;
    }
    return nil;
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


- (UITabBarController *)settingsTabsIn:(UIViewController *)controller {
    if (!controller) return nil;
    if ([controller isKindOfClass:UITabBarController.class]) {
        UITabBarController *tabs = (UITabBarController *)controller;
        for (UIViewController *child in tabs.viewControllers) {
            NSString *title = child.tabBarItem.title ?: child.title;
            if ([title localizedCaseInsensitiveContainsString:@"Settings"]) return tabs;
        }
    }
    for (UIViewController *child in controller.childViewControllers) {
        UITabBarController *tabs = [self settingsTabsIn:child];
        if (tabs) return tabs;
    }
    return [self settingsTabsIn:controller.presentedViewController];
}

- (void)openNativeSettings {
    UIWindow *window = [self activeWindow];
    UITabBarController *tabs = [self settingsTabsIn:window.rootViewController];
    if (tabs) {
        for (NSUInteger index = 0; index < tabs.viewControllers.count; index++) {
            UIViewController *child = tabs.viewControllers[index];
            NSString *title = child.tabBarItem.title ?: child.title;
            if ([title localizedCaseInsensitiveContainsString:@"Settings"]) {
                tabs.selectedIndex = index;
                return;
            }
        }
    }
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"FlareStore Settings"
        message:@"Use the Settings tab: background refresh is under Refresh & Downloads, while individual app selection and certificates are under Favorites & Auto-Updates."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [root presentViewController:alert animated:YES completion:nil];
}

- (NSString *)backgroundEnabledLabel {
    id setting = [NSUserDefaults.standardUserDefaults objectForKey:@"backgroundRefreshEnabled"];
    return setting == nil ? @"App default" : ([setting boolValue] ? @"Enabled" : @"Disabled");
}

- (NSString *)autoUpdateSelectionLabel {
    // Do not modify the original app's certificate or per-app selection data.
    id value = [NSUserDefaults.standardUserDefaults objectForKey:@"autoUpdate.keys.v1"];
    if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSSet.class]
        || [value isKindOfClass:NSDictionary.class]) {
        return [NSString stringWithFormat:@"%lu selected", (unsigned long)[value count]];
    }
    return @"Manage in Settings";
}

- (void)openRefreshMenu {
    UIWindow *window = [self activeWindow];
    if (!window) return;
    NSDate *date = [self validatedRefreshDate];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    NSString *timestamp = date ? [formatter stringFromDate:date] : @"Not run yet";
    NSString *summary = [NSUserDefaults.standardUserDefaults stringForKey:@"backgroundRefreshLastSummary"];
    if (summary.length > 180) summary = [[summary substringToIndex:180] stringByAppendingString:@"…"];
    NSString *details = [NSString stringWithFormat:
        @"Last background refresh: %@\nBackground checks: %@\nAuto-updates: %@%@\n\nRun times are chosen by iOS. App signing and installation may need a working pairing connection or confirmation.",
        timestamp, [self backgroundEnabledLabel], [self autoUpdateSelectionLabel],
        summary.length ? [NSString stringWithFormat:@"\nLast run: %@", summary] : @""];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Refresh & Auto-Updates"
        message:details preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [menu addAction:[UIAlertAction actionWithTitle:@"Background Refresh Settings" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) { [weakSelf openNativeSettings]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Manage Auto-Update Apps" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) { [weakSelf openNativeSettings]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = menu.popoverPresentationController;
    if (popover) { popover.sourceView = self.badge; popover.sourceRect = self.badge.bounds; }
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    [root presentViewController:menu animated:YES completion:nil];
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
        self.badge = [UIButton buttonWithType:UIButtonTypeSystem];
        self.badge.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
        self.badge.titleLabel.numberOfLines = 2;
        self.badge.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.badge.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.badge.titleLabel.minimumScaleFactor = 0.75;
        [self.badge setTitleColor:UIColor.secondaryLabelColor forState:UIControlStateNormal];
        self.badge.backgroundColor = UIColor.secondarySystemBackgroundColor;
        self.badge.layer.cornerRadius = 10;
        self.badge.layer.masksToBounds = YES;
        self.badge.accessibilityIdentifier = @"FlareStorePlus.Library.RefreshControls";
        [self.badge addTarget:self action:@selector(openRefreshMenu) forControlEvents:UIControlEventTouchUpInside];
        [window addSubview:self.badge];
        self.badgeWindow = window;
    }
    CGFloat top = window.safeAreaInsets.top;
    CGFloat width = MIN(310, window.bounds.size.width - 120);
    self.badge.frame = CGRectMake((window.bounds.size.width - width) / 2, top + 38, width, 42);
    NSDate *lastRun = [self validatedRefreshDate];
    if (lastRun) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateStyle = NSDateFormatterShortStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        [self.badge setTitle:[NSString stringWithFormat:@"Last BG refresh: %@\nAuto-updates: Manage apps", [formatter stringFromDate:lastRun]] forState:UIControlStateNormal];
        self.badge.accessibilityLabel = [NSString stringWithFormat:@"Last background refresh %@. Tap for background and auto-update settings.", [formatter stringFromDate:lastRun]];
    } else {
        [self.badge setTitle:@"Last BG refresh: Not run yet\nAuto-updates: Manage apps" forState:UIControlStateNormal];
        self.badge.accessibilityLabel = @"No completed background refresh recorded. Tap for background and auto-update settings.";
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
