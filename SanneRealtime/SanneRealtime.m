#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

#pragma mark - Globals

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

        UIViewController *vc = window.rootViewController;

        while (vc.presentedViewController) {
            vc = vc.presentedViewController;
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

#pragma mark - Route Description

static NSString *SRPortDescription(AVAudioSessionPortDescription *port)
{
    if (!port) {
        return @"<none>";
    }

    NSString *name = port.portName ?: @"?";
    NSString *type = port.portType ?: @"?";

    return [NSString stringWithFormat:
        @"%@ (%@)",
        name,
        type];
}

static NSString *SRRouteDescription(AVAudioSessionRouteDescription *route)
{
    if (!route) {
        return @"<no route>";
    }

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
    if (!@available(iOS 18.2, *)) {
        return @"iOS 18.2 or newer required.";
    }

    AVAudioSession *session =
        AVAudioSession.sharedInstance;

    AVAudioSessionRouteDescription *route =
        session.currentRoute;

    AVAudioFormat *inputFormat = nil;

    @try {
        inputFormat = session.inputFormatForBus:0;
    }
    @catch (NSException *exception) {

        NSLog(
            @"[SanneRealtime] inputFormatForBus exception: %@",
            exception
        );
    }

    NSString *formatDescription =
        @"<unavailable>";

    if (inputFormat) {

        formatDescription =
            [NSString stringWithFormat:
                @"%@ Hz / %u ch",
                @(inputFormat.sampleRate),
                inputFormat.channelCount];
    }

    NSString *routeDescription =
        SRRouteDescription(route);

    NSString *message =
        [NSString stringWithFormat:

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

            routeDescription
        ];

    return message;
}

static void SRLogSessionState(NSString *reason)
{
    if (!@available(iOS 18.2, *)) {
        return;
    }

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

#pragma mark - Injection Test

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
    if (!gSynth) {
        gSynth =
            [[AVSpeechSynthesizer alloc] init];
    }

    AVSpeechSynthesisVoice *voice =
        SRFemaleVoice();

    AVSpeechUtterance *utterance =
        [AVSpeechUtterance
            speechUtteranceWithString:
                @"Hello. This is the SanneRealtime female voice test."];

    utterance.voice = voice;
    utterance.rate = 0.48;
    utterance.pitchMultiplier = 1.05;
    utterance.volume = 1.0;

    NSLog(
        @"[SanneRealtime] Speaking female test voice."
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

    NSLog(
        @"[SanneRealtime] Injection permission: %@",
        SRPermissionString()
    );

    if (permission ==
        AVAudioApplicationMicrophoneInjectionPermissionUndetermined) {

        NSLog(
            @"[SanneRealtime] Requesting injection permission."
        );

        [AVAudioApplication
            requestMicrophoneInjectionPermissionWithCompletionHandler:
            ^(AVAudioApplicationMicrophoneInjectionPermission result) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{

                        NSLog(
                            @"[SanneRealtime] Permission callback: %@",
                            SRPermissionString()
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
        @"[SanneRealtime] SpokenAudio injection enabled."
    );

    SRPopup(
        @"INJECTION: READY\n\n"
         "Female test voice will play now."
    );

    /*
     * IMPORTANT:
     *
     * We deliberately do NOT:
     *
     * - activate the audio session
     * - change Discord's category
     * - change Discord's mode
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

#pragma mark - Passive Notifications

static void SRHandleRouteChange(NSNotification *notification)
{
    NSLog(
        @"[SanneRealtime] ROUTE CHANGE notification."
    );

    NSNumber *reason =
        notification.userInfo
            [AVAudioSessionRouteChangeReasonKey];

    if (reason) {

        NSLog(
            @"[SanneRealtime] Route change reason: %@",
            reason
        );
    }

    SRLogSessionState(@"ROUTE CHANGE");
}

static void SRHandleInjectionCapabilityChange(
    NSNotification *notification
)
{
    NSLog(
        @"[SanneRealtime] INJECTION CAPABILITY CHANGE."
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
        notification.userInfo
            [AVAudioSessionInterruptionTypeKey];

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
        @"[SanneRealtime] MEDIA SERVICES RESET."
    );

    SRLogSessionState(
        @"MEDIA SERVICES RESET"
    );
}

#pragma mark - Install Observers

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

                SRHandleInjectionCapabilityChange(
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

            SRHandleMediaServicesReset(notification);
        }];

    NSLog(
        @"[SanneRealtime] Passive audio observers installed."
    );
}

#pragma mark - Initial Diagnostic

static void SRInitialDiagnostic(void)
{
    NSLog(
        @"[SanneRealtime] Performing initial passive diagnostic."
    );

    SRLogSessionState(@"INITIAL");

    /*
     * Preserve the proven injection test.
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
        @"[SanneRealtime] STEP 1 PASSIVE AUDIO DIAGNOSTIC"
    );

    NSLog(
        @"[SanneRealtime] =================================="
    );

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            /*
             * IMPORTANT:
             *
             * Nothing here activates or changes the
             * AVAudioSession.
             */

            SRStartPassiveObservers();

            /*
             * Give Nobanny/Discord some time to establish
             * its initial audio environment.
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
