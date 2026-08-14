#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static BOOL testRunning = NO;

static void Popup(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;

        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in
                 [UIApplication sharedApplication].connectedScenes) {

                if (scene.activationState !=
                    UISceneActivationStateForegroundActive)
                    continue;

                if (![scene isKindOfClass:[UIWindowScene class]])
                    continue;

                UIWindowScene *ws = (UIWindowScene *)scene;

                for (UIWindow *candidate in ws.windows) {
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

        UIViewController *vc = window.rootViewController;

        while (vc.presentedViewController)
            vc = vc.presentedViewController;

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

        [vc presentViewController:alert
                          animated:YES
                        completion:nil];
    });
}


static void EnableInjection(void) {

    if (!@available(iOS 18.2, *)) {
        Popup(@"iOS 18.2+ required.");
        return;
    }

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    if (!session.isMicrophoneInjectionAvailable) {

        Popup(
            @"PERMISSION: GRANTED\n\n"
             "INJECTION AVAILABLE: NO\n\n"
             "Keep the Discord call connected and "
             "restart Nobanny when the call is established."
        );

        return;
    }


    NSError *error = nil;

    BOOL success =
        [session
            setPreferredMicrophoneInjectionMode:
                AVAudioSessionMicrophoneInjectionModeSpokenAudio
            error:&error];

    if (!success) {

        Popup(
            [NSString stringWithFormat:
                @"Injection mode failed.\n\n%@",
                error.localizedDescription
                    ?: @"Unknown error"]
        );

        return;
    }


    testRunning = YES;

    Popup(
        @"PERMISSION: GRANTED\n\n"
         "INJECTION AVAILABLE: YES\n\n"
         "SPOKEN AUDIO: ENABLED\n\n"
         "INJECTION PATH READY.\n\n"
         "No audio engine is running."
    );
}


static void CheckAndEnable(void) {

    if (!@available(iOS 18.2, *))
        return;

    AVAudioApplication *application =
        [AVAudioApplication sharedInstance];

    AVAudioApplicationMicrophoneInjectionPermission permission =
        application.microphoneInjectionPermission;


    if (permission !=
        AVAudioApplicationMicrophoneInjectionPermissionGranted) {

        [AVAudioApplication
            requestMicrophoneInjectionPermissionWithCompletionHandler:
            ^(AVAudioApplicationMicrophoneInjectionPermission result) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{

                        if (result ==
                            AVAudioApplicationMicrophoneInjectionPermissionGranted) {

                            EnableInjection();

                        } else {

                            Popup(
                                @"Microphone injection permission "
                                 "was not granted."
                            );
                        }
                    }
                );
            }
        ];

        return;
    }


    EnableInjection();
}


static void InstallObserver(void) {

    if (!@available(iOS 18.2, *))
        return;

    [[NSNotificationCenter defaultCenter]
        addObserverForName:
            AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {

            AVAudioSession *session =
                [AVAudioSession sharedInstance];

            NSLog(
                @"[SanneRealtime] Injection capability changed: %@",
                session.isMicrophoneInjectionAvailable
                    ? @"YES"
                    : @"NO"
            );

            /*
             * Only act when the system reports YES.
             */
            if (session.isMicrophoneInjectionAvailable &&
                !testRunning) {

                EnableInjection();
            }
        }];
}


__attribute__((constructor))
static void SanneRealtimeLoaded(void) {

    NSLog(
        @"[SanneRealtime] INJECTION TEST BUILD LOADED"
    );

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            InstallObserver();

            /*
             * Wait for the host/call state to settle.
             */
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    2 * NSEC_PER_SEC
                ),
                dispatch_get_main_queue(),
                ^{

                    CheckAndEnable();
                }
            );
        }
    );
}
