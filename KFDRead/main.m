//
//  main.m
//  KFDRead
//
//  Created by 大京 on 2025/10/31.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "kfd_c.h"
#include <string.h>

int main(int argc, char * argv[]) {
    if (argc > 1 && argv[1] && strcmp(argv[1], "-kfdread") == 0) {
        return kfd_entry_run(argc, argv);
    }

    NSString * appDelegateClassName;
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
