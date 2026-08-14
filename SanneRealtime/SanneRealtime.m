#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static id capabilityObserver = nil;
static BOOL popupVisible = NO;

static NSString *PermissionName(
    AVAudioApplicationMicrophoneInjectionPermission permission
) {
    if (permission ==
        AVAudioApplicationMicrophoneInjectionPermissionGranted) {
        return @"GRANTED";
    }

    if (permission ==
        AVAudioApplicationMicrophoneInjectionPermissionDenied) {
        return @"DENIED";
    }

    if (permission ==
        AVAudioApplicationMicrophoneInjectionPermissionUndetermined) {
        return @"UNDETERMINED";
    }

    return @"SERVICE DISABLED";
}


static void ShowPopup(NSString *message) {

    dispatch_async(dispatch_get_main_queue(), ^{

        if (popupVisible)
            return;

        UIWindow *window = nil;

        if (@available(iOS 13.0, *)) {

            for (UIScene *scene in
                 [UIApplication sharedApplication].connectedScenes) {

                if (scene.activationState !=
                    UISceneActivationStateForegroundActive)
                    continue;

                if (![scene isKindOfClass:[UIWindowScene class]])
                    continue;

                UIWindowScene *windowScene =
                    (UIWindowScene *)scene;

                for (UIWindow *candidate in windowScene.windows) {

                    if (candidate.isKeyWindow) {
                        window = candidate;
                        break;
                    }
                }

                if (window)
                    break;
            }
        }

        if (!window)
            return;

        UIViewController *vc =
            window.rootViewController;

        while (vc.presentedViewController)
            vc = vc.presentedViewController;

        popupVisible = YES;

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:@"SanneRealtime"
                message:message
                preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"OK"
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    popupVisible = NO;
                }]];

        [vc presentViewController:alert
                          animated:YES
                        completion:nil];
    });
}


static void CheckState(NSString *reason) {

    if (!@available(iOS 18.2, *))
        return;

    AVAudioApplication *application =
        [AVAudioApplication sharedInstance];

    AVAudioApplicationMicrophoneInjectionPermission permission =
        application.microphoneInjectionPermission;

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    BOOL available =
        session.isMicrophoneInjectionAvailable;

    NSLog(
        @"[SanneRealtime] %@ | permission=%@ | available=%@",
        reason,
        PermissionName(permission),
        available ? @"YES" : @"NO"
    );


    NSString *message =
        [NSString stringWithFormat:
            @"PERMISSION: %@\n\n"
             "INJECTION AVAILABLE: %@\n\n"
             "Reason: %@",
            PermissionName(permission),
            available ? @"YES" : @"NO",
            reason];


    ShowPopup(message);
}


static void RequestPermission(void) {

    if (!@available(iOS 18.2, *)) {

        ShowPopup(
            @"This build requires iOS 18.2 or newer."
        );

        return;
    }

    AVAudioApplication *application =
        [AVAudioApplication sharedInstance];

    AVAudioApplicationMicrophoneInjectionPermission current =
        application.microphoneInjectionPermission;


    NSLog(
        @"[SanneRealtime] Current permission: %@",
        PermissionName(current)
    );


    /*
     * Apple requires an explicit permission request.
     * If already granted, this immediately returns GRANTED.
     */
    [AVAudioApplication
        requestMicrophoneInjectionPermissionWithCompletionHandler:
        ^(AVAudioApplicationMicrophoneInjectionPermission permission) {

            dispatch_async(
                dispatch_get_main_queue(),
                ^{

                    NSLog(
                        @"[SanneRealtime] Permission result: %@",
                        PermissionName(permission)
                    );

                    if (permission ==
                        AVAudioApplicationMicrophoneInjectionPermissionGranted) {

                        AVAudioSession *session =
                            [AVAudioSession sharedInstance];

                        BOOL available =
                            session.isMicrophoneInjectionAvailable;

                        ShowPopup(
                            [NSString stringWithFormat:
                                @"PERMISSION: GRANTED\n\n"
                                 "INJECTION AVAILABLE: %@\n\n"
                                 "No audio engine started.\n\n"
                                 "This build is only testing "
                                 "the iOS injection state.",
                                available ? @"YES" : @"NO"]
                        );

                    } else {

                        ShowPopup(
                            [NSString stringWithFormat:
                                @"PERMISSION: %@\n\n"
                                 "Injection cannot be used "
                                 "until permission is granted.",
                                PermissionName(permission)]
                        );
                    }
                }
            );
        }
    ];
}


static void InstallObserver(void) {

    if (!@available(iOS 18.2, *))
        return;


    if (capabilityObserver) {
        return;
    }


    capabilityObserver =
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                AVAudioSession *session =
                    [AVAudioSession sharedInstance];

                BOOL available =
                    session.isMicrophoneInjectionAvailable;


                NSLog(
                    @"[SanneRealtime] CAPABILITY CHANGED: %@",
                    available ? @"YES" : @"NO"
                );


                AVAudioApplication *application =
                    [AVAudioApplication sharedInstance];

                NSString *permission =
                    PermissionName(
                        application.microphoneInjectionPermission
                    );


                ShowPopup(
                    [NSString stringWithFormat:
                        @"CAPABILITY CHANGED\n\n"
                         "PERMISSION: %@\n\n"
                         "INJECTION AVAILABLE: %@",
                        permission,
                        available ? @"YES" : @"NO"]
                );
            }];
}


__attribute__((constructor))
static void SanneRealtimeLoaded(void) {

    NSLog(
        @"[SanneRealtime] ========================"
    );

    NSLog(
        @"[SanneRealtime] DIAGNOSTIC BUILD LOADED"
    );

    NSLog(
        @"[SanneRealtime] NO AUDIO ENGINE"
    );

    NSLog(
        @"[SanneRealtime] ========================"
    );


    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            InstallObserver();


            /*
             * Let the host application finish loading.
             */
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    2 * NSEC_PER_SEC
                ),
                dispatch_get_main_queue(),
                ^{

                    RequestPermission();
                }
            );
        }
    );
}
