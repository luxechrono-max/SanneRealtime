#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static AVSpeechSynthesizer *synthesizer = nil;

static NSString *PermissionName(
    AVAudioApplicationMicrophoneInjectionPermission p
) {
    switch (p) {
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

static void ShowPopup(NSString *message) {

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
            NSLog(@"[SanneRealtime] No active window.");
            return;
        }

        UIViewController *controller =
            window.rootViewController;

        while (controller.presentedViewController) {
            controller =
                controller.presentedViewController;
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

        [controller presentViewController:alert
                                 animated:YES
                               completion:nil];
    });
}


/*
 * This is called ONLY after Apple's permission request
 * has returned a result.
 */
static void ContinueAfterPermission(
    AVAudioApplicationMicrophoneInjectionPermission permission
) {

    NSLog(
        @"[SanneRealtime] Permission callback: %@",
        PermissionName(permission)
    );

    if (permission !=
        AVAudioApplicationMicrophoneInjectionPermissionGranted) {

        ShowPopup(
            [NSString stringWithFormat:
                @"PERMISSION RESULT: %@\n\n"
                 "Injection permission is not granted.",
                PermissionName(permission)]
        );

        return;
    }

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    BOOL available =
        session.isMicrophoneInjectionAvailable;

    NSLog(
        @"[SanneRealtime] Injection available: %@",
        available ? @"YES" : @"NO"
    );

    if (!available) {

        ShowPopup(
            @"PERMISSION: GRANTED\n\n"
             "INJECTION AVAILABLE: NO\n\n"
             "Keep the Discord call connected and try again."
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

        NSString *errorText =
            error.localizedDescription
            ?: @"Unknown AVAudioSession error.";

        NSLog(
            @"[SanneRealtime] Failed to enable injection: %@",
            errorText
        );

        ShowPopup(
            [NSString stringWithFormat:
                @"PERMISSION: GRANTED\n\n"
                 "INJECTION AVAILABLE: YES\n\n"
                 "FAILED TO ENABLE SPOKEN AUDIO:\n%@",
                errorText]
        );

        return;
    }

    NSLog(
        @"[SanneRealtime] SpokenAudio injection ENABLED."
    );

    ShowPopup(
        @"PERMISSION: GRANTED\n\n"
         "INJECTION AVAILABLE: YES\n\n"
         "SPOKEN AUDIO: ENABLED\n\n"
         "Sending test speech..."
    );

    /*
     * Keep the synthesizer alive.
     */
    synthesizer =
        [[AVSpeechSynthesizer alloc] init];

    AVSpeechUtterance *utterance =
        [[AVSpeechUtterance alloc]
            initWithString:
                @"SanneRealtime test. "
                 "This audio is being injected into the call."];

    utterance.rate = 0.48;
    utterance.volume = 1.0;

    AVSpeechSynthesisVoice *voice =
        [AVSpeechSynthesisVoice
            voiceWithLanguage:@"en-US"];

    if (voice) {
        utterance.voice = voice;
    }

    /*
     * Wait briefly so the popup is visible and the
     * call audio session is fully established.
     */
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            2 * NSEC_PER_SEC
        ),
        dispatch_get_main_queue(),
        ^{

            NSLog(
                @"[SanneRealtime] Speaking test sentence."
            );

            [synthesizer speakUtterance:utterance];
        }
    );
}


/*
 * Request permission first.
 *
 * Apple documents that if permission has already been
 * granted/denied, this callback returns immediately.
 * Otherwise iOS presents the permission dialog.
 */
static void RequestPermissionAndTest(void) {

    if (@available(iOS 18.2, *)) {

        AVAudioApplication *application =
            [AVAudioApplication sharedInstance];

        AVAudioApplicationMicrophoneInjectionPermission
            currentPermission =
                application.microphoneInjectionPermission;

        NSLog(
            @"[SanneRealtime] Current permission: %@",
            PermissionName(currentPermission)
        );

        /*
         * Always use Apple's request API here.
         * This is important because the callback gives us
         * the authoritative permission result.
         */
        [AVAudioApplication
            requestMicrophoneInjectionPermissionWithCompletionHandler:
            ^(AVAudioApplicationMicrophoneInjectionPermission result) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{

                        ContinueAfterPermission(result);
                    }
                );
            }
        ];

    } else {

        ShowPopup(
            @"iOS 18.2 or newer is required."
        );
    }
}


/*
 * Watch for the call becoming injection-capable.
 *
 * The capability can change when the call starts/ends,
 * so don't rely exclusively on the state at launch.
 */
static void StartCapabilityObserver(void) {

    if (@available(iOS 18.2, *)) {

        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                AVAudioSession *session =
                    [AVAudioSession sharedInstance];

                NSLog(
                    @"[SanneRealtime] Capability changed: %@",
                    session.isMicrophoneInjectionAvailable
                        ? @"YES"
                        : @"NO"
                );
            }];
    }
}


__attribute__((constructor))
static void SanneRealtimeLoaded(void) {

    NSLog(
        @"[SanneRealtime] ======================="
    );

    NSLog(
        @"[SanneRealtime] DYLIB LOADED"
    );

    NSLog(
        @"[SanneRealtime] ======================="
    );

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            StartCapabilityObserver();

            /*
             * Wait for Nobanny/Discord to finish
             * initializing its audio environment.
             */
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    3 * NSEC_PER_SEC
                ),
                dispatch_get_main_queue(),
                ^{

                    RequestPermissionAndTest();
                }
            );
        }
    );
}
