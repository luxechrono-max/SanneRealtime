#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static AVSpeechSynthesizer *gSynth = nil;
static AVAudioEngine *gEngine = nil;

static BOOL gCaptureRunning = NO;
static BOOL gTestStarted = NO;

static uint64_t gCapturedFrames = 0;
static uint64_t gCallbackCount = 0;

static float gPeak = 0.0f;
static float gRMS = 0.0f;

static UIWindow *SRKeyWindow(void)
{
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        if (windowScene.activationState !=
            UISceneActivationStateForegroundActive) {
            continue;
        }

        for (UIWindow *window in windowScene.windows) {

            if (window.isKeyWindow) {
                return window;
            }
        }
    }

    return nil;
}

static void SRPopup(NSString *message)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window = SRKeyWindow();

        if (!window) {
            NSLog(@"[SanneRealtime] %@", message);
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

        [controller
            presentViewController:alert
            animated:YES
            completion:nil];
    });
}

static NSString *SRPermissionString(void)
{
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
                return @"SERVICE DISABLED";
        }
    }

    return @"UNAVAILABLE";
}

static AVSpeechSynthesisVoice *SRFemaleVoice(void)
{
    NSArray<AVSpeechSynthesisVoice *> *voices =
        [AVSpeechSynthesisVoice speechVoices];

    for (AVSpeechSynthesisVoice *voice in voices) {

        if (voice.gender ==
            AVSpeechSynthesisVoiceGenderFemale) {

            if ([voice.language hasPrefix:@"en"]) {
                return voice;
            }
        }
    }

    return
        [AVSpeechSynthesisVoice
            voiceWithLanguage:@"en-US"];
}

static void SRSpeakKnownGoodTest(void)
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
                @"SanneRealtime live microphone capture test."];

    utterance.voice =
        voice;

    utterance.rate =
        0.48;

    utterance.pitchMultiplier =
        1.05;

    utterance.volume =
        1.0;

    NSLog(
        @"[SanneRealtime] SPEAKING KNOWN-GOOD TEST");

    [gSynth speakUtterance:utterance];
}

static NSString *SRRouteDescription(void)
{
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    AVAudioSessionRouteDescription *route =
        session.currentRoute;

    NSMutableArray *inputs =
        [NSMutableArray array];

    NSMutableArray *outputs =
        [NSMutableArray array];

    for (AVAudioSessionPortDescription *port
         in route.inputs) {

        [inputs addObject:
            [NSString stringWithFormat:
                @"%@/%@",
                port.portName ?: @"?",
                port.portType ?: @"?"]];
    }

    for (AVAudioSessionPortDescription *port
         in route.outputs) {

        [outputs addObject:
            [NSString stringWithFormat:
                @"%@/%@",
                port.portName ?: @"?",
                port.portType ?: @"?"]];
    }

    NSString *input =
        inputs.count
        ? [inputs componentsJoinedByString:@","]
        : @"NONE";

    NSString *output =
        outputs.count
        ? [outputs componentsJoinedByString:@","]
        : @"NONE";

    return
        [NSString stringWithFormat:
            @"IN:%@ OUT:%@",
            input,
            output];
}

static NSString *SRSessionReport(void)
{
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    BOOL injection =
        NO;

    if (@available(iOS 18.2, *)) {
        injection =
            session.isMicrophoneInjectionAvailable;
    }

    return
        [NSString stringWithFormat:
            @"PERMISSION: %@\n"
             "INJECTION: %@\n"
             "CATEGORY: %@\n"
             "MODE: %@\n"
             "INPUT AVAILABLE: %@\n"
             "INPUT CHANNELS: %ld\n"
             "SAMPLE RATE: %.0f\n"
             "ROUTE: %@",
            SRPermissionString(),
            injection ? @"YES" : @"NO",
            session.category ?: @"NONE",
            session.mode ?: @"NONE",
            session.isInputAvailable
                ? @"YES"
                : @"NO",
            (long)session.inputNumberOfChannels,
            session.sampleRate,
            SRRouteDescription()];
}

static void SRResetCaptureStats(void)
{
    gCapturedFrames = 0;
    gCallbackCount = 0;
    gPeak = 0.0f;
    gRMS = 0.0f;
}

static void SRProcessBuffer(AVAudioPCMBuffer *buffer)
{
    if (!buffer) {
        return;
    }

    AVAudioFrameCount frames =
        buffer.frameLength;

    if (frames == 0) {
        return;
    }

    gCapturedFrames +=
        frames;

    gCallbackCount++;

    AVAudioChannelCount channels =
        buffer.format.channelCount;

    if (channels == 0) {
        return;
    }

    float localPeak =
        0.0f;

    double sumSquares =
        0.0;

    if (buffer.floatChannelData) {

        for (AVAudioChannelCount channel = 0;
             channel < channels;
             channel++) {

            float *data =
                buffer.floatChannelData[channel];

            if (!data) {
                continue;
            }

            for (AVAudioFrameCount frame = 0;
                 frame < frames;
                 frame++) {

                float value =
                    data[frame];

                float absolute =
                    fabsf(value);

                if (absolute > localPeak) {
                    localPeak =
                        absolute;
                }

                sumSquares +=
                    (double)value *
                    (double)value;
            }
        }

        double sampleCount =
            (double)frames *
            (double)channels;

        if (sampleCount > 0.0) {

            gRMS =
                (float)sqrt(
                    sumSquares /
                    sampleCount);
        }

        if (localPeak > gPeak) {
            gPeak =
                localPeak;
        }
    }
}

static void SRStartCapture(void)
{
    if (gCaptureRunning) {
        NSLog(
            @"[SanneRealtime] CAPTURE ALREADY RUNNING");
        return;
    }

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    NSLog(
        @"[SanneRealtime] =======================");

    NSLog(
        @"[SanneRealtime] START CAPTURE REQUEST");

    NSLog(
        @"[SanneRealtime] %@",
        SRSessionReport());

    if (!session.isInputAvailable) {

        SRPopup(
            @"INPUT IS NOT AVAILABLE.\n\n"
             "Make sure the Nobanny Discord call is "
             "already connected before starting capture.");

        return;
    }

    if (session.inputNumberOfChannels <= 0) {

        SRPopup(
            @"INPUT CHANNELS = 0.\n\n"
             "The Discord call has not exposed a usable "
             "microphone input yet.");

        return;
    }

    gEngine =
        [[AVAudioEngine alloc] init];

    AVAudioInputNode *inputNode =
        gEngine.inputNode;

    if (!inputNode) {

        gEngine =
            nil;

        SRPopup(
            @"Could not obtain AVAudioEngine input node.");

        return;
    }

    AVAudioFormat *format =
        [inputNode inputFormatForBus:0];

    if (!format) {

        gEngine =
            nil;

        SRPopup(
            @"Could not obtain microphone format.");

        return;
    }

    NSLog(
        @"[SanneRealtime] INPUT FORMAT: %@",
        format);

    if (format.channelCount == 0 ||
        format.sampleRate <= 0.0) {

        gEngine =
            nil;

        SRPopup(
            [NSString stringWithFormat:
                @"INVALID INPUT FORMAT.\n\n"
                 "Channels: %u\n"
                 "Sample rate: %.0f",
                (unsigned)format.channelCount,
                format.sampleRate]);

        return;
    }

    SRResetCaptureStats();

    [inputNode
        installTapOnBus:0
        bufferSize:1024
        format:format
        block:^(AVAudioPCMBuffer *buffer,
                AVAudioTime *when) {

            (void)when;

            SRProcessBuffer(buffer);
        }];

    /*
     AVAudioEngine prepare returns void.
     It does not return BOOL.
    */

    [gEngine prepare];

    NSError *engineError =
        nil;

    BOOL started =
        [gEngine
            startAndReturnError:&engineError];

    if (!started) {

        [inputNode
            removeTapOnBus:0];

        NSString *errorText =
            engineError.localizedDescription
            ?: @"Unknown AVAudioEngine error.";

        gEngine =
            nil;

        SRPopup(
            [NSString stringWithFormat:
                @"REALTIME CAPTURE FAILED.\n\n%@",
                errorText]);

        NSLog(
            @"[SanneRealtime] ENGINE START FAILED: %@",
            engineError);

        return;
    }

    gCaptureRunning =
        YES;

    NSLog(
        @"[SanneRealtime] LIVE PCM CAPTURE STARTED");

    SRPopup(
        [NSString stringWithFormat:
            @"LIVE CAPTURE STARTED\n\n"
             "Input channels: %u\n"
             "Sample rate: %.0f\n\n"
             "The tap is only measuring live PCM.\n"
             "No voice conversion yet.\n\n"
             "The known-good female test will "
             "play in 2 seconds.",
            (unsigned)format.channelCount,
            format.sampleRate]);

    if (!gTestStarted) {

        gTestStarted =
            YES;

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                2 * NSEC_PER_SEC),
            dispatch_get_main_queue(),
            ^{

                SRSpeakKnownGoodTest();
            });
    }

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            8 * NSEC_PER_SEC),
        dispatch_get_main_queue(),
        ^{

            if (!gCaptureRunning) {
                return;
            }

            AVAudioSession *currentSession =
                [AVAudioSession sharedInstance];

            double duration =
                currentSession.sampleRate > 0.0
                ? (double)gCapturedFrames /
                    currentSession.sampleRate
                : 0.0;

            SRPopup(
                [NSString stringWithFormat:
                    @"LIVE PCM RESULT\n\n"
                     "Callbacks: %llu\n"
                     "Frames: %llu\n"
                     "Captured seconds: %.2f\n"
                     "Peak: %.4f\n"
                     "RMS: %.4f\n\n"
                     "Call is still being observed.\n"
                     "No neural conversion yet.",
                    gCallbackCount,
                    gCapturedFrames,
                    duration,
                    gPeak,
                    gRMS]);
        });
}

static void SREnableKnownGoodInjection(void)
{
    if (!@available(iOS 18.2, *)) {

        SRPopup(
            @"iOS 18.2 or newer is required.");

        return;
    }

    AVAudioApplication *application =
        [AVAudioApplication sharedInstance];

    AVAudioApplicationMicrophoneInjectionPermission permission =
        application.microphoneInjectionPermission;

    if (permission !=
        AVAudioApplicationMicrophoneInjectionPermissionGranted) {

        SRPopup(
            [NSString stringWithFormat:
                @"Injection permission is %@.\n\n"
                 "The known-good injection path "
                 "cannot be started.",
                SRPermissionString()]);

        return;
    }

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    if (!session.isMicrophoneInjectionAvailable) {

        SRPopup(
            @"INJECTION IS CURRENTLY UNAVAILABLE.\n\n"
             "Start the Nobanny Discord call first.");

        return;
    }

    NSError *error =
        nil;

    BOOL success =
        [session
            setPreferredMicrophoneInjectionMode:
                AVAudioSessionMicrophoneInjectionModeSpokenAudio
            error:&error];

    if (!success) {

        SRPopup(
            [NSString stringWithFormat:
                @"SPOKEN AUDIO MODE FAILED.\n\n%@",
                error.localizedDescription
                    ?: @"Unknown error."]);

        return;
    }

    NSLog(
        @"[SanneRealtime] SPOKEN AUDIO MODE ENABLED");

    SRStartCapture();
}

static void SRCapabilityChanged(
    NSNotification *notification)
{
    (void)notification;

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    NSLog(
        @"[SanneRealtime] INJECTION CAPABILITY CHANGED");

    NSLog(
        @"[SanneRealtime] %@",
        SRSessionReport());

    if (@available(iOS 18.2, *)) {

        if (session.isMicrophoneInjectionAvailable &&
            session.isInputAvailable &&
            session.inputNumberOfChannels > 0) {

            if (!gCaptureRunning) {
                SREnableKnownGoodInjection();
            }
        }
    }
}

static void SRRouteChanged(
    NSNotification *notification)
{
    (void)notification;

    NSLog(
        @"[SanneRealtime] ROUTE CHANGED");

    NSLog(
        @"[SanneRealtime] %@",
        SRSessionReport());

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    if (!gCaptureRunning &&
        session.isInputAvailable &&
        session.inputNumberOfChannels > 0 &&
        session.isMicrophoneInjectionAvailable) {

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                500 * NSEC_PER_MSEC),
            dispatch_get_main_queue(),
            ^{

                SREnableKnownGoodInjection();
            });
    }
}

static void SRInterruption(
    NSNotification *notification)
{
    NSNumber *typeNumber =
        notification.userInfo[
            AVAudioSessionInterruptionTypeKey];

    if (typeNumber &&
        typeNumber.unsignedIntegerValue ==
            AVAudioSessionInterruptionTypeBegan) {

        NSLog(
            @"[SanneRealtime] AUDIO INTERRUPTION BEGAN");

    } else {

        NSLog(
            @"[SanneRealtime] AUDIO INTERRUPTION ENDED");
    }

    NSLog(
        @"[SanneRealtime] %@",
        SRSessionReport());
}

static void SRApplicationActive(
    NSNotification *notification)
{
    (void)notification;

    NSLog(
        @"[SanneRealtime] APPLICATION ACTIVE");

    NSLog(
        @"[SanneRealtime] %@",
        SRSessionReport());
}

static void SRApplicationInactive(
    NSNotification *notification)
{
    (void)notification;

    NSLog(
        @"[SanneRealtime] APPLICATION INACTIVE");

    NSLog(
        @"[SanneRealtime] %@",
        SRSessionReport());
}

static void SRInstallObservers(void)
{
    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    [center
        addObserverForName:
            AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRCapabilityChanged(notification);
        }];

    [center
        addObserverForName:
            AVAudioSessionRouteChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRRouteChanged(notification);
        }];

    [center
        addObserverForName:
            AVAudioSessionInterruptionNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRInterruption(notification);
        }];

    [center
        addObserverForName:
            UIApplicationDidBecomeActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRApplicationActive(notification);
        }];

    [center
        addObserverForName:
            UIApplicationWillResignActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRApplicationInactive(notification);
        }];

    NSLog(
        @"[SanneRealtime] OBSERVERS INSTALLED");
}

static void SRStartup(void)
{
    NSLog(
        @"[SanneRealtime] =========================");

    NSLog(
        @"[SanneRealtime] SANNE REALTIME CAPTURE BUILD");

    NSLog(
        @"[SanneRealtime] =========================");

    NSLog(
        @"[SanneRealtime] %@",
        SRSessionReport());

    SRInstallObservers();

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            1500 * NSEC_PER_MSEC),
        dispatch_get_main_queue(),
        ^{

            AVAudioSession *session =
                [AVAudioSession sharedInstance];

            NSLog(
                @"[SanneRealtime] FIRST CHECK");

            NSLog(
                @"[SanneRealtime] %@",
                SRSessionReport());

            if (@available(iOS 18.2, *)) {

                if (session.isMicrophoneInjectionAvailable &&
                    session.isInputAvailable &&
                    session.inputNumberOfChannels > 0) {

                    SREnableKnownGoodInjection();

                } else {

                    SRPopup(
                        [NSString stringWithFormat:
                            @"Waiting for active Discord audio.\n\n"
                             "Injection: %@\n"
                             "Input: %@\n"
                             "Channels: %ld\n\n"
                             "Make the Nobanny call now.",
                            session.isMicrophoneInjectionAvailable
                                ? @"YES"
                                : @"NO",
                            session.isInputAvailable
                                ? @"YES"
                                : @"NO",
                            (long)session.inputNumberOfChannels]);
                }
            }
        });
}

__attribute__((constructor))
static void SanneRealtimeLoaded(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            SRStartup();
        });
}
