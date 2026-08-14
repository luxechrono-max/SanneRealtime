#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static AVAudioEngine *audioEngine = nil;
static AVAudioUnitTimePitch *pitchUnit = nil;
static BOOL testStarted = NO;

static void ShowPopup(NSString *message) {
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


static void StartFemaleDSP(void);


static void WaitForInjectionAndStart(void) {

    if (@available(iOS 18.2, *)) {

        AVAudioSession *session =
            [AVAudioSession sharedInstance];

        if (!session.isMicrophoneInjectionAvailable) {

            NSLog(@"[SanneRealtime] Injection unavailable.");

            ShowPopup(
                @"PERMISSION: GRANTED\n\n"
                 "INJECTION AVAILABLE: NO\n\n"
                 "Keep the Discord call connected and try again."
            );

            return;
        }

        StartFemaleDSP();
    }
}


static void StartFemaleDSP(void) {

    if (testStarted)
        return;

    testStarted = YES;

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    NSError *error = nil;

    BOOL injectionOK =
        [session
            setPreferredMicrophoneInjectionMode:
                AVAudioSessionMicrophoneInjectionModeSpokenAudio
            error:&error];

    if (!injectionOK) {

        testStarted = NO;

        ShowPopup(
            [NSString stringWithFormat:
                @"INJECTION FAILED\n\n%@",
                error.localizedDescription
                    ?: @"Unknown error"]
        );

        return;
    }

    NSLog(
        @"[SanneRealtime] SpokenAudio injection enabled."
    );


    /*
     * IMPORTANT:
     * We don't change Discord's AVAudioSession category here.
     * Discord owns the active call audio session.
     */


    audioEngine =
        [[AVAudioEngine alloc] init];

    AVAudioInputNode *input =
        audioEngine.inputNode;

    AVAudioFormat *format =
        [input outputFormatForBus:0];

    if (!format || format.channelCount == 0) {

        testStarted = NO;

        ShowPopup(
            @"Could not obtain microphone format."
        );

        return;
    }

    NSLog(
        @"[SanneRealtime] Microphone: %.0f Hz, %u channels",
        format.sampleRate,
        format.channelCount
    );


    /*
     * First female-style experiment:
     *
     * +600 cents = +6 semitones
     *
     * This is NOT neural voice conversion yet.
     */
    pitchUnit =
        [[AVAudioUnitTimePitch alloc] init];

    pitchUnit.pitch = 600.0;
    pitchUnit.rate = 1.0;
    pitchUnit.overlap = 8.0;


    [audioEngine attachNode:pitchUnit];


    /*
     * Microphone
     *     ↓
     * TimePitch
     *     ↓
     * Mixer
     *     ↓
     * App output
     *
     * SpokenAudio mode allows the app's spoken audio
     * to be added to the other app's input stream.
     */
    [audioEngine
        connect:input
        to:pitchUnit
        format:format];

    [audioEngine
        connect:pitchUnit
        to:audioEngine.mainMixerNode
        format:format];

    [audioEngine
        connect:audioEngine.mainMixerNode
        to:audioEngine.outputNode
        format:format];


    NSError *engineError = nil;

    BOOL started =
        [audioEngine startAndReturnError:&engineError];

    if (!started) {

        testStarted = NO;

        ShowPopup(
            [NSString stringWithFormat:
                @"AUDIO ENGINE FAILED\n\n%@",
                engineError.localizedDescription
                    ?: @"Unknown audio-engine error"]
        );

        return;
    }


    NSLog(
        @"[SanneRealtime] REALTIME FEMALE DSP STARTED."
    );

    ShowPopup(
        @"PERMISSION: GRANTED\n\n"
         "INJECTION AVAILABLE: YES\n\n"
         "SPOKEN AUDIO: ENABLED\n\n"
         "REALTIME FEMALE TEST RUNNING\n\n"
         "Pitch: +600 cents\n"
         "Rate: 1.0x\n\n"
         "Speak normally now."
    );
}


static void RequestInjectionPermission(void) {

    if (!@available(iOS 18.2, *)) {

        ShowPopup(
            @"Microphone injection requires iOS 18.2 or newer."
        );

        return;
    }


    AVAudioApplication *application =
        [AVAudioApplication sharedInstance];


    NSLog(
        @"[SanneRealtime] Current permission = %ld",
        (long)application.microphoneInjectionPermission
    );


    /*
     * THIS IS THE IMPORTANT FIX.
     *
     * We request permission instead of merely checking it.
     *
     * If already granted, Apple immediately calls the
     * completion handler with GRANTED.
     *
     * If undetermined, iOS displays the Allow dialog.
     */
    [AVAudioApplication
        requestMicrophoneInjectionPermissionWithCompletionHandler:
        ^(AVAudioApplicationMicrophoneInjectionPermission permission) {

            NSLog(
                @"[SanneRealtime] Permission callback = %ld",
                (long)permission
            );


            if (permission !=
                AVAudioApplicationMicrophoneInjectionPermissionGranted) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{

                        ShowPopup(
                            [NSString stringWithFormat:
                                @"PERMISSION RESULT: %ld\n\n"
                                 "Microphone injection permission "
                                 "was not granted.",
                                (long)permission]
                        );
                    }
                );

                return;
            }


            /*
             * Permission is definitely granted.
             *
             * Now check whether the active Discord call has
             * made injection available.
             */
            dispatch_async(
                dispatch_get_main_queue(),
                ^{

                    WaitForInjectionAndStart();
                }
            );
        }
    ];
}


static void InstallCapabilityObserver(void) {

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

            BOOL available =
                session.isMicrophoneInjectionAvailable;

            NSLog(
                @"[SanneRealtime] Injection capability changed: %@",
                available ? @"YES" : @"NO"
            );


            if (available &&
                !testStarted) {

                /*
                 * Capability just became available.
                 * Request again; if permission is already granted,
                 * the callback returns GRANTED immediately.
                 */
                RequestInjectionPermission();
            }
        }];
}


__attribute__((constructor))
static void SanneRealtimeLoaded(void) {

    NSLog(
        @"[SanneRealtime] ========================="
    );

    NSLog(
        @"[SanneRealtime] REALTIME FEMALE BUILD LOADED"
    );

    NSLog(
        @"[SanneRealtime] ========================="
    );


    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            InstallCapabilityObserver();


            /*
             * Give Discord/Nobanny a few seconds to establish
             * the call audio session.
             */
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    3 * NSEC_PER_SEC
                ),
                dispatch_get_main_queue(),
                ^{

                    RequestInjectionPermission();
                }
            );
        }
    );
}
