#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

__attribute__((constructor))
static void SanneRealtimeLoaded(void) {
    NSLog(@"[SanneRealtime] DYLIB LOADED");

    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                3 * NSEC_PER_SEC
            ),
            dispatch_get_main_queue(),
            ^{

                UIWindow *window = nil;

                if (@available(iOS 13.0, *)) {
                    NSSet *scenes =
                        [UIApplication sharedApplication].connectedScenes;

                    for (UIScene *scene in scenes) {

                        if (scene.activationState !=
                            UISceneActivationStateForegroundActive) {
                            continue;
                        }

                        if (![scene isKindOfClass:[UIWindowScene class]]) {
                            continue;
                        }

                        UIWindowScene *windowScene =
                            (UIWindowScene *)scene;

                        for (UIWindow *candidate in windowScene.windows) {

                            if (candidate.isKeyWindow) {
                                window = candidate;
                                break;
                            }
                        }

                        if (window) {
                            break;
                        }
                    }
                }

                if (!window) {
                    NSLog(
                        @"[SanneRealtime] Could not find key window"
                    );
                    return;
                }

                UIViewController *root =
                    window.rootViewController;

                if (!root) {
                    NSLog(
                        @"[SanneRealtime] Could not find root view controller"
                    );
                    return;
                }

                while (root.presentedViewController) {
                    root = root.presentedViewController;
                }

                UIAlertController *alert =
                    [UIAlertController
                        alertControllerWithTitle:@"SanneRealtime"
                        message:@"DYLIB LOADED"
                        preferredStyle:UIAlertControllerStyleAlert];

                UIAlertAction *ok =
                    [UIAlertAction
                        actionWithTitle:@"OK"
                        style:UIAlertActionStyleDefault
                        handler:nil];

                [alert addAction:ok];

                [root presentViewController:alert
                                    animated:YES
                                  completion:nil];

                NSLog(
                    @"[SanneRealtime] Load confirmation displayed"
                );
            }
        );
    });
}
