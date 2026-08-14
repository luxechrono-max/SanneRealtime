#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>

static AVAudioEngine *engine = nil;
static AVAudioPlayerNode *player = nil;
static AVAudioUnitTimePitch *pitch = nil;

static BOOL running = NO;
static BOOL injectionReady = NO;

static void Popup(NSString *text) {

    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window = nil;

        if (@available(iOS 13.0, *)) {

            for (UIScene *scene
                 in UIApplication.sharedApplication.connectedScenes) {

                if (scene.activationState !=
                    UISceneActivationStateForegroundActive)
                    continue;

                if (![scene isKindOfClass:[UIWindowScene class]])
                    continue;

                UIWindowScene *ws = (UIWindowScene *)scene;

                for (UIWindow *w in ws.windows) {

                    if (w.isKeyWindow) {
                        window = w;
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

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:@"SanneRealtime"
                message:text
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


/*
 * Stop everything cleanly.
 */
static void StopRealtime(void) {

    if (!running)
        return;

    NSLog(@"[SanneRealtime] Stopping realtime engine.");

    if (player) {
        [player stop];
    }

    if (engine) {
        [engine stop];
        [engine reset];
    }

    engine = nil;
    player = nil;
    pitch = nil;

    running = NO;
}


/*
 * Start the realtime processing graph.
 *
 * IMPORTANT:
 * We do NOT change Discord's AVAudioSession
 * category or activate/deactivate it.
 */
static void StartRealtime(void) {

    if (running)
        return;

    if (!injectionReady)
        return;

    NSLog(@"[SanneRealtime] Starting realtime processor.");

    engine =
        [[AVAudioEngine alloc] init];

    AVAudioInputNode *input =
        engine.inputNode;

    AVAudioFormat *inputFormat =
        [input inputFormatForBus:0];

    if (!inputFormat ||
        inputFormat.sampleRate <= 0 ||
        inputFormat.channelCount == 0) {

        NSLog(
            @"[SanneRealtime] Invalid input format."
        );

        Popup(
            @"REALTIME FAILED\n\n"
             "Could not obtain microphone format."
        );

        StopRealtime();
        return;
    }


    NSLog(
        @"[SanneRealtime] Input %.0f Hz / %u channels",
        inputFormat.sampleRate,
        inputFormat.channelCount
    );


    /*
     * Female-style pitch test.
     *
     * +500 cents = +5 semitones.
     *
     * This is deliberately NOT Sanne AI yet.
     */
    pitch =
        [[AVAudioUnitTimePitch alloc] init];

    pitch.pitch = 500.0;
    pitch.rate = 1.0;


    player =
        [[AVAudioPlayerNode alloc] init];


    [engine attachNode:pitch];
    [engine attachNode:player];


    /*
     * Mic
     *  ↓
     * TimePitch
     *  ↓
     * Player
     */
    [engine
        connect:input
        to:pitch
        format:inputFormat];

    [engine
        connect:pitch
        to:player
        format:inputFormat];


    /*
     * Capture the microphone continuously.
     *
     * We deliberately don't modify the buffers here yet.
     * The purpose of this first live test is proving that
     * the realtime processing graph can remain alive.
     */
    [input
        installTapOnBus:0
        bufferSize:1024
        format:inputFormat
        block:^(AVAudioPCMBuffer *buffer,
                AVAudioTime *when) {

            if (!running)
                return;

            NSLog(
                @"[SanneRealtime] PCM %.0f Hz, frames=%u",
                buffer.format.sampleRate,
                buffer.frameLength
            );
        }];


    NSError *error = nil;

    if (![engine startAndReturnError:&error]) {

        NSLog(
            @"[SanneRealtime] Engine start failed: %@",
            error.localizedDescription
        );

        Popup(
            [NSString stringWithFormat:
                @"REALTIME ENGINE FAILED\n\n%@",
                error.localizedDescription
                    ?: @"Unknown error"]
        );

        StopRealtime();
        return;
    }


    [player play];

    running = YES;

    NSLog(
        @"[SanneRealtime] REALTIME PROCESSOR RUNNING."
    );


    Popup(
        @"REALTIME PROCESSOR RUNNING\n\n"
         "Male → +500 cents\n\n"
         "Speak normally.\n\n"
         "This is the first live-processing test."
    );
}


/*
 * Called when iOS reports that microphone injection
 * became available.
 */
static void CheckInjection(void) {

    if (!@available(iOS 18.2, *))
        return;

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    if (!session.isMicrophoneInjectionAvailable) {

        injectionReady = NO;

        StopRealtime();

        NSLog(
            @"[SanneRealtime] Injection unavailable."
        );

        return;
    }


    NSError *error = nil;

    BOOL result =
        [session
            setPreferredMicrophoneInjectionMode:
                AVAudioSessionMicrophoneInjectionModeSpokenAudio
            error:&error];

    if (!result) {

        NSLog(
            @"[SanneRealtime] SpokenAudio failed: %@",
            error.localizedDescription
        );

        Popup(
            [NSString stringWithFormat:
                @"SPOKEN AUDIO FAILED\n\n%@",
                error.localizedDescription
                    ?: @"Unknown error"]
        );

        return;
    }


    injectionReady = YES;

    NSLog(
        @"[SanneRealtime] SpokenAudio enabled."
    );


    /*
     * Wait a moment for the call's audio route to settle.
     */
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            500 * NSEC_PER_MSEC
        ),
        dispatch_get_main_queue(),
        ^{

            StartRealtime();
        }
    );
}


/*
 * Watch for Discord call state changes.
 */
static void InstallInjectionObserver(void) {

    if (!@available(iOS 18.2, *))
        return;

    [[NSNotificationCenter defaultCenter]
        addObserverForName:
            AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
        object:nil
        queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *note) {

            AVAudioSession *session =
                [AVAudioSession sharedInstance];

            BOOL available =
                session.isMicrophoneInjectionAvailable;

            NSLog(
                @"[SanneRealtime] Injection capability: %@",
                available ? @"YES" : @"NO"
            );


            if (available) {

                CheckInjection();

            } else {

                injectionReady = NO;

                StopRealtime();
            }
        }];
}


/*
 * Permission.
 */
static void RequestPermission(void) {

    if (!@available(iOS 18.2, *)) {
        Popup(@"iOS 18.2+ required.");
        return;
    }


    AVAudioApplication *application =
        [AVAudioApplication sharedInstance];


    if (application.microphoneInjectionPermission ==
        AVAudioApplicationMicrophoneInjectionPermissionGranted) {

        CheckInjection();
        return;
    }


    [AVAudioApplication
        requestMicrophoneInjectionPermissionWithCompletionHandler:
        ^(AVAudioApplicationMicrophoneInjectionPermission result) {

            dispatch_async(
                dispatch_get_main_queue(),
                ^{

                    if (result ==
                        AVAudioApplicationMicrophoneInjectionPermissionGranted) {

                        CheckInjection();

                    } else {

                        Popup(
                            @"MICROPHONE INJECTION PERMISSION "
                             "WAS NOT GRANTED."
                        );
                    }
                }
            );
        }];
}


/*
 * Constructor.
 */
__attribute__((constructor))
static void SanneRealtimeLoaded(void) {

    NSLog(
        @"[SanneRealtime] ======================="
    );

    NSLog(
        @"[SanneRealtime] LIVE FEMALE DSP BUILD"
    );

    NSLog(
        @"[SanneRealtime] ======================="
    );


    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            InstallInjectionObserver();


            /*
             * Give Discord time to establish the call.
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
