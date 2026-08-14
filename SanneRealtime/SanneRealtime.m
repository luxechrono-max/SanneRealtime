#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static AVSpeechSynthesizer *gSynth = nil;

static void SRPopup(NSString *message)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;

        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {

                if (scene.activationState != UISceneActivationStateForegroundActive)
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
        [UIAlertController alertControllerWithTitle:@"SanneRealtime"
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction actionWithTitle:@"OK"
                                     style:UIAlertActionStyleDefault
                                   handler:nil]];

        [vc presentViewController:alert animated:YES completion:nil];
    });
}


static NSString *SRPermissionString(void)
{
    if (@available(iOS 18.2, *)) {

        AVAudioApplicationMicrophoneInjectionPermission p =
            AVAudioApplication.sharedInstance.microphoneInjectionPermission;

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


static AVSpeechSynthesisVoice *SRFemaleVoice(void)
{
    if (@available(iOS 13.0, *)) {

        NSArray<AVSpeechSynthesisVoice *> *voices =
            [AVSpeechSynthesisVoice speechVoices];

        for (AVSpeechSynthesisVoice *voice in voices) {

            if (voice.gender == AVSpeechSynthesisVoiceGenderFemale &&
                [voice.language hasPrefix:@"en"]) {

                return voice;
            }
        }
    }

    return [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
}


static void SRSpeakTest(void)
{
    if (!gSynth)
        gSynth = [[AVSpeechSynthesizer alloc] init];

    AVSpeechSynthesisVoice *voice = SRFemaleVoice();

    AVSpeechUtterance *utterance =
        [AVSpeechUtterance speechUtteranceWithString:
            @"Hello. This is the SanneRealtime female voice test."];

    utterance.voice = voice;
    utterance.rate = 0.48;
    utterance.pitchMultiplier = 1.05;
    utterance.volume = 1.0;

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

    if (permission ==
        AVAudioApplicationMicrophoneInjectionPermissionUndetermined) {

        [AVAudioApplication
            requestMicrophoneInjectionPermissionWithCompletionHandler:
            ^(AVAudioApplicationMicrophoneInjectionPermission result) {

                dispatch_async(dispatch_get_main_queue(), ^{
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
                });
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
            @"Permission is GRANTED, but injection is currently unavailable.\n\n"
             "Start the Discord call and open Nobanny again."
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
                error.localizedDescription ?: @"Unknown error"]
        );

        return;
    }

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
     * - create AVAudioEngine
     * - install a microphone tap
     * - take ownership of the audio route
     *
     * Apple's microphone-injection system handles adding
     * the synthesized speech to the active call.
     */

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
        dispatch_get_main_queue(),
        ^{
            SRSpeakTest();
        }
    );
}


static void SRCheckInjectionState(void)
{
    if (!@available(iOS 18.2, *)) {
        SRPopup(@"iOS 18.2 or newer is required.");
        return;
    }

    AVAudioSession *session =
        AVAudioSession.sharedInstance;

    NSString *message =
    [NSString stringWithFormat:
        @"INJECTION PERMISSION: %@\n"
         "INJECTION AVAILABLE: %@\n\n"
         "CATEGORY: %@\n"
         "MODE: %@\n"
         "INPUT AVAILABLE: %@\n"
         "INPUT CHANNELS: %ld",

        SRPermissionString(),

        session.isMicrophoneInjectionAvailable
            ? @"YES"
            : @"NO",

        session.category ?: @"?",

        session.mode ?: @"?",

        session.isInputAvailable
            ? @"YES"
            : @"NO",

        (long)session.inputNumberOfChannels
    ];

    NSLog(@"[SanneRealtime]\n%@", message);

    SREnableInjectionAndTest();
}


__attribute__((constructor))
static void SanneRealtimeLoaded(void)
{
    NSLog(@"[SanneRealtime] ===========================");
    NSLog(@"[SanneRealtime] FEMALE TEST VOICE BUILD");
    NSLog(@"[SanneRealtime] ===========================");

    dispatch_async(dispatch_get_main_queue(), ^{

        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, 1200 * NSEC_PER_MSEC),
            dispatch_get_main_queue(),
            ^{
                SRCheckInjectionState();
            }
        );
    });
}
