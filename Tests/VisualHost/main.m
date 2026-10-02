#import <UIKit/UIKit.h>

// A real UIKit application context for the native SwiftUI visual tests.
// This target is simulator-only and is not a dependency of QNScaleTest.app.
@interface QNVisualHostDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation QNVisualHostDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *controller = [[UIViewController alloc] init];
    controller.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(QNVisualHostDelegate.class));
    }
}
