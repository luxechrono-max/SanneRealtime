#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static NSString *PermissionName(
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
            NSLog(@"[SanneRealtime] No active window");
            return;
        }

        UIViewController *root =
            window.rootViewController;

        if (!root) {
            NSLog(@"[SanneRealtime] No root controller");
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

                if (@available(iOS 18.2, *)) {

                    AVAudioApplication *application =
                        [AVAudioApplication sharedInstance];

                    AVAudioSession *session =
                        [AVAudioSession sharedInstance];

                    AVAudioApplicationMicrophoneInjectionPermission
                        currentPermission =
                            application.microphoneInjectionPermission;

                    NSLog(
                        @"[SanneRealtime] Current permission: %@",
                        PermissionName(currentPermission)
                    );

                    BOOL available =
                        session.isMicrophoneInjectionAvailable;

                    NSLog(
                        @"[SanneRealtime] Injection available: %@",
                        available ? @"YES" : @"NO"
                    );

                    if (!available) {

                        ShowResult(
                            [NSString stringWithFormat:
                                @"Permission: %@\n\n"
                                 "Injection available: NO\n\n"
                                 "Start a Discord voice call and try again.",
                                PermissionName(currentPermission)]
                        );

                        return;
                    }

                    if (
                        currentPermission ==
                        AVAudioApplicationMicrophoneInjectionPermissionGranted
                    ) {

                        ShowResult(
                            @"Permission: GRANTED\n\n"
                             "Injection available: YES"
                        );

                        return;
                    }

                    if (
                        currentPermission ==
                        AVAudioApplicationMicrophoneInjectionPermissionDenied
                    ) {

                        ShowResult(
                            @"Permission: DENIED\n\n"
                             "iOS has already denied microphone injection."
                        );

                        return;
                    }

                    if (
                        currentPermission ==
                        AVAudioApplicationMicrophoneInjectionPermissionServiceDisabled
                    ) {

                        ShowResult(
                            @"Permission: SERVICE DISABLED\n\n"
                             "Microphone injection is disabled by iOS."
                        );

                        return;
                    }

                    NSLog(
                        @"[SanneRealtime] Requesting microphone injection permission..."
                    );

                    [AVAudioApplication
                        requestMicrophoneInjectionPermissionWithCompletionHandler:
                        ^(
                            AVAudioApplicationMicrophoneInjectionPermission permission
                        ) {

                            NSLog(
                                @"[SanneRealtime] Permission result: %@",
                                PermissionName(permission)
                            );

                            BOOL nowAvailable =
                                [AVAudioSession sharedInstance]
                                    .isMicrophoneInjectionAvailable;

                            NSString *result =
                                [NSString stringWithFormat:
                                    @"Permission: %@\n\n"
                                     "Injection available: %@",
                                    PermissionName(permission),
                                    nowAvailable ? @"YES" : @"NO"];

                            ShowResult(result);
                        }
                    ];
                }
                else {

                    ShowResult(
                        @"Microphone injection requires iOS 18.2 or newer."
                    );
                }
            }
        );
    });
}
