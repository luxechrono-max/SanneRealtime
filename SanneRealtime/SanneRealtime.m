#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

#pragma mark - Global State

static NSMutableArray<NSString *> *SRLog;

static BOOL SRObserversInstalled = NO;
static BOOL SRCapabilityPopupShown = NO;
static BOOL SRPermissionPopupShown = NO;

#pragma mark - Time / Logging

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

#pragma mark - Permission

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

#pragma mark - Audio Session Helpers

static AVAudioSession *SRSession(void) {
    return [AVAudioSession sharedInstance];
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

#pragma mark - Audio Report

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

#pragma mark - Key Window

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

#pragma mark - Permission Request

static void SRRequestInjectionPermission(void) {

    if (@available(iOS 18.2, *)) {

        AVAudioApplication *application =
            [AVAudioApplication sharedInstance];

        AVAudioApplicationMicrophoneInjectionPermission permission =
            application.microphoneInjectionPermission;

        SRLogLine(
            [NSString stringWithFormat:
                @"CURRENT INJECTION PERMISSION: %@",
                SRPermission()]
        );

        if (permission ==
            AVAudioApplicationMicrophoneInjectionPermissionUndetermined) {

            SRLogLine(
                @"REQUESTING MICROPHONE INJECTION PERMISSION"
            );

            [application
                requestMicrophoneInjectionPermissionWithCompletionHandler:
                ^(BOOL granted) {

                    dispatch_async(
                        dispatch_get_main_queue(),
                        ^{

                            SRLogLine(
                                [NSString stringWithFormat:
                                    @"PERMISSION CALLBACK: %@",
                                    granted
                                        ? @"GRANTED"
                                        : @"DENIED"]
                            );

                            SRLogLine(
                                [NSString stringWithFormat:
                                    @"POST-PERMISSION STATE:\n%@",
                                    SRSessionReport()]
                            );

                            if (!SRPermissionPopupShown) {

                                SRPermissionPopupShown = YES;

                                SRPopup(
                                    @"SanneRealtime\nPERMISSION RESULT",

                                    [NSString stringWithFormat:
                                        @"Microphone injection permission:\n\n"
                                         "%@\n\n"
                                         "Injection capability: %@\n\n"
                                         "Category: %@\n"
                                         "Mode: %@\n"
                                         "Input channels: %ld\n\n"
                                         "NO AUDIO WAS GENERATED.",

                                        SRPermission(),

                                        [SRSession()
                                            isMicrophoneInjectionAvailable]
                                            ? @"YES"
                                            : @"NO",

                                        SRCategory(SRSession()),

                                        SRMode(SRSession()),

                                        (long)[SRSession()
                                            inputNumberOfChannels]
                                    ]
                                );
                            }
                        }
                    );
                }
            ];
        }
    }
}

#pragma mark - Capability Change

static void SRHandleInjectionCapabilityChange(
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
            @"NOTIFICATION REPORTED: %@",
            reported
                ? (reported.boolValue ? @"YES" : @"NO")
                : @"<none>"]
    );

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION AVAILABLE: %@",
            available ? @"YES" : @"NO"]
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

        SRLogLine(@"*** REAL INJECTION CAPABILITY DETECTED ***");

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
                        @"AFTER MODE SET:\n%@",
                        SRSessionReport()]
                );

                if (!SRCapabilityPopupShown) {

                    SRCapabilityPopupShown = YES;

                    SRPopup(
                        @"SanneRealtime\nINJECTION AVAILABLE",

                        [NSString stringWithFormat:
                            @"Apple reports microphone injection AVAILABLE.\n\n"
                             "SpokenAudio mode: SUCCESS\n\n"
                             "Permission: %@\n"
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
                         "SpokenAudio mode could not be selected.\n\n"
                         "ERROR:\n%@",

                        SRPermission(),
                        error]
                );
            }
        }

    } else {

        SRLogLine(@"INJECTION CAPABILITY: NO");
    }
}

#pragma mark - Route Change

static void SRHandleRouteChange(
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

static void SRHandleInterruption(
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

static void SRAppDidBecomeActive(
    NSNotification *notification
) {

    AVAudioSession *session = SRSession();

    SRLogLine(@"========================================");
    SRLogLine(@"APPLICATION DID BECOME ACTIVE");

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

static void SRAppWillResignActive(
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

#pragma mark - Audio Session State Notifications

static void SRHandleMediaServicesReset(
    NSNotification *notification
) {

    SRLogLine(@"MEDIA SERVICES RESET");

    SRLogLine(
        [NSString stringWithFormat:
            @"STATE AFTER RESET:\n%@",
            SRSessionReport()]
    );
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
     Apple's documented microphone-injection capability event.
    */

    [center
        addObserverForName:
            AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRHandleInjectionCapabilityChange(
                notification
            );
        }];

    SRLogLine(
        @"INSTALLED: MICROPHONE INJECTION CAPABILITY OBSERVER"
    );

    /*
     Route changes.
    */

    [center
        addObserverForName:
            AVAudioSessionRouteChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRHandleRouteChange(notification);
        }];

    SRLogLine(
        @"INSTALLED: AUDIO ROUTE OBSERVER"
    );

    /*
     Interruptions.
    */

    [center
        addObserverForName:
            AVAudioSessionInterruptionNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRHandleInterruption(notification);
        }];

    SRLogLine(
        @"INSTALLED: AUDIO INTERRUPTION OBSERVER"
    );

    /*
     UIApplication lifecycle notifications.

     We deliberately do NOT use:
       AVAudioSessionDidBecomeActiveNotification
       AVAudioSessionDidBecomeInactiveNotification

     Those symbols are not available in your SDK.
    */

    [center
        addObserverForName:
            UIApplicationDidBecomeActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRAppDidBecomeActive(notification);
        }];

    SRLogLine(
        @"INSTALLED: APPLICATION ACTIVE OBSERVER"
    );

    [center
        addObserverForName:
            UIApplicationWillResignActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRAppWillResignActive(notification);
        }];

    SRLogLine(
        @"INSTALLED: APPLICATION RESIGN-ACTIVE OBSERVER"
    );

    /*
     Media-server reset.
    */

    [center
        addObserverForName:
            AVAudioSessionMediaServicesWereResetNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRHandleMediaServicesReset(notification);
        }];

    SRLogLine(
        @"INSTALLED: MEDIA SERVICES RESET OBSERVER"
    );
}

#pragma mark - Initial Probe

static void SRInitialProbe(void) {

    AVAudioSession *session = SRSession();

    SRLogLine(@"========================================");
    SRLogLine(@"SANNE REALTIME - CAPABILITY PROBE");
    SRLogLine(@"========================================");

    SRLogLine(@"PASSIVE MODE");
    SRLogLine(@"ZERO AUDIO GENERATION");
    SRLogLine(@"ZERO AUDIO PLAYBACK");
    SRLogLine(@"ZERO AVAUDIOENGINE");
    SRLogLine(@"ZERO MICROPHONE TAP");
    SRLogLine(@"ZERO SESSION ACTIVATION");
    SRLogLine(@"ZERO TEST VOICE");

    SRLogLine(@"----------------------------------------");

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION PERMISSION: %@",
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

#pragma mark - Final Popup

static void SRShowReadyPopup(void) {

    AVAudioSession *session = SRSession();

    NSString *permission =
        SRPermission();

    NSString *available =
        session.isMicrophoneInjectionAvailable
            ? @"YES"
            : @"NO";

    NSString *message =
        [NSString stringWithFormat:

            @"Permission: %@\n\n"
             "Current injection: %@\n\n"
             "Category: %@\n"
             "Mode: %@\n"
             "Input channels: %ld\n"
             "Sample rate: %.0f\n\n"
             "The probe is PASSIVE.\n"
             "No test voice.\n"
             "No AVAudioEngine.\n"
             "No microphone tap.\n"
             "No audio generated.\n\n"
             "Waiting for Apple's injection capability event.",

            permission,

            available,

            SRCategory(session),

            SRMode(session),

            (long)session.inputNumberOfChannels,

            session.sampleRate
        ];

    SRPopup(
        @"SanneRealtime\nCAPABILITY PROBE READY",
        message
    );
}

#pragma mark - Constructor

__attribute__((constructor))
static void SanneRealtimeInit(void) {

    @autoreleasepool {

        SRLog =
            [NSMutableArray array];

        SRLogLine(
            @"SANNE REALTIME INITIALIZING"
        );

        /*
         Install observers immediately.

         We do not activate the audio session.
        */

        SRInstallObservers();

        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                SRInitialProbe();

                /*
                 Only request permission if still
                 undetermined.

                 If already granted, nothing is requested.
                */

                if (@available(iOS 18.2, *)) {

                    if ([SRPermission()
                        isEqualToString:@"UNDETERMINED"]) {

                        SRRequestInjectionPermission();

                    } else {

                        SRShowReadyPopup();
                    }

                } else {

                    SRPopup(
                        @"SanneRealtime\nUNSUPPORTED",

                        @"Microphone injection APIs require "
                         "iOS 18.2 or later."
                    );
                }
            }
        );
    }
}
