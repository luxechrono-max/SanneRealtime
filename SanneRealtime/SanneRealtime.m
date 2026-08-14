#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static AVSpeechSynthesizer *gSynth = nil;

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

#pragma mark - Permission

static NSString *SRPermissionString(void)
{
    if (@available(iOS 18.2, *)) {

        AVAudioApplicationMicrophoneInjectionPermission p =
            AVAudioApplication.sharedInstance
                .microphoneInjectionPermission;

        switch (p) {

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

#pragma mark - Route Diagnostics

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

    AVAudioFormat *inputFormat = nil;

    @try {

        inputFormat =
            [session inputFormatForBus:0];

    }
    @catch (NSException *exception) {

        NSLog(
            @"[SanneRealtime] inputFormat exception: %@",
            exception
        );
    }

    NSString *formatDescription =
        @"<unavailable>";

    if (inputFormat) {

        formatDescription =
            [NSString stringWithFormat:
                @"%.2f Hz / %u ch",
                inputFormat.sampleRate,
                inputFormat.channelCount];
    }

    return [NSString stringWithFormat:

        @"CATEGORY: %@\n"
         "MODE: %@\n"
         "INPUT AVAILABLE: %@\n"
         "INPUT CHANNELS: %ld\n"
         "SAMPLE RATE: %.2f\n"
         "INPUT FORMAT: %@\n"
         "INJECTION AVAILABLE: %@\n\n"
         "%@",

        session.category ?: @"?",
        session.mode ?: @"?",

        session.isInputAvailable
            ? @"YES"
            : @"NO",

        (long)session.inputNumberOfChannels,

        session.sampleRate,

        formatDescription,

        session.isMicrophoneInjectionAvailable
            ? @"YES"
            : @"NO",

        SRRouteDescription(route)
    ];
}

static void SRLogSessionState(NSString *reason)
{
    NSString *diagnostic =
        SRSessionDiagnostic();

    NSLog(
        @"\n"
         "[SanneRealtime] ==============================\n"
         "[SanneRealtime] AUDIO SESSION STATE\n"
         "[SanneRealtime] REASON: %@\n"
         "[SanneRealtime] ==============================\n"
         "%@\n"
         "[SanneRealtime] ==============================",
        reason,
        diagnostic
    );
}

#pragma mark - Known-Good Injection Test

static AVSpeechSynthesisVoice *SRFemaleVoice(void)
{
    if (@available(iOS 13.0, *)) {

        NSArray<AVSpeechSynthesisVoice *> *voices =
            [AVSpeechSynthesisVoice speechVoices];

        for (AVSpeechSynthesisVoice *voice in voices) {

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

    NSLog(
        @"[SanneRealtime] Speaking known-good test voice."
    );

    [gSynth speakUtterance:utterance];
}

static void SREnableInjectionAndTest(void)
{
    if (!@available(iOS 18.2, *)) {

        SRPopup(@"iOS 18.2 or newer is required.");
        return;
    }

    AVAudioApplication *application =
        AVAudioApplication.sharedInstance;

    AVAudioSession *session =
        AVAudioSession.sharedInstance;

    AVAudioApplicationMicrophoneInjectionPermission permission =
        application.microphoneInjectionPermission;

    NSLog(
        @"[SanneRealtime] Permission: %@",
        SRPermissionString()
    );

    if (permission ==
        AVAudioApplicationMicrophoneInjectionPermissionUndetermined) {

        [AVAudioApplication
            requestMicrophoneInjectionPermissionWithCompletionHandler:
            ^(AVAudioApplicationMicrophoneInjectionPermission result) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{

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

        SRPopup(
            [NSString stringWithFormat:
                @"Could not enable SpokenAudio injection.\n\n%@",
                error.localizedDescription
                    ?: @"Unknown error"]
        );

        return;
    }

    NSLog(
        @"[SanneRealtime] SpokenAudio injection ENABLED."
    );

    SRPopup(
        @"INJECTION: READY\n\n"
         "Female test voice will play now."
    );

    /*
     * DO NOT:
     *
     * - activate the session
     * - change the category
     * - change the mode
     * - create AVAudioEngine
     * - install a microphone tap
     * - take ownership of Discord's route
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

#pragma mark - Passive Notifications

static void SRHandleRouteChange(
    NSNotification *notification
)
{
    NSLog(
        @"[SanneRealtime] ROUTE CHANGE"
    );

    NSNumber *reason =
        notification.userInfo[
            AVAudioSessionRouteChangeReasonKey
        ];

    NSLog(
        @"[SanneRealtime] Route change reason: %@",
        reason ?: @"unknown"
    );

    SRLogSessionState(
        @"ROUTE CHANGE"
    );
}

static void SRHandleCapabilityChange(
    NSNotification *notification
)
{
    NSLog(
        @"[SanneRealtime] INJECTION CAPABILITY CHANGE"
    );

    SRLogSessionState(
        @"INJECTION CAPABILITY CHANGE"
    );
}

static void SRHandleInterruption(
    NSNotification *notification
)
{
    NSNumber *type =
        notification.userInfo[
            AVAudioSessionInterruptionTypeKey
        ];

    NSLog(
        @"[SanneRealtime] AUDIO INTERRUPTION: %@",
        type ?: @"unknown"
    );

    SRLogSessionState(
        @"AUDIO INTERRUPTION"
    );
}

static void SRHandleMediaServicesReset(
    NSNotification *notification
)
{
    NSLog(
        @"[SanneRealtime] MEDIA SERVICES RESET"
    );

    SRLogSessionState(
        @"MEDIA SERVICES RESET"
    );
}

#pragma mark - Observers

static void SRStartPassiveObservers(void)
{
    NSNotificationCenter *center =
        NSNotificationCenter.defaultCenter;

    [center addObserverForName:
                AVAudioSessionRouteChangeNotification
                object:nil
                queue:NSOperationQueue.mainQueue
                usingBlock:
        ^(NSNotification *notification) {

            SRHandleRouteChange(notification);
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

            SRHandleInterruption(notification);
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

    NSLog(
        @"[SanneRealtime] Passive observers installed."
    );
}

#pragma mark - Initial Diagnostic

static void SRInitialDiagnostic(void)
{
    NSLog(
        @"[SanneRealtime] Initial diagnostic."
    );

    SRLogSessionState(
        @"INITIAL"
    );

    /*
     * Preserve the proven injection path
     * as our control test.
     */
    SREnableInjectionAndTest();
}

#pragma mark - Constructor

__attribute__((constructor))
static void SanneRealtimeLoaded(void)
{
    NSLog(
        @"[SanneRealtime] =================================="
    );

    NSLog(
        @"[SanneRealtime] STEP 1 - PASSIVE AUDIO DIAGNOSTIC"
    );

    NSLog(
        @"[SanneRealtime] =================================="
    );

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            SRStartPassiveObservers();

            /*
             * Give Nobanny/Discord time to initialize.
             */
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
