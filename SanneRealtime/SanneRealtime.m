#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static AVAudioEngine *audioEngine = nil;
static AVAudioUnitTimePitch *pitchUnit = nil;

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


static BOOL EnableSpokenAudioInjection(void) {

    if (@available(iOS 18.2, *)) {

        AVAudioSession *session =
            [AVAudioSession sharedInstance];

        if (!session.isMicrophoneInjectionAvailable) {

            NSLog(
                @"[SanneRealtime] Injection unavailable."
            );

            return NO;
        }

        NSError *error = nil;

        BOOL result =
            [session
                setPreferredMicrophoneInjectionMode:
                    AVAudioSessionMicrophoneInjectionModeSpokenAudio
                error:&error];

        if (!result) {

            NSLog(
                @"[SanneRealtime] Injection error: %@",
                error.localizedDescription
            );

            return NO;
        }

        NSLog(
            @"[SanneRealtime] SpokenAudio injection enabled."
        );

        return YES;
    }

    return NO;
}


static void StartRealtimeFemaleTest(void) {

    if (!@available(iOS 18.2, *)) {

        ShowPopup(
            @"iOS 18.2 or newer is required."
        );

        return;
    }

    AVAudioApplication *application =
        [AVAudioApplication sharedInstance];

    AVAudioApplicationMicrophoneInjectionPermission permission =
        application.microphoneInjectionPermission;

    if (permission !=
        AVAudioApplicationMicrophoneInjectionPermissionGranted) {

        ShowPopup(
            @"Microphone injection permission is not granted."
        );

        return;
    }

    if (!EnableSpokenAudioInjection()) {

        ShowPopup(
            @"Permission is granted, but microphone injection "
             "is currently unavailable.\n\n"
             "Start the Discord call first."
        );

        return;
    }


    /*
     * Configure the audio session.
     */
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    NSError *sessionError = nil;

    [session setCategory:
        AVAudioSessionCategoryPlayAndRecord
               mode:
        AVAudioSessionModeVoiceChat
            options:
        AVAudioSessionCategoryOptionDefaultToSpeaker |
        AVAudioSessionCategoryOptionAllowBluetoothHFP
            error:&sessionError];

    if (sessionError) {

        NSLog(
            @"[SanneRealtime] Session configuration: %@",
            sessionError.localizedDescription
        );
    }


    /*
     * Create the realtime engine.
     */
    audioEngine =
        [[AVAudioEngine alloc] init];

    AVAudioInputNode *input =
        audioEngine.inputNode;

    AVAudioFormat *format =
        [input outputFormatForBus:0];

    if (!format ||
        format.sampleRate <= 0 ||
        format.channelCount == 0) {

        ShowPopup(
            @"Microphone input format is unavailable."
        );

        return;
    }

    NSLog(
        @"[SanneRealtime] Input: %.0f Hz / %u channels",
        format.sampleRate,
        format.channelCount
    );


    /*
     * TimePitch performs the first simple
     * male → female-style experiment.
     *
     * +600 cents = +6 semitones.
     */
    pitchUnit =
        [[AVAudioUnitTimePitch alloc] init];

    pitchUnit.pitch = 600.0;
    pitchUnit.rate = 1.0;
    pitchUnit.overlap = 8.0;


    /*
     * Connect:
     *
     * microphone
     *     ↓
     * pitch processor
     *     ↓
     * mixer
     *     ↓
     * output
     */
    [audioEngine
        attachNode:pitchUnit];

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


    /*
     * Start the engine.
     */
    NSError *engineError = nil;

    BOOL started =
        [audioEngine startAndReturnError:&engineError];

    if (!started) {

        ShowPopup(
            [NSString stringWithFormat:
                @"Audio engine FAILED.\n\n%@",
                engineError.localizedDescription
                    ?: @"Unknown error"]
        );

        return;
    }


    NSLog(
        @"[SanneRealtime] REALTIME FEMALE TEST RUNNING."
    );


    ShowPopup(
        @"REALTIME FEMALE TEST RUNNING\n\n"
         "Pitch: +600 cents\n"
         "Rate: 1.0x\n\n"
         "Speak normally now.\n\n"
         "Listen on the OG Discord account."
    );
}


__attribute__((constructor))
static void SanneRealtimeLoaded(void) {

    NSLog(
        @"[SanneRealtime] ========================="
    );

    NSLog(
        @"[SanneRealtime] REALTIME DSP BUILD LOADED"
    );

    NSLog(
        @"[SanneRealtime] ========================="
    );

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            /*
             * Give Discord/Nobanny time to establish
             * the active call audio session.
             */
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    3 * NSEC_PER_SEC
                ),
                dispatch_get_main_queue(),
                ^{

                    StartRealtimeFemaleTest();
                }
            );
        }
    );
}
