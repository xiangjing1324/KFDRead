//
//  AppDelegate.m
//  KFDRead
//
//  Created by 大京 on 2025/10/31.
//

#import "AppDelegate.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 强制使用浅色模式
    if (@available(iOS 13.0, *)) {
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    }
    return YES;
}


@end
