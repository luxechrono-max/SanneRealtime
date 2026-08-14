#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static AVSpeechSynthesizer *gSynth = nil;

static NSMutableArray<NSString *> *gRuntimeLog = nil;
static BOOL gHasInterestingAudioEvent = NO;
static BOOL gObserversStarted = NO;
static BOOL gShowingDiagnostic = NO;

#pragma mark - Runtime Log

static void SRRecordLog(NSString *message)
{
    if (!gRuntimeLog)
        gRuntimeLog = [NSMutableArray array];

    NSString *time =
        [NSDateFormatter localizedStringFromDate:
            [NSDate date]
            dateStyle:NSDateFormatterNoStyle
            timeStyle:NSDateFormatterMediumStyle];

    NSString *entry =
        [NSString stringWithFormat:
            @"[%@] %@",
            time ?: @"?",
            message ?: @""];

    [gRuntimeLog addObject:entry];

    while (gRuntimeLog.count > 30) {
        [gRuntimeLog removeObjectAtIndex:0];
    }

    NSLog(@"[SanneRealtime] %@", entry);
}

#pragma mark - Popup

static void SRPopup(NSString *message)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;

        if (@available(iOS 13.0, *)) {

            for (UIScene *scene in
                 UIApplication.sharedApplication.connectedScenes) {

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

        UIViewController *controller =
            window.rootViewController;

        while (controller.presentedViewController)
            controller =
                controller.presentedViewController;

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

#pragma mark - Permission

static NSString *SRPermissionString(void)
{
    if (@available(iOS 18.2, *)) {

        AVAudioApplicationMicrophoneInjectionPermission permission =
            AVAudioApplication.sharedInstance
                .microphoneInjectionPermission;

        switch (permission) {

            case AVAudioApplicationMicrophoneInjectionPermissionGranted:
                return @"GRANTED";

            case AVAudioApplicationMicrophoneInjectionPermissionDenied:
                return @"DENIED";

            case AVAudioApplicationMicrophoneInjectionPermissionUndetermined:
                return @"UNDETERMINED";

            case AVAudioApplicationMicrophoneInjectionPermissionServiceDisabled:
                return @"SERVICE DISABLED";
        }
    }

    return @"UNAVAILABLE";
}

#pragma mark - Route Description

static NSString *SRPortDescription(
    AVAudioSessionPortDescription *port
)
{
    if (!port)
        return @"<none>";

    return [NSString stringWithFormat:
        @"%@ (%@)",
        port.portName ?: @"?",
        port.portType ?: @"?"];
}

static NSString *SRRouteDescription(
    AVAudioSessionRouteDescription *route
)
{
    if (!route)
        return @"<no route>";

    NSMutableString *result =
        [NSMutableString string];

    [result appendString:@"INPUTS:\n"];

    if (route.inputs.count == 0) {

        [result appendString:@"  <none>\n"];

    } else {

        for (AVAudioSessionPortDescription *port
             in route.inputs) {

            [result appendFormat:
                @"  %@\n",
                SRPortDescription(port)];
        }
    }

    [result appendString:@"OUTPUTS:\n"];

    if (route.outputs.count == 0) {

        [result appendString:@"  <none>\n"];

    } else {

        for (AVAudioSessionPortDescription *port
             in route.outputs) {

            [result appendFormat:
                @"  %@\n",
                SRPortDescription(port)];
        }
    }

    return result;
}

#pragma mark - Session Diagnostic

static NSString *SRSessionDiagnostic(void)
{
    if (!@available(iOS 18.2, *))
        return @"iOS 18.2 or newer required.";

    AVAudioSession *session =
        AVAudioSession.sharedInstance;

    AVAudioSessionRouteDescription *route =
        session.currentRoute;

    return [NSString stringWithFormat:

        @"CATEGORY: %@\n"
         "MODE: %@\n"
         "INPUT AVAILABLE: %@\n"
         "INPUT CHANNELS: %ld\n"
         "SAMPLE RATE: %.2f\n"
         "INPUT LATENCY: %.6f\n"
         "OUTPUT LATENCY: %.6f\n"
         "INJECTION AVAILABLE: %@\n\n"
         "%@",

        session.category ?: @"?",
        session.mode ?: @"?",

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

        SRRouteDescription(route)
    ];
}

static void SRRecordSessionState(
    NSString *reason
)
{
    NSString *state =
        SRSessionDiagnostic();

    NSString *message =
        [NSString stringWithFormat:
            @"STATE: %@\n%@",
            reason ?: @"UNKNOWN",
            state];

    gHasInterestingAudioEvent = YES;

    SRRecordLog(message);
}

#pragma mark - Runtime Diagnostic Popup

static void SRShowRuntimeDiagnostic(void)
{
    if (gShowingDiagnostic)
        return;

    if (!gRuntimeLog || gRuntimeLog.count == 0)
        return;

    gShowingDiagnostic = YES;

    NSMutableString *report =
        [NSMutableString string];

    [report appendString:
        @"RECENT AUDIO EVENTS\n\n"];

    NSUInteger startIndex = 0;

    if (gRuntimeLog.count > 12) {
        startIndex = gRuntimeLog.count - 12;
    }

    for (NSUInteger i = startIndex;
         i < gRuntimeLog.count;
         i++) {

        [report appendFormat:
            @"%@\n\n",
            gRuntimeLog[i]];
    }

    if (report.length > 7000) {

        NSRange range =
            NSMakeRange(
                report.length - 7000,
                7000
            );

        NSString *tail =
            [report substringWithRange:range];

        report =
            [NSMutableString
                stringWithFormat:
                    @"...LAST EVENTS...\n\n%@",
                    tail];
    }

    [report appendFormat:
        @"\nCURRENT STATE\n\n%@",
        SRSessionDiagnostic()];

    SRPopup(report);

    gShowingDiagnostic = NO;
}

#pragma mark - Known-Good Injection Test

static AVSpeechSynthesisVoice *SRFemaleVoice(void)
{
    if (@available(iOS 13.0, *)) {

        NSArray<AVSpeechSynthesisVoice *> *voices =
            [AVSpeechSynthesisVoice speechVoices];

        for (AVSpeechSynthesisVoice *voice
             in voices) {

            if (voice.gender ==
                    AVSpeechSynthesisVoiceGenderFemale &&
                [voice.language hasPrefix:@"en"]) {

                return voice;
            }
        }
    }

    return [AVSpeechSynthesisVoice
        voiceWithLanguage:@"en-US"];
}

static void SRSpeakTest(void)
{
    if (!gSynth)
        gSynth =
            [[AVSpeechSynthesizer alloc] init];

    AVSpeechUtterance *utterance =
        [AVSpeechUtterance
            speechUtteranceWithString:
                @"Hello. This is the SanneRealtime female voice test."];

    utterance.voice =
        SRFemaleVoice();

    utterance.rate = 0.48;
    utterance.pitchMultiplier = 1.05;
    utterance.volume = 1.0;

    SRRecordLog(
        @"CONTROL TEST: AVSpeechSynthesizer test voice started."
    );

    [gSynth speakUtterance:utterance];
}

static void SREnableInjectionAndTest(void)
{
    if (!@available(iOS 18.2, *)) {

        SRPopup(
            @"iOS 18.2 or newer is required."
        );

        return;
    }

    AVAudioApplication *application =
        AVAudioApplication.sharedInstance;

    AVAudioSession *session =
        AVAudioSession.sharedInstance;

    AVAudioApplicationMicrophoneInjectionPermission permission =
        application.microphoneInjectionPermission;

    SRRecordLog(
        [NSString stringWithFormat:
            @"INJECTION PERMISSION: %@",
            SRPermissionString()]
    );

    if (permission ==
        AVAudioApplicationMicrophoneInjectionPermissionUndetermined) {

        SRRecordLog(
            @"REQUESTING MICROPHONE INJECTION PERMISSION."
        );

        [AVAudioApplication
            requestMicrophoneInjectionPermissionWithCompletionHandler:
            ^(AVAudioApplicationMicrophoneInjectionPermission result) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{

                        SRRecordLog(
                            [NSString stringWithFormat:
                                @"PERMISSION CALLBACK: %@",
                                SRPermissionString()]
                        );

                        if (result ==
                            AVAudioApplicationMicrophoneInjectionPermissionGranted) {

                            SREnableInjectionAndTest();

                        } else {

                            SRPopup(
                                [NSString stringWithFormat:
                                    @"Microphone injection permission: %@",
                                    SRPermissionString()]
                            );
                        }
                    }
                );
            }];

        return;
    }

    if (permission !=
        AVAudioApplicationMicrophoneInjectionPermissionGranted) {

        SRPopup(
            [NSString stringWithFormat:
                @"Injection permission is %@.",
                SRPermissionString()]
        );

        return;
    }

    if (!session.isMicrophoneInjectionAvailable) {

        SRRecordLog(
            @"INJECTION CURRENTLY UNAVAILABLE."
        );

        SRPopup(
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

        SRRecordLog(
            [NSString stringWithFormat:
                @"FAILED TO ENABLE SPOKEN AUDIO: %@",
                error.localizedDescription
                    ?: @"Unknown error"]
        );

        SRPopup(
            [NSString stringWithFormat:
                @"Could not enable SpokenAudio injection.\n\n%@",
                error.localizedDescription
                    ?: @"Unknown error"]
        );

        return;
    }

    SRRecordLog(
        @"SPOKEN AUDIO INJECTION ENABLED."
    );

    SRPopup(
        @"INJECTION: READY\n\n"
         "Female test voice will play now."
    );

    /*
     * CONTROL TEST ONLY.
     *
     * We deliberately do NOT:
     *
     * - activate the audio session
     * - change the audio category
     * - change the audio mode
     * - create AVAudioEngine
     * - install a microphone tap
     * - take ownership of the audio route
     */

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            700 * NSEC_PER_MSEC
        ),
        dispatch_get_main_queue(),
        ^{

            SRSpeakTest();
        }
    );
}

#pragma mark - Route Change

static void SRHandleRouteChange(
    NSNotification *notification
)
{
    gHasInterestingAudioEvent = YES;

    NSNumber *reason =
        notification.userInfo[
            AVAudioSessionRouteChangeReasonKey
        ];

    NSNumber *previousRoute =
        notification.userInfo[
            AVAudioSessionRouteChangePreviousRouteKey
        ];

    NSString *reasonText =
        reason
            ? [reason description]
            : @"unknown";

    NSString *previousText =
        previousRoute
            ? @"previous route available"
            : @"no previous route object";

    SRRecordLog(
        [NSString stringWithFormat:
            @"ROUTE CHANGE\n"
             "REASON: %@\n"
             "%@",
            reasonText,
            previousText]
    );

    SRRecordSessionState(
        @"AFTER ROUTE CHANGE"
    );
}

#pragma mark - Injection Capability Change

static void SRHandleCapabilityChange(
    NSNotification *notification
)
{
    gHasInterestingAudioEvent = YES;

    AVAudioSession *session =
        AVAudioSession.sharedInstance;

    NSNumber *available =
        notification.userInfo[
            AVAudioSessionMicrophoneInjectionIsAvailableKey
        ];

    SRRecordLog(
        [NSString stringWithFormat:
            @"INJECTION CAPABILITY CHANGE\n"
             "NOTIFICATION AVAILABLE: %@\n"
             "SESSION AVAILABLE: %@",
            available
                ? (available.boolValue ? @"YES" : @"NO")
                : @"UNKNOWN",
            session.isMicrophoneInjectionAvailable
                ? @"YES"
                : @"NO"]
    );

    SRRecordSessionState(
        @"AFTER INJECTION CAPABILITY CHANGE"
    );
}

#pragma mark - Interruption

static void SRHandleInterruption(
    NSNotification *notification
)
{
    gHasInterestingAudioEvent = YES;

    NSNumber *type =
        notification.userInfo[
            AVAudioSessionInterruptionTypeKey
        ];

    NSNumber *reason =
        notification.userInfo[
            AVAudioSessionInterruptionReasonKey
        ];

    SRRecordLog(
        [NSString stringWithFormat:
            @"AUDIO INTERRUPTION\n"
             "TYPE: %@\n"
             "REASON: %@",
            type ?: @"unknown",
            reason ?: @"unknown"]
    );

    SRRecordSessionState(
        @"AFTER AUDIO INTERRUPTION"
    );
}

#pragma mark - Media Services Reset

static void SRHandleMediaServicesReset(
    NSNotification *notification
)
{
    gHasInterestingAudioEvent = YES;

    SRRecordLog(
        @"MEDIA SERVICES RESET"
    );

    SRRecordSessionState(
        @"AFTER MEDIA SERVICES RESET"
    );
}

#pragma mark - Audio Session Activation State

static void SRHandleAudioSessionActive(
    NSNotification *notification
)
{
    gHasInterestingAudioEvent = YES;

    SRRecordLog(
        @"AUDIO SESSION DID BECOME ACTIVE"
    );

    SRRecordSessionState(
        @"AUDIO SESSION ACTIVE"
    );
}

static void SRHandleAudioSessionInactive(
    NSNotification *notification
)
{
    gHasInterestingAudioEvent = YES;

    SRRecordLog(
        @"AUDIO SESSION DID BECOME INACTIVE"
    );

    SRRecordSessionState(
        @"AUDIO SESSION INACTIVE"
    );
}

#pragma mark - App Became Active

static void SRHandleApplicationDidBecomeActive(
    NSNotification *notification
)
{
    if (!gObserversStarted)
        return;

    if (!gHasInterestingAudioEvent)
        return;

    /*
     * Give the audio session a moment to settle after
     * returning to Nobanny before displaying the report.
     */
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            800 * NSEC_PER_MSEC
        ),
        dispatch_get_main_queue(),
        ^{

            if (!gHasInterestingAudioEvent)
                return;

            SRRecordSessionState(
                @"RETURNED TO NOBANNY"
            );

            SRShowRuntimeDiagnostic();
        }
    );
}

#pragma mark - Observers

static void SRStartPassiveObservers(void)
{
    if (gObserversStarted)
        return;

    gObserversStarted = YES;

    NSNotificationCenter *center =
        NSNotificationCenter.defaultCenter;

    [center addObserverForName:
                AVAudioSessionRouteChangeNotification
                object:nil
                queue:NSOperationQueue.mainQueue
                usingBlock:
        ^(NSNotification *notification) {

            SRHandleRouteChange(
                notification
            );
        }];

    if (@available(iOS 18.2, *)) {

        [center addObserverForName:
                    AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
                    object:nil
                    queue:NSOperationQueue.mainQueue
                    usingBlock:
            ^(NSNotification *notification) {

                SRHandleCapabilityChange(
                    notification
                );
            }];
    }

    [center addObserverForName:
                AVAudioSessionInterruptionNotification
                object:nil
                queue:NSOperationQueue.mainQueue
                usingBlock:
        ^(NSNotification *notification) {

            SRHandleInterruption(
                notification
            );
        }];

    [center addObserverForName:
                AVAudioSessionMediaServicesWereResetNotification
                object:nil
                queue:NSOperationQueue.mainQueue
                usingBlock:
        ^(NSNotification *notification) {

            SRHandleMediaServicesReset(
                notification
            );
        }];

    [center addObserverForName:
                AVAudioSessionDidBecomeActiveNotification
                object:nil
                queue:NSOperationQueue.mainQueue
                usingBlock:
        ^(NSNotification *notification) {

            SRHandleAudioSessionActive(
                notification
            );
        }];

    [center addObserverForName:
                AVAudioSessionDidBecomeInactiveNotification
                object:nil
                queue:NSOperationQueue.mainQueue
                usingBlock:
        ^(NSNotification *notification) {

            SRHandleAudioSessionInactive(
                notification
            );
        }];

    [center addObserverForName:
                UIApplicationDidBecomeActiveNotification
                object:nil
                queue:NSOperationQueue.mainQueue
                usingBlock:
        ^(NSNotification *notification) {

            SRHandleApplicationDidBecomeActive(
                notification
            );
        }];

    SRRecordLog(
        @"PASSIVE AUDIO OBSERVERS INSTALLED."
    );
}

#pragma mark - Initial Diagnostic

static void SRInitialDiagnostic(void)
{
    SRRecordSessionState(
        @"INITIAL"
    );

    SREnableInjectionAndTest();
}

#pragma mark - Constructor

__attribute__((constructor))
static void SanneRealtimeLoaded(void)
{
    gRuntimeLog =
        [NSMutableArray array];

    SRRecordLog(
        @"=========================================="
    );

    SRRecordLog(
        @"SANNE REALTIME - IPHONE DIAGNOSTIC BUILD"
    );

    SRRecordLog(
        @"PASSIVE AUDIO SESSION OBSERVATION ONLY"
    );

    SRRecordLog(
        @"=========================================="
    );

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            SRStartPassiveObservers();

            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    1200 * NSEC_PER_MSEC
                ),
                dispatch_get_main_queue(),
                ^{

                    SRInitialDiagnostic();
                }
            );
        }
    );
}
