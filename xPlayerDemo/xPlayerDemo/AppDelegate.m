//
//  AppDelegate.m
//  xPlayerDemo
//
//  Created by JSK on 2018/2/22.
//  Copyright © 2018年 JSK. All rights reserved.
//

#import "AppDelegate.h"
#import "DemoViewController.h"


@interface AppDelegate() {
}

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[[DemoViewController alloc] init]];
    [self.window makeKeyAndVisible];
    return YES;
}


- (void)applicationWillTerminate:(UIApplication *)application
{

}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{

}

- (void)applicationWillResignActive:(UIApplication*)application
{

}

- (void)applicationDidEnterBackground:(UIApplication*)application
{

}

- (void)applicationWillEnterForeground:(UIApplication*)application
{

}

- (void)applicationDidBecomeActive:(UIApplication*)application
{

}

@end
