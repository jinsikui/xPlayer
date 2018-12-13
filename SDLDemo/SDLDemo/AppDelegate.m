
#include "SDL_internal.h"

#if SDL_VIDEO_DRIVER_UIKIT

#include "SDL_sysvideo.h"
#include "SDL_assert.h"
#include "SDL_hints.h"
#include "SDL_system.h"
#include "SDL_main.h"

#import "AppDelegate.h"
#import "SDL_uikitmodes.h"
#import "SDL_uikitwindow.h"

#include "SDL_events_c.h"

#ifdef main
#undef main
#endif

static int forward_argc;
static char **forward_argv;
static int exit_status;

int main(int argc, char **argv)
{
    int i;

    /* store arguments */
    forward_argc = argc;
    forward_argv = (char **)malloc((argc+1) * sizeof(char *));
    for (i = 0; i < argc; i++) {
        forward_argv[i] = malloc( (strlen(argv[i])+1) * sizeof(char));
        strcpy(forward_argv[i], argv[i]);
    }
    forward_argv[i] = NULL;

    /* Give over control to run loop, AppDelegate will handle most things from here */
    @autoreleasepool {
        UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }

    /* free the memory we used to hold copies of argc and argv */
    for (i = 0; i < forward_argc; i++) {
        free(forward_argv[i]);
    }
    free(forward_argv);

    return exit_status;
}

static void SDLCALL
SDL_IdleTimerDisabledChanged(void *userdata, const char *name, const char *oldValue, const char *hint)
{
    BOOL disable = (hint && *hint != '0');
    [UIApplication sharedApplication].idleTimerDisabled = disable;
}

@implementation AppDelegate 

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSBundle *bundle = [NSBundle mainBundle];

    /* Set working directory to resource path */
    [[NSFileManager defaultManager] changeCurrentDirectoryPath:[bundle resourcePath]];

    /* register a callback for the idletimer hint */
    SDL_AddHintCallback(SDL_HINT_IDLE_TIMER_DISABLED,
                        SDL_IdleTimerDisabledChanged, NULL);

    SDL_SetMainReady();
    [self performSelector:@selector(postFinishLaunch) withObject:nil afterDelay:0.0];

    return YES;
}

- (void)postFinishLaunch
{
    /* run the user's application, passing argc and argv */
    SDL_iPhoneSetEventPump(SDL_TRUE);
    exit_status = SDL_main(forward_argc, forward_argv);
    SDL_iPhoneSetEventPump(SDL_FALSE);
    
    /* exit, passing the return status from the user's application */
    /* We don't actually exit to support applications that do setup in their
     * main function and then allow the Cocoa event loop to run. */
    /* exit(exit_status); */
}

- (UIWindow *)window
{
    SDL_VideoDevice *_this = SDL_GetVideoDevice();
    if (_this) {
        SDL_Window *window = NULL;
        for (window = _this->windows; window != NULL; window = window->next) {
            SDL_WindowData *data = (__bridge SDL_WindowData *) window->driverdata;
            if (data != nil) {
                return data.uiwindow;
            }
        }
    }
    return nil;
}

- (void)setWindow:(UIWindow *)window
{
    /* Do nothing. */
}

#if !TARGET_OS_TV
- (void)application:(UIApplication *)application didChangeStatusBarOrientation:(UIInterfaceOrientation)oldStatusBarOrientation
{
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(application.statusBarOrientation);
    SDL_VideoDevice *_this = SDL_GetVideoDevice();

    if (_this && _this->num_displays > 0) {
        SDL_DisplayMode *desktopmode = &_this->displays[0].desktop_mode;
        SDL_DisplayMode *currentmode = &_this->displays[0].current_mode;

        /* The desktop display mode should be kept in sync with the screen
         * orientation so that updating a window's fullscreen state to
         * SDL_WINDOW_FULLSCREEN_DESKTOP keeps the window dimensions in the
         * correct orientation. */
        if (isLandscape != (desktopmode->w > desktopmode->h)) {
            int height = desktopmode->w;
            desktopmode->w = desktopmode->h;
            desktopmode->h = height;
        }

        /* Same deal with the current mode + SDL_GetCurrentDisplayMode. */
        if (isLandscape != (currentmode->w > currentmode->h)) {
            int height = currentmode->w;
            currentmode->w = currentmode->h;
            currentmode->h = height;
        }
    }
}
#endif

- (void)applicationWillTerminate:(UIApplication *)application
{
    SDL_OnApplicationWillTerminate();
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    SDL_OnApplicationDidReceiveMemoryWarning();
}

- (void)applicationWillResignActive:(UIApplication*)application
{
    SDL_OnApplicationWillResignActive();
}

- (void)applicationDidEnterBackground:(UIApplication*)application
{
    SDL_OnApplicationDidEnterBackground();
}

- (void)applicationWillEnterForeground:(UIApplication*)application
{
    SDL_OnApplicationWillEnterForeground();
}

- (void)applicationDidBecomeActive:(UIApplication*)application
{
    SDL_OnApplicationDidBecomeActive();
}

- (void)sendDropFileForURL:(NSURL *)url
{
    NSURL *fileURL = url.filePathURL;
    if (fileURL != nil) {
        SDL_SendDropFile(NULL, fileURL.path.UTF8String);
    } else {
        SDL_SendDropFile(NULL, url.absoluteString.UTF8String);
    }
    SDL_SendDropComplete(NULL);
}

#if TARGET_OS_TV || (defined(__IPHONE_9_0) && __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_9_0)

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options
{
    /* TODO: Handle options */
    [self sendDropFileForURL:url];
    return YES;
}

#else

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    [self sendDropFileForURL:url];
    return YES;
}

#endif

@end

#endif /* SDL_VIDEO_DRIVER_UIKIT */

/* vi: set ts=4 sw=4 expandtab: */
