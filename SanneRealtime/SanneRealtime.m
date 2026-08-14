#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static AVSpeechSynthesizer *gSynth = nil;

static BOOL gObserversStarted = NO;
static BOOL gInjectionEnabledForCurrentCall = NO;
static BOOL gTestVoiceStartedForCurrentCall = NO;
static BOOL gWaitingForUsableAudio = NO;
static BOOL gCheckScheduled = NO;

static NSInteger gCallGeneration = 0;

static NSMutableArray<NSString *> *gRuntimeLog = nil;

#pragma mark - Logging

static void SRRecordLog(NSString *message)
{
    if (!gRuntimeLog)
        gRuntimeLog = [NSMutableArray array];

    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.dateFormat = @"HH:mm:ss.SSS";

    NSString *time =
        [formatter stringFromDate:[NSDate date]];

    NSString *entry =
        [NSString stringWithFormat:
            @"[%@] %@",
            time ?: @"?",
            message ?: @""];

    [gRuntimeLog addObject:entry];

    while (gRuntimeLog.count > 60) {
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
            AVAudioApplication.sharedInstance.microphoneInjectionPermission;

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

#pragma mark - Route

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

#pragma mark - Audio State

static BOOL SRIsDiscordVoiceStateReady(void)
{
    if (!@available(iOS 18.2, *))
        return NO;

    AVAudioSession *session =
        AVAudioSession.sharedInstance;

    NSString *category =
        session.category ?: @"";

    NSString *mode =
        session.mode ?: @"";

    BOOL categoryReady =
        [category isEqualToString:
            AVAudioSessionCategoryPlayAndRecord];

    BOOL modeReady =
        [mode isEqualToString:
            AVAudioSessionModeVoiceChat];

    BOOL inputReady =
        session.isInputAvailable &&
        session.inputNumberOfChannels > 0;

    BOOL injectionReady =
        session.isMicrophoneInjectionAvailable;

    return
        categoryReady &&
        modeReady &&
        inputReady &&
        injectionReady;
}

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
         "INJECTION AVAILABLE: %@\n"
         "READY FOR DISCORD VOICE: %@\n\n"
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

        SRIsDiscordVoiceStateReady()
            ? @"YES"
            : @"NO",

        SRRouteDescription(route)
    ];
}

#pragma mark - Female Test Voice

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

static void SRSpeakKnownGoodTest(void)
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
        @"CONTROL TEST: AVSpeechSynthesizer STARTED."
    );

    [gSynth speakUtterance:utterance];
}

#pragma mark - Enable SpokenAudio

static BOOL SREnableSpokenAudio(void)
{
    if (!@available(iOS 18.2, *))
        return NO;

    AVAudioSession *session =
        AVAudioSession.sharedInstance;

    if (!SRIsDiscordVoiceStateReady()) {

        SRRecordLog(
            @"ENABLE SKIPPED: Discord voice state is not ready."
        );

        return NO;
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
                @"SPOKEN AUDIO ENABLE FAILED: %@",
                error.localizedDescription
                    ?: @"Unknown error"]
        );

        return NO;
    }

    gInjectionEnabledForCurrentCall = YES;

    SRRecordLog(
        @"SPOKEN AUDIO INJECTION ENABLED FOR CURRENT CALL."
    );

    SRRecordLog(
        [NSString stringWithFormat:
            @"STATE AFTER ENABLE:\n%@",
            SRSessionDiagnostic()]
    );

    return YES;
}

#pragma mark - Wait For Usable State

static void SRCheckAudioState(void);

static void SRScheduleAudioCheck(
    NSString *reason
)
{
    if (gCheckScheduled)
        return;

    gCheckScheduled = YES;

    SRRecordLog(
        [NSString stringWithFormat:
            @"AUDIO CHECK SCHEDULED: %@",
            reason ?: @"unknown"]
    );

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            300 * NSEC_PER_MSEC
        ),
        dispatch_get_main_queue(),
        ^{

            gCheckScheduled = NO;

            SRCheckAudioState();
        }
    );
}

static void SRStartTestAfterReady(void)
{
    if (gTestVoiceStartedForCurrentCall)
        return;

    if (!SRIsDiscordVoiceStateReady())
        return;

    if (!gInjectionEnabledForCurrentCall) {

        if (!SREnableSpokenAudio())
            return;
    }

    gTestVoiceStartedForCurrentCall = YES;

    SRRecordLog(
        @"DISCORD VOICE STATE READY."
    );

    SRRecordLog(
        @"WAITING 500 MS BEFORE CONTROL TEST."
    );

    SRPopup(
        @"DISCORD AUDIO READY\n\n"
         "SpokenAudio injection enabled.\n\n"
         "Starting known-good female test voice."
    );

    NSInteger generation =
        gCallGeneration;

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            500 * NSEC_PER_MSEC
        ),
        dispatch_get_main_queue(),
        ^{

            if (generation != gCallGeneration) {

                SRRecordLog(
                    @"TEST CANCELLED: CALL GENERATION CHANGED."
                );

                return;
            }

            if (!SRIsDiscordVoiceStateReady()) {

                SRRecordLog(
                    @"TEST CANCELLED: AUDIO STATE NO LONGER READY."
                );

                gTestVoiceStartedForCurrentCall = NO;

                SRScheduleAudioCheck(
                    @"STATE LOST BEFORE TEST"
                );

                return;
            }

            SRSpeakKnownGoodTest();
        }
    );
}

static void SRCheckAudioState(void)
{
    if (!@available(iOS 18.2, *))
        return;

    AVAudioSession *session =
        AVAudioSession.sharedInstance;

    NSString *category =
        session.category ?: @"";

    NSString *mode =
        session.mode ?: @"";

    BOOL categoryReady =
        [category isEqualToString:
            AVAudioSessionCategoryPlayAndRecord];

    BOOL modeReady =
        [mode isEqualToString:
            AVAudioSessionModeVoiceChat];

    BOOL inputReady =
        session.isInputAvailable &&
        session.inputNumberOfChannels > 0;

    BOOL injectionReady =
        session.isMicrophoneInjectionAvailable;

    SRRecordLog(
        [NSString stringWithFormat:
            @"AUDIO CHECK\n"
             "CATEGORY READY: %@\n"
             "MODE READY: %@\n"
             "INPUT READY: %@\n"
             "INJECTION READY: %@",

            categoryReady ? @"YES" : @"NO",
            modeReady ? @"YES" : @"NO",
            inputReady ? @"YES" : @"NO",
            injectionReady ? @"YES" : @"NO"]
    );

    if (categoryReady &&
        modeReady &&
        inputReady &&
        injectionReady) {

        gWaitingForUsableAudio = NO;

        SRStartTestAfterReady();

        return;
    }

    gWaitingForUsableAudio = YES;

    SRRecordLog(
        [NSString stringWithFormat:
            @"WAITING FOR USABLE DISCORD AUDIO.\n%@",
            SRSessionDiagnostic()]
    );
}

#pragma mark - Route Changes

static void SRHandleRouteChange(
    NSNotification *notification
)
{
    NSNumber *reason =
        notification.userInfo[
            AVAudioSessionRouteChangeReasonKey
        ];

    SRRecordLog(
        [NSString stringWithFormat:
            @"ROUTE CHANGE: %@",
            reason ?: @"unknown"]
    );

    SRRecordLog(
        [NSString stringWithFormat:
            @"STATE AFTER ROUTE CHANGE:\n%@",
            SRSessionDiagnostic()]
    );

    /*
     * A route change may temporarily produce zero
     * input channels. Do not touch the session during
     * that transient state.
     */

    if (!SRIsDiscordVoiceStateReady()) {

        gInjectionEnabledForCurrentCall = NO;
        gTestVoiceStartedForCurrentCall = NO;

        SRScheduleAudioCheck(
            @"ROUTE CHANGE"
        );

        return;
    }

    /*
     * If Discord has now established its real
     * PlayAndRecord / VoiceChat route, restore the
     * preferred injection mode without activating
     * or reconfiguring the session ourselves.
     */

    gInjectionEnabledForCurrentCall = NO;
    gTestVoiceStartedForCurrentCall = NO;

    SRScheduleAudioCheck(
        @"ROUTE NOW USABLE"
    );
}

#pragma mark - Injection Capability

static void SRHandleCapabilityChange(
    NSNotification *notification
)
{
    AVAudioSession *session =
        AVAudioSession.sharedInstance;

    NSNumber *available =
        notification.userInfo[
            AVAudioSessionMicrophoneInjectionIsAvailableKey
        ];

    SRRecordLog(
        [NSString stringWithFormat:
            @"INJECTION CAPABILITY CHANGE\n"
             "NOTIFICATION: %@\n"
             "SESSION: %@",

            available
                ? (available.boolValue
                    ? @"YES"
                    : @"NO")
                : @"UNKNOWN",

            session.isMicrophoneInjectionAvailable
                ? @"YES"
                : @"NO"]
    );

    SRRecordLog(
        [NSString stringWithFormat:
            @"STATE AFTER CAPABILITY CHANGE:\n%@",
            SRSessionDiagnostic()]
    );

    if (session.isMicrophoneInjectionAvailable) {

        SRScheduleAudioCheck(
            @"INJECTION BECAME AVAILABLE"
        );

    } else {

        gInjectionEnabledForCurrentCall = NO;

        SRRecordLog(
            @"INJECTION LOST."
        );
    }
}

#pragma mark - Interruption

static void SRHandleInterruption(
    NSNotification *notification
)
{
    NSNumber *type =
        notification.userInfo[
            AVAudioSessionInterruptionTypeKey
        ];

    SRRecordLog(
        [NSString stringWithFormat:
            @"AUDIO INTERRUPTION: %@",
            type ?: @"unknown"]
    );

    SRRecordLog(
        [NSString stringWithFormat:
            @"STATE AFTER INTERRUPTION:\n%@",
            SRSessionDiagnostic()]
    );

    gInjectionEnabledForCurrentCall = NO;
    gTestVoiceStartedForCurrentCall = NO;

    SRScheduleAudioCheck(
        @"AUDIO INTERRUPTION"
    );
}

#pragma mark - Media Services

static void SRHandleMediaServicesReset(
    NSNotification *notification
)
{
    SRRecordLog(
        @"MEDIA SERVICES RESET."
    );

    SRRecordLog(
        [NSString stringWithFormat:
            @"STATE AFTER MEDIA RESET:\n%@",
            SRSessionDiagnostic()]
    );

    gInjectionEnabledForCurrentCall = NO;
    gTestVoiceStartedForCurrentCall = NO;

    SRScheduleAudioCheck(
        @"MEDIA SERVICES RESET"
    );
}

#pragma mark - Application Active

static void SRHandleApplicationDidBecomeActive(
    NSNotification *notification
)
{
    SRRecordLog(
        @"NOBANNY BECAME ACTIVE."
    );

    SRRecordLog(
        [NSString stringWithFormat:
            @"CURRENT STATE:\n%@",
            SRSessionDiagnostic()]
    );

    /*
     * Do not immediately activate/configure anything.
     * Just inspect the state.
     */

    SRScheduleAudioCheck(
        @"NOBANNY BECAME ACTIVE"
    );
}

#pragma mark - Observers

static void SRStartObservers(void)
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

#pragma mark - Initial Startup

static void SRStartup(void)
{
    if (!@available(iOS 18.2, *)) {

        SRPopup(
            @"iOS 18.2 or newer is required."
        );

        return;
    }

    AVAudioApplication *application =
        AVAudioApplication.sharedInstance;

    AVAudioApplicationMicrophoneInjectionPermission permission =
        application.microphoneInjectionPermission;

    SRRecordLog(
        [NSString stringWithFormat:
            @"STARTUP PERMISSION: %@",
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

                            SRScheduleAudioCheck(
                                @"PERMISSION GRANTED"
                            );

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

    SRScheduleAudioCheck(
        @"STARTUP"
    );
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
        @"SANNE REALTIME - CALL STABILIZATION BUILD"
    );

    SRRecordLog(
        @"NO AUDIO SESSION ACTIVATION"
    );

    SRRecordLog(
        @"NO AUDIO ENGINE"
    );

    SRRecordLog(
        @"NO MICROPHONE TAP"
    );

    SRRecordLog(
        @"=========================================="
    );

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            SRStartObservers();

            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    1000 * NSEC_PER_MSEC
                ),
                dispatch_get_main_queue(),
                ^{

                    SRStartup();
                }
            );
        }
    );
}
