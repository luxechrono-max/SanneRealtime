#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static NSString *PermissionText(
    AVAudioApplicationMicrophoneInjectionPermission permission
) {
    switch (permission) {
        case AVAudioApplicationMicrophoneInjectionPermissionServiceDisabled:
            return @"SERVICE DISABLED";

        case AVAudioApplicationMicrophoneInjectionPermissionUndetermined:
            return @"UNDETERMINED";

        case AVAudioApplicationMicrophoneInjectionPermissionGranted:
            return @"GRANTED";

        case AVAudioApplicationMicrophoneInjectionPermissionDenied:
            return @"DENIED";
    }

    return @"UNKNOWN";
}

static void ShowResult(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;

        if (@available(iOS 13.0, *)) {
            for (UIScene *scene
                 in [UIApplication sharedApplication].connectedScenes) {

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
            NSLog(@"[SanneRealtime] No active window");
            return;
        }

        UIViewController *root =
            window.rootViewController;

        if (!root) {
            return;
        }

        while (root.presentedViewController) {
            root = root.presentedViewController;
        }

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:@"SanneRealtime"
                message:message
                preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"OK"
                style:UIAlertActionStyleDefault
                handler:nil]];

        [root presentViewController:alert
                           animated:YES
                         completion:nil];
    });
}

static void CheckPermission(void) {

    if (@available(iOS 18.2, *)) {

        AVAudioApplication *app =
            [AVAudioApplication sharedInstance];

        AVAudioSession *session =
            [AVAudioSession sharedInstance];

        AVAudioApplicationMicrophoneInjectionPermission before =
            app.microphoneInjectionPermission;

        BOOL available =
            session.isMicrophoneInjectionAvailable;

        NSLog(
            @"[SanneRealtime] BEFORE: permission=%@ available=%@",
            PermissionText(before),
            available ? @"YES" : @"NO"
        );

        /*
         * Ask iOS directly.
         *
         * If permission was already decided, Apple says this
         * completion handler returns the stored result immediately.
         * If it was still undetermined, iOS presents the dialog.
         */
        [AVAudioApplication
            requestMicrophoneInjectionPermissionWithCompletionHandler:
            ^(AVAudioApplicationMicrophoneInjectionPermission result) {

                AVAudioApplication *updatedApp =
                    [AVAudioApplication sharedInstance];

                AVAudioSession *updatedSession =
                    [AVAudioSession sharedInstance];

                AVAudioApplicationMicrophoneInjectionPermission after =
                    updatedApp.microphoneInjectionPermission;

                BOOL availableAfter =
                    updatedSession.isMicrophoneInjectionAvailable;

                NSString *message =
                    [NSString stringWithFormat:
                        @"REQUEST RESULT: %@\n\n"
                         "STORED PERMISSION: %@\n\n"
                         "INJECTION AVAILABLE: %@",
                        PermissionText(result),
                        PermissionText(after),
                        availableAfter ? @"YES" : @"NO"];

                NSLog(
                    @"[SanneRealtime] %@",
                    message
                );

                ShowResult(message);
            }
        ];
    }
    else {
        ShowResult(
            @"This test requires iOS 18.2 or newer."
        );
    }
}

__attribute__((constructor))
static void SanneRealtimeLoaded(void) {

    NSLog(@"[SanneRealtime] DYLIB LOADED");

    dispatch_async(dispatch_get_main_queue(), ^{

        /*
         * Give Nobanny time to finish launching.
         */
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                3 * NSEC_PER_SEC
            ),
            dispatch_get_main_queue(),
            ^{
                CheckPermission();
            }
        );
    });
}
