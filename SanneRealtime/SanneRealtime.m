#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static AVSpeechSynthesizer *synthesizer;

static void ShowResult(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;

        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in
                 [UIApplication sharedApplication].connectedScenes) {

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
            return;
        }

        UIViewController *root =
            window.rootViewController;

        while (root.presentedViewController) {
            root = root.presentedViewController;
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

        [root presentViewController:alert
                           animated:YES
                         completion:nil];
    });
}

static void RunInjectionTest(void) {

    if (@available(iOS 18.2, *)) {

        AVAudioApplication *application =
            [AVAudioApplication sharedInstance];

        AVAudioSession *session =
            [AVAudioSession sharedInstance];

        if (application.microphoneInjectionPermission !=
            AVAudioApplicationMicrophoneInjectionPermissionGranted) {

            ShowResult(
                @"Injection permission is not GRANTED."
            );

            return;
        }

        if (!session.isMicrophoneInjectionAvailable) {

            ShowResult(
                @"Injection is currently unavailable.\n\n"
                 "Start a Discord voice call first."
            );

            return;
        }

        NSError *error = nil;

        BOOL success =
            [session
                setPreferredMicrophoneInjectionMode:
                    AVAudioSessionMicrophoneInjectionModeSpokenAudio
                error:&error];

        if (!success || error) {

            NSString *message =
                [NSString stringWithFormat:
                    @"Could not enable injection.\n\n%@",
                    error.localizedDescription ?: @"Unknown error"];

            ShowResult(message);

            return;
        }

        NSLog(
            @"[SanneRealtime] SpokenAudio injection ENABLED"
        );

        /*
         * Generate a short piece of synthesized speech.
         * This is intentionally NOT the Sanne voice yet.
         */
        synthesizer =
            [[AVSpeechSynthesizer alloc] init];

        AVSpeechUtterance *utterance =
            [[AVSpeechUtterance alloc]
                initWithString:
                    @"SanneRealtime test. "
                     "This audio is being injected into the call."];

        utterance.rate = 0.48;
        utterance.volume = 1.0;

        AVSpeechSynthesisVoice *voice =
            [AVSpeechSynthesisVoice
                voiceWithLanguage:@"en-US"];

        if (voice) {
            utterance.voice = voice;
        }

        ShowResult(
            @"Injection ENABLED.\n\n"
             "Sending test speech now."
        );

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                1 * NSEC_PER_SEC
            ),
            dispatch_get_main_queue(),
            ^{
                [synthesizer speakUtterance:utterance];
            }
        );
    }
}

__attribute__((constructor))
static void SanneRealtimeLoaded(void) {

    NSLog(@"[SanneRealtime] DYLIB LOADED");

    dispatch_async(dispatch_get_main_queue(), ^{

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                3 * NSEC_PER_SEC
            ),
            dispatch_get_main_queue(),
            ^{
                RunInjectionTest();
            }
        );
    });
}
