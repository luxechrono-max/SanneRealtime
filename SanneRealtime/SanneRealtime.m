#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static NSMutableArray<NSString *> *SRLog;


/* ============================================================
   TIME / LOGGING
   ============================================================ */

static NSString *SRNow(void) {

    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.dateFormat = @"HH:mm:ss.SSS";

    return [formatter stringFromDate:[NSDate date]];
}


static void SRLogLine(NSString *text) {

    if (!SRLog) {
        SRLog = [NSMutableArray array];
    }

    NSString *line =
        [NSString stringWithFormat:
            @"[%@] %@",
            SRNow(),
            text];

    [SRLog addObject:line];

    if (SRLog.count > 150) {
        [SRLog removeObjectAtIndex:0];
    }

    NSLog(@"[SanneRealtime] %@", line);
}


/* ============================================================
   INJECTION PERMISSION
   ============================================================ */

static NSString *SRPermission(void) {

    if (@available(iOS 18.2, *)) {

        AVAudioApplicationMicrophoneInjectionPermission permission =
            [AVAudioApplication sharedInstance]
                .microphoneInjectionPermission;

        switch (permission) {

            case AVAudioApplicationMicrophoneInjectionPermissionGranted:
                return @"GRANTED";

            case AVAudioApplicationMicrophoneInjectionPermissionDenied:
                return @"DENIED";

            case AVAudioApplicationMicrophoneInjectionPermissionUndetermined:
                return @"UNDETERMINED";

            case AVAudioApplicationMicrophoneInjectionPermissionServiceDisabled:
                return @"SERVICE_DISABLED";
        }
    }

    return @"UNAVAILABLE";
}


/* ============================================================
   AUDIO SESSION HELPERS
   ============================================================ */

static NSString *SRCategory(AVAudioSession *session) {

    return session.category ?: @"<none>";
}


static NSString *SRMode(AVAudioSession *session) {

    return session.mode ?: @"<none>";
}


/* ============================================================
   COMPLETE SESSION REPORT
   ============================================================ */

static NSString *SRSessionReport(void) {

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    return [NSString stringWithFormat:

        @"CATEGORY: %@\n"
         "MODE: %@\n"
         "INPUT AVAILABLE: %@\n"
         "INPUT CHANNELS: %ld\n"
         "SAMPLE RATE: %.2f\n"
         "INPUT LATENCY: %.6f\n"
         "OUTPUT LATENCY: %.6f\n"
         "INJECTION AVAILABLE: %@\n"
         "PREFERRED INJECTION MODE: %ld\n"
         "INJECTION PERMISSION: %@",

        SRCategory(session),

        SRMode(session),

        session.isInputAvailable
            ? @"YES"
            : @"NO",

        (long)session.inputNumberOfChannels,

        session.sampleRate,

        session.inputLatency,

        session.outputLatency,

        session.isMicrophoneInjectionAvailable
            ? @"YES"
            : @"NO",

        (long)session.preferredMicrophoneInjectionMode,

        SRPermission()
    ];
}


/* ============================================================
   FIND KEY WINDOW
   ============================================================ */

static UIWindow *SRKeyWindow(void) {

    for (UIScene *scene in
         [UIApplication sharedApplication].connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        for (UIWindow *window in windowScene.windows) {

            if (window.isKeyWindow) {
                return window;
            }
        }
    }

    return nil;
}


/* ============================================================
   POPUP
   ============================================================ */

static void SRPopup(NSString *title,
                    NSString *message) {

    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window =
            SRKeyWindow();

        if (!window) {

            SRLogLine(
                @"POPUP FAILED: NO KEY WINDOW");

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
                alertControllerWithTitle:title
                message:message
                preferredStyle:
                    UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"OK"
                style:UIAlertActionStyleDefault
                handler:nil]];

        [controller
            presentViewController:alert
            animated:YES
            completion:nil];
    });
}


/* ============================================================
   CAPABILITY CHANGE
   ============================================================ */

static void SRInjectionCapabilityChanged(
    NSNotification *notification) {

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    BOOL available =
        session.isMicrophoneInjectionAvailable;

    NSNumber *reported =
        notification.userInfo[
            AVAudioSessionMicrophoneInjectionIsAvailableKey
        ];

    if (reported) {
        available = reported.boolValue;
    }

    SRLogLine(@"========================================");

    SRLogLine(
        @"MICROPHONE INJECTION CAPABILITY CHANGED");

    SRLogLine(@"========================================");

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION AVAILABLE: %@",
            available
                ? @"YES"
                : @"NO"]);

    SRLogLine(
        [NSString stringWithFormat:
            @"PERMISSION: %@",
            SRPermission()]);

    SRLogLine(
        [NSString stringWithFormat:
            @"CATEGORY: %@",
            SRCategory(session)]);

    SRLogLine(
        [NSString stringWithFormat:
            @"MODE: %@",
            SRMode(session)]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT AVAILABLE: %@",
            session.isInputAvailable
                ? @"YES"
                : @"NO"]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT CHANNELS: %ld",
            (long)session.inputNumberOfChannels]);

    SRLogLine(
        [NSString stringWithFormat:
            @"SAMPLE RATE: %.2f",
            session.sampleRate]);

    SRLogLine(
        [NSString stringWithFormat:
            @"PREFERRED INJECTION MODE: %ld",
            (long)session.preferredMicrophoneInjectionMode]);

    /*
     IMPORTANT:

     We still do NOT:

     - create AVAudioEngine
     - tap the microphone
     - generate audio
     - activate AVAudioSession
     - inject audio

     We only test the documented capability and
     select SpokenAudio mode if the system exposes
     the capability.
    */

    if (available) {

        SRLogLine(
            @"*** REAL INJECTION CAPABILITY DETECTED ***");

        if (@available(iOS 18.2, *)) {

            NSError *error = nil;

            BOOL success =
                [session
                    setPreferredMicrophoneInjectionMode:
                        AVAudioSessionMicrophoneInjectionModeSpokenAudio
                    error:&error];

            if (success) {

                SRLogLine(
                    @"SPOKEN AUDIO MODE: SET SUCCESSFULLY");

                SRPopup(
                    @"SanneRealtime\nINJECTION AVAILABLE",

                    [NSString stringWithFormat:

                        @"iOS exposed microphone injection.\n\n"
                         "Permission: %@\n\n"
                         "SpokenAudio mode: SUCCESS\n\n"
                         "Category: %@\n"
                         "Mode: %@\n"
                         "Input channels: %ld\n"
                         "Sample rate: %.0f\n\n"
                         "NO AUDIO WAS GENERATED.",

                        SRPermission(),

                        SRCategory(session),

                        SRMode(session),

                        (long)session.inputNumberOfChannels,

                        session.sampleRate
                    ]);
            }

            else {

                SRLogLine(
                    [NSString stringWithFormat:
                        @"SPOKEN AUDIO MODE: FAILED\nERROR: %@",
                        error]);

                SRPopup(
                    @"SanneRealtime\nINJECTION AVAILABLE",

                    [NSString stringWithFormat:

                        @"iOS reports injection AVAILABLE,\n"
                         "but SpokenAudio mode failed.\n\n"
                         "Permission: %@\n\n"
                         "ERROR:\n%@",

                        SRPermission(),

                        error
                    ]);
            }
        }
    }

    else {

        SRLogLine(
            @"INJECTION CAPABILITY: NO");

        SRPopup(
            @"SanneRealtime\nINJECTION NOT AVAILABLE",

            [NSString stringWithFormat:

                @"iOS currently reports microphone "
                 "injection as UNAVAILABLE.\n\n"
                 "Permission: %@\n\n"
                 "No audio was generated.",

                SRPermission()
            ]);
    }
}


/* ============================================================
   INSTALL CAPABILITY OBSERVER
   ============================================================ */

static void SRInstallCapabilityObserver(void) {

    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    [center
        addObserverForName:
            AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification

        object:nil

        queue:[NSOperationQueue mainQueue]

        usingBlock:^(NSNotification *notification) {

            SRInjectionCapabilityChanged(notification);
        }];

    SRLogLine(
        @"MICROPHONE INJECTION CAPABILITY OBSERVER INSTALLED");
}


/* ============================================================
   AUDIO SESSION ROUTE CHANGE OBSERVER
   ============================================================ */

static void SRInstallRouteObserver(void) {

    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    [center
        addObserverForName:
            AVAudioSessionRouteChangeNotification

        object:nil

        queue:[NSOperationQueue mainQueue]

        usingBlock:^(NSNotification *notification) {

            AVAudioSession *session =
                [AVAudioSession sharedInstance];

            NSNumber *reason =
                notification.userInfo[
                    AVAudioSessionRouteChangeReasonKey
                ];

            SRLogLine(@"----------------------------------------");

            SRLogLine(@"AUDIO ROUTE CHANGE");

            if (reason) {

                SRLogLine(
                    [NSString stringWithFormat:
                        @"ROUTE CHANGE REASON: %ld",
                        (long)reason.integerValue]);
            }

            SRLogLine(
                [NSString stringWithFormat:
                    @"CATEGORY: %@",
                    SRCategory(session)]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"MODE: %@",
                    SRMode(session)]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"INPUT AVAILABLE: %@",
                    session.isInputAvailable
                        ? @"YES"
                        : @"NO"]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"INPUT CHANNELS: %ld",
                    (long)session.inputNumberOfChannels]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"SAMPLE RATE: %.2f",
                    session.sampleRate]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"INJECTION AVAILABLE: %@",
                    session.isMicrophoneInjectionAvailable
                        ? @"YES"
                        : @"NO"]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"PERMISSION: %@",
                    SRPermission()]);

            SRLogLine(@"----------------------------------------");
        }];
}


/* ============================================================
   AUDIO SESSION ACTIVE / INACTIVE OBSERVERS
   ============================================================ */

static void SRInstallSessionObservers(void) {

    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    [center
        addObserverForName:
            AVAudioSessionDidBecomeActiveNotification

        object:nil

        queue:[NSOperationQueue mainQueue]

        usingBlock:^(NSNotification *notification) {

            AVAudioSession *session =
                [AVAudioSession sharedInstance];

            SRLogLine(@"========================================");

            SRLogLine(@"AUDIO SESSION BECAME ACTIVE");

            SRLogLine(
                [NSString stringWithFormat:
                    @"CATEGORY: %@",
                    SRCategory(session)]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"MODE: %@",
                    SRMode(session)]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"INPUT CHANNELS: %ld",
                    (long)session.inputNumberOfChannels]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"SAMPLE RATE: %.2f",
                    session.sampleRate]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"INJECTION AVAILABLE: %@",
                    session.isMicrophoneInjectionAvailable
                        ? @"YES"
                        : @"NO"]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"PERMISSION: %@",
                    SRPermission()]);

            SRLogLine(@"========================================");
        }];


    [center
        addObserverForName:
            AVAudioSessionDidBecomeInactiveNotification

        object:nil

        queue:[NSOperationQueue mainQueue]

        usingBlock:^(NSNotification *notification) {

            AVAudioSession *session =
                [AVAudioSession sharedInstance];

            SRLogLine(@"========================================");

            SRLogLine(@"AUDIO SESSION BECAME INACTIVE");

            SRLogLine(
                [NSString stringWithFormat:
                    @"CATEGORY: %@",
                    SRCategory(session)]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"MODE: %@",
                    SRMode(session)]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"INPUT CHANNELS: %ld",
                    (long)session.inputNumberOfChannels]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"SAMPLE RATE: %.2f",
                    session.sampleRate]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"INJECTION AVAILABLE: %@",
                    session.isMicrophoneInjectionAvailable
                        ? @"YES"
                        : @"NO"]);

            SRLogLine(
                [NSString stringWithFormat:
                    @"PERMISSION: %@",
                    SRPermission()]);

            SRLogLine(@"========================================");
        }];
}


/* ============================================================
   INITIAL STATE
   ============================================================ */

static void SRInitialState(void) {

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    SRLogLine(@"========================================");

    SRLogLine(
        @"SANNE REALTIME - CAPABILITY PROBE");

    SRLogLine(@"========================================");

    SRLogLine(@"ZERO AUDIO GENERATION");

    SRLogLine(@"ZERO AUDIO PLAYBACK");

    SRLogLine(@"ZERO AVAUDIOENGINE");

    SRLogLine(@"ZERO MICROPHONE TAP");

    SRLogLine(@"ZERO AUDIO SESSION ACTIVATION");

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION PERMISSION: %@",
            SRPermission()]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INITIAL INJECTION AVAILABLE: %@",
            session.isMicrophoneInjectionAvailable
                ? @"YES"
                : @"NO"]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INITIAL CATEGORY: %@",
            SRCategory(session)]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INITIAL MODE: %@",
            SRMode(session)]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INITIAL INPUT AVAILABLE: %@",
            session.isInputAvailable
                ? @"YES"
                : @"NO"]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INITIAL INPUT CHANNELS: %ld",
            (long)session.inputNumberOfChannels]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INITIAL SAMPLE RATE: %.2f",
            session.sampleRate]);
}


/* ============================================================
   REQUEST MICROPHONE INJECTION PERMISSION
   ============================================================ */

static void SRRequestInjectionPermission(void) {

    if (@available(iOS 18.2, *)) {

        AVAudioApplicationMicrophoneInjectionPermission current =
            [AVAudioApplication sharedInstance]
                .microphoneInjectionPermission;

        SRLogLine(
            [NSString stringWithFormat:
                @"CURRENT INJECTION PERMISSION: %@",
                SRPermission()]);


        if (current !=
            AVAudioApplicationMicrophoneInjectionPermissionUndetermined) {

            SRLogLine(
                @"INJECTION PERMISSION ALREADY DETERMINED");

            SRPopup(
                @"SanneRealtime\nPERMISSION STATUS",

                [NSString stringWithFormat:

                    @"Injection permission:\n\n%@\n\n"
                     "Injection capability:\n%@\n\n"
                     "No audio was generated.",

                    SRPermission(),

                    [AVAudioSession sharedInstance]
                        .isMicrophoneInjectionAvailable
                        ? @"YES"
                        : @"NO"
                ]);

            return;
        }


        SRLogLine(
            @"REQUESTING MICROPHONE INJECTION PERMISSION");


        [AVAudioApplication
            requestMicrophoneInjectionPermissionWithCompletionHandler:
            ^(AVAudioApplicationMicrophoneInjectionPermission permission) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{

                        NSString *result =
                            @"UNKNOWN";

                        switch (permission) {

                            case AVAudioApplicationMicrophoneInjectionPermissionGranted:

                                result =
                                    @"GRANTED";

                                break;


                            case AVAudioApplicationMicrophoneInjectionPermissionDenied:

                                result =
                                    @"DENIED";

                                break;


                            case AVAudioApplicationMicrophoneInjectionPermissionUndetermined:

                                result =
                                    @"UNDETERMINED";

                                break;


                            case AVAudioApplicationMicrophoneInjectionPermissionServiceDisabled:

                                result =
                                    @"SERVICE_DISABLED";

                                break;
                        }


                        SRLogLine(
                            [NSString stringWithFormat:
                                @"INJECTION PERMISSION RESULT: %@",
                                result]);


                        AVAudioSession *session =
                            [AVAudioSession sharedInstance];


                        SRLogLine(
                            [NSString stringWithFormat:
                                @"POST-PERMISSION INJECTION AVAILABLE: %@",
                                session.isMicrophoneInjectionAvailable
                                    ? @"YES"
                                    : @"NO"]);


                        SRPopup(
                            @"SanneRealtime\nPERMISSION RESULT",

                            [NSString stringWithFormat:

                                @"Microphone injection permission:\n\n%@\n\n"
                                 "Injection capability: %@\n\n"
                                 "Category: %@\n"
                                 "Mode: %@\n"
                                 "Input channels: %ld\n\n"
                                 "NO AUDIO WAS GENERATED.",

                                result,

                                session.isMicrophoneInjectionAvailable
                                    ? @"YES"
                                    : @"NO",

                                SRCategory(session),

                                SRMode(session),

                                (long)session.inputNumberOfChannels
                            ]);
                    });
            }];
    }

    else {

        SRLogLine(
            @"MICROPHONE INJECTION PERMISSION API "
             "UNAVAILABLE ON THIS iOS VERSION");

        SRPopup(
            @"SanneRealtime\nUNAVAILABLE",

            @"Microphone injection requires iOS 18.2 or later.");
    }
}


/* ============================================================
   CONSTRUCTOR
   ============================================================ */

__attribute__((constructor))
static void SanneRealtimeInit(void) {

    @autoreleasepool {

        SRLog =
            [NSMutableArray array];


        /*
         IMPORTANT:

         These observers are passive.

         We do not activate the audio session.
         We do not create AVAudioEngine.
         We do not tap the microphone.
         We do not generate audio.
        */

        SRInstallCapabilityObserver();

        SRInstallRouteObserver();

        SRInstallSessionObservers();


        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                SRInitialState();


                AVAudioSession *session =
                    [AVAudioSession sharedInstance];


                SRPopup(
                    @"SanneRealtime\nCAPABILITY PROBE READY",

                    [NSString stringWithFormat:

                        @"Permission: %@\n\n"
                         "Current injection: %@\n\n"
                         "This build will now request "
                         "Apple's microphone-injection permission.\n\n"
                         "No test voice.\n"
                         "No AVAudioEngine.\n"
                         "No microphone tap.\n"
                         "No audio generation.",

                        SRPermission(),

                        session.isMicrophoneInjectionAvailable
                            ? @"YES"
                            : @"NO"
                    ]);


                /*
                 Request Apple's actual injection permission.

                 This is the only new active operation
                 in this build.
                */

                SRRequestInjectionPermission();
            });
    }
}
