#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static NSMutableArray<NSString *> *SRLog;

static BOOL SRObserversInstalled = NO;
static BOOL SRCapabilityPopupShown = NO;

#pragma mark - Logging

static NSString *SRNow(void) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss.SSS";
    return [formatter stringFromDate:[NSDate date]];
}

static void SRLogLine(NSString *text) {

    if (!SRLog) {
        SRLog = [NSMutableArray array];
    }

    NSString *line =
        [NSString stringWithFormat:@"[%@] %@",
         SRNow(),
         text];

    [SRLog addObject:line];

    if (SRLog.count > 200) {
        [SRLog removeObjectAtIndex:0];
    }

    NSLog(@"[SanneRealtime] %@", line);
}

#pragma mark - Audio Session

static AVAudioSession *SRSession(void) {
    return [AVAudioSession sharedInstance];
}

static NSString *SRPermission(void) {

    if (@available(iOS 18.2, *)) {

        AVAudioApplication *application =
            [AVAudioApplication sharedInstance];

        AVAudioApplicationMicrophoneInjectionPermission permission =
            application.microphoneInjectionPermission;

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

static NSString *SRCategory(AVAudioSession *session) {

    if (!session.category) {
        return @"<none>";
    }

    return session.category;
}

static NSString *SRMode(AVAudioSession *session) {

    if (!session.mode) {
        return @"<none>";
    }

    return session.mode;
}

static NSString *SRInjectionModeName(
    AVAudioSessionMicrophoneInjectionMode mode
) {

    switch (mode) {

        case AVAudioSessionMicrophoneInjectionModeNone:
            return @"NONE";

        case AVAudioSessionMicrophoneInjectionModeSpokenAudio:
            return @"SPOKEN_AUDIO";
    }

    return [NSString stringWithFormat:
        @"UNKNOWN(%ld)",
        (long)mode];
}

#pragma mark - Complete State

static NSString *SRSessionReport(void) {

    AVAudioSession *session = SRSession();

    return [NSString stringWithFormat:

        @"CATEGORY: %@\n"
         "MODE: %@\n"
         "INPUT AVAILABLE: %@\n"
         "INPUT CHANNELS: %ld\n"
         "SAMPLE RATE: %.2f\n"
         "INPUT LATENCY: %.6f\n"
         "OUTPUT LATENCY: %.6f\n"
         "INJECTION AVAILABLE: %@\n"
         "PREFERRED INJECTION MODE: %@\n"
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

        SRInjectionModeName(
            session.preferredMicrophoneInjectionMode
        ),

        SRPermission()
    ];
}

#pragma mark - Window

static UIWindow *SRKeyWindow(void) {

    UIApplication *application =
        [UIApplication sharedApplication];

    for (UIScene *scene in application.connectedScenes) {

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

#pragma mark - Popup

static void SRPopup(
    NSString *title,
    NSString *message
) {

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            UIWindow *window = SRKeyWindow();

            if (!window) {
                SRLogLine(@"POPUP FAILED: NO KEY WINDOW");
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
                    preferredStyle:UIAlertControllerStyleAlert];

            [alert addAction:
                [UIAlertAction
                    actionWithTitle:@"OK"
                    style:UIAlertActionStyleDefault
                    handler:nil]];

            [controller
                presentViewController:alert
                animated:YES
                completion:nil];
        }
    );
}

#pragma mark - Capability Event

static void SRInjectionCapabilityChanged(
    NSNotification *notification
) {

    AVAudioSession *session = SRSession();

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
    SRLogLine(@"MICROPHONE INJECTION CAPABILITY EVENT");
    SRLogLine(@"========================================");

    SRLogLine(
        [NSString stringWithFormat:
            @"NOTIFICATION VALUE: %@",
            reported
                ? (reported.boolValue
                    ? @"YES"
                    : @"NO")
                : @"<none>"]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION AVAILABLE: %@",
            available
                ? @"YES"
                : @"NO"]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"PERMISSION: %@",
            SRPermission()]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"CATEGORY: %@",
            SRCategory(session)]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"MODE: %@",
            SRMode(session)]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT AVAILABLE: %@",
            session.isInputAvailable
                ? @"YES"
                : @"NO"]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT CHANNELS: %ld",
            (long)session.inputNumberOfChannels]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"SAMPLE RATE: %.2f",
            session.sampleRate]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"PREFERRED INJECTION MODE: %@",
            SRInjectionModeName(
                session.preferredMicrophoneInjectionMode
            )]
    );

    if (available) {

        SRLogLine(@"*** INJECTION CAPABILITY DETECTED ***");

        if (@available(iOS 18.2, *)) {

            NSError *error = nil;

            BOOL success =
                [session
                    setPreferredMicrophoneInjectionMode:
                        AVAudioSessionMicrophoneInjectionModeSpokenAudio
                    error:&error];

            if (success) {

                SRLogLine(
                    @"SPOKEN AUDIO MODE SET SUCCESSFULLY"
                );

                SRLogLine(
                    [NSString stringWithFormat:
                        @"STATE AFTER MODE SET:\n%@",
                        SRSessionReport()]
                );

                if (!SRCapabilityPopupShown) {

                    SRCapabilityPopupShown = YES;

                    SRPopup(
                        @"SanneRealtime\nINJECTION AVAILABLE",

                        [NSString stringWithFormat:

                            @"Apple reports microphone "
                             "injection AVAILABLE.\n\n"
                             "Permission: %@\n"
                             "SpokenAudio mode: SUCCESS\n\n"
                             "Category: %@\n"
                             "Mode: %@\n"
                             "Input channels: %ld\n"
                             "Sample rate: %.0f\n\n"
                             "NO TEST AUDIO WAS GENERATED.",

                            SRPermission(),

                            SRCategory(session),

                            SRMode(session),

                            (long)session.inputNumberOfChannels,

                            session.sampleRate]
                    );
                }

            } else {

                SRLogLine(
                    [NSString stringWithFormat:
                        @"SPOKEN AUDIO MODE FAILED: %@",
                        error]
                );

                SRPopup(
                    @"SanneRealtime\nMODE FAILED",

                    [NSString stringWithFormat:

                        @"Injection capability: YES\n\n"
                         "Permission: %@\n\n"
                         "SpokenAudio mode failed.\n\n"
                         "ERROR:\n%@",

                        SRPermission(),
                        error]
                );
            }
        }

    } else {

        SRLogLine(
            @"INJECTION CAPABILITY STILL NOT AVAILABLE"
        );
    }
}

#pragma mark - Route Change

static void SRRouteChanged(
    NSNotification *notification
) {

    AVAudioSession *session = SRSession();

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
                (long)reason.integerValue]
        );
    }

    SRLogLine(
        [NSString stringWithFormat:
            @"CATEGORY: %@",
            SRCategory(session)]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"MODE: %@",
            SRMode(session)]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT AVAILABLE: %@",
            session.isInputAvailable
                ? @"YES"
                : @"NO"]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT CHANNELS: %ld",
            (long)session.inputNumberOfChannels]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"SAMPLE RATE: %.2f",
            session.sampleRate]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION AVAILABLE: %@",
            session.isMicrophoneInjectionAvailable
                ? @"YES"
                : @"NO"]
    );

    SRLogLine(@"----------------------------------------");
}

#pragma mark - Interruption

static void SRInterruptionChanged(
    NSNotification *notification
) {

    NSNumber *type =
        notification.userInfo[
            AVAudioSessionInterruptionTypeKey
        ];

    SRLogLine(@"========================================");
    SRLogLine(@"AUDIO INTERRUPTION EVENT");

    if (type) {

        if (type.integerValue ==
            AVAudioSessionInterruptionTypeBegan) {

            SRLogLine(@"INTERRUPTION: BEGAN");

        } else if (
            type.integerValue ==
            AVAudioSessionInterruptionTypeEnded
        ) {

            SRLogLine(@"INTERRUPTION: ENDED");

        } else {

            SRLogLine(
                [NSString stringWithFormat:
                    @"INTERRUPTION TYPE: %ld",
                    (long)type.integerValue]
            );
        }
    }

    SRLogLine(
        [NSString stringWithFormat:
            @"CURRENT STATE:\n%@",
            SRSessionReport()]
    );

    SRLogLine(@"========================================");
}

#pragma mark - App Lifecycle

static void SRApplicationActive(
    NSNotification *notification
) {

    AVAudioSession *session = SRSession();

    SRLogLine(@"========================================");
    SRLogLine(@"APPLICATION BECAME ACTIVE");

    SRLogLine(
        [NSString stringWithFormat:
            @"PERMISSION: %@",
            SRPermission()]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION AVAILABLE: %@",
            session.isMicrophoneInjectionAvailable
                ? @"YES"
                : @"NO"]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"CATEGORY: %@",
            SRCategory(session)]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"MODE: %@",
            SRMode(session)]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT CHANNELS: %ld",
            (long)session.inputNumberOfChannels]
    );

    SRLogLine(@"========================================");
}

static void SRApplicationInactive(
    NSNotification *notification
) {

    SRLogLine(@"========================================");
    SRLogLine(@"APPLICATION WILL RESIGN ACTIVE");

    SRLogLine(
        [NSString stringWithFormat:
            @"STATE:\n%@",
            SRSessionReport()]
    );

    SRLogLine(@"========================================");
}

#pragma mark - Media Reset

static void SRMediaServicesReset(
    NSNotification *notification
) {

    SRLogLine(@"========================================");
    SRLogLine(@"MEDIA SERVICES RESET");

    SRLogLine(
        [NSString stringWithFormat:
            @"STATE:\n%@",
            SRSessionReport()]
    );

    SRLogLine(@"========================================");
}

#pragma mark - Observers

static void SRInstallObservers(void) {

    if (SRObserversInstalled) {
        return;
    }

    SRObserversInstalled = YES;

    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    /*
     Apple microphone-injection capability notification.
    */

    [center
        addObserverForName:
            AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRInjectionCapabilityChanged(
                notification
            );
        }];

    SRLogLine(
        @"OBSERVER INSTALLED: INJECTION CAPABILITY"
    );

    /*
     Audio route changes.
    */

    [center
        addObserverForName:
            AVAudioSessionRouteChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRRouteChanged(notification);
        }];

    SRLogLine(
        @"OBSERVER INSTALLED: ROUTE CHANGE"
    );

    /*
     Audio interruptions.
    */

    [center
        addObserverForName:
            AVAudioSessionInterruptionNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRInterruptionChanged(notification);
        }];

    SRLogLine(
        @"OBSERVER INSTALLED: INTERRUPTION"
    );

    /*
     UIApplication lifecycle.

     IMPORTANT:
     We intentionally do NOT use:

     AVAudioSessionDidBecomeActiveNotification
     AVAudioSessionDidBecomeInactiveNotification

     Those symbols are unavailable in the SDK being used.
    */

    [center
        addObserverForName:
            UIApplicationDidBecomeActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRApplicationActive(notification);
        }];

    SRLogLine(
        @"OBSERVER INSTALLED: APPLICATION ACTIVE"
    );

    [center
        addObserverForName:
            UIApplicationWillResignActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRApplicationInactive(notification);
        }];

    SRLogLine(
        @"OBSERVER INSTALLED: APPLICATION INACTIVE"
    );

    /*
     Media services reset.
    */

    [center
        addObserverForName:
            AVAudioSessionMediaServicesWereResetNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRMediaServicesReset(notification);
        }];

    SRLogLine(
        @"OBSERVER INSTALLED: MEDIA SERVICES RESET"
    );
}

#pragma mark - Initial Probe

static void SRInitialProbe(void) {

    AVAudioSession *session = SRSession();

    SRLogLine(@"========================================");
    SRLogLine(@"SANNE REALTIME");
    SRLogLine(@"CAPABILITY PROBE");
    SRLogLine(@"========================================");

    SRLogLine(@"PASSIVE MODE");

    SRLogLine(@"ZERO AUDIO GENERATION");
    SRLogLine(@"ZERO AUDIO PLAYBACK");
    SRLogLine(@"ZERO AVAUDIOENGINE");
    SRLogLine(@"ZERO MICROPHONE TAP");
    SRLogLine(@"ZERO AUDIO SESSION ACTIVATION");
    SRLogLine(@"ZERO TEST VOICE");

    SRLogLine(@"----------------------------------------");

    SRLogLine(
        [NSString stringWithFormat:
            @"PERMISSION: %@",
            SRPermission()]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION AVAILABLE: %@",
            session.isMicrophoneInjectionAvailable
                ? @"YES"
                : @"NO"]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"PREFERRED INJECTION MODE: %@",
            SRInjectionModeName(
                session.preferredMicrophoneInjectionMode
            )]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"CATEGORY: %@",
            SRCategory(session)]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"MODE: %@",
            SRMode(session)]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT AVAILABLE: %@",
            session.isInputAvailable
                ? @"YES"
                : @"NO"]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT CHANNELS: %ld",
            (long)session.inputNumberOfChannels]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"SAMPLE RATE: %.2f",
            session.sampleRate]
    );

    SRLogLine(@"----------------------------------------");

    SRLogLine(
        [NSString stringWithFormat:
            @"FULL INITIAL STATE:\n%@",
            SRSessionReport()]
    );

    SRLogLine(@"========================================");
}

#pragma mark - Ready Popup

static void SRShowReadyPopup(void) {

    AVAudioSession *session = SRSession();

    SRPopup(
        @"SanneRealtime\nCAPABILITY PROBE READY",

        [NSString stringWithFormat:

            @"Permission: %@\n\n"
             "Current injection: %@\n\n"
             "Category: %@\n"
             "Mode: %@\n"
             "Input channels: %ld\n"
             "Sample rate: %.0f\n\n"
             "PASSIVE OBSERVER ACTIVE.\n\n"
             "Waiting for Apple's microphone-injection "
             "capability event.\n\n"
             "No audio generated.",

            SRPermission(),

            session.isMicrophoneInjectionAvailable
                ? @"YES"
                : @"NO",

            SRCategory(session),

            SRMode(session),

            (long)session.inputNumberOfChannels,

            session.sampleRate]
    );
}

#pragma mark - Initialization

__attribute__((constructor))
static void SanneRealtimeInit(void) {

    @autoreleasepool {

        SRLog =
            [NSMutableArray array];

        SRLogLine(
            @"SANNE REALTIME INITIALIZING"
        );

        SRInstallObservers();

        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                SRInitialProbe();

                /*
                 IMPORTANT:
                 We do NOT request permission here.

                 The permission popup has already been handled
                 by the system/Nobanny integration.

                 We only observe the resulting permission state.
                */

                SRShowReadyPopup();
            }
        );
    }
}
