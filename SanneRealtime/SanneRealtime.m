#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static AVSpeechSynthesizer *synthesizer = nil;

static void ShowResult(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;

        if (@available(iOS 13.0, *)) {
            NSSet<UIScene *> *scenes =
                [UIApplication sharedApplication].connectedScenes;

            for (UIScene *scene in scenes) {
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
            NSLog(@"[SanneRealtime] No active window");
            return;
        }

        UIViewController *root =
            window.rootViewController;

        if (!root) {
            return;
        }

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

static void StartInjectionTest(void) {

    if (@available(iOS 18.2, *)) {

        AVAudioApplication *application =
            [AVAudioApplication sharedInstance];

        AVAudioSession *session =
            [AVAudioSession sharedInstance];

        AVAudioApplicationMicrophoneInjectionPermission permission =
            application.microphoneInjectionPermission;

        BOOL available =
            session.isMicrophoneInjectionAvailable;

        NSLog(
            @"[SanneRealtime] Permission=%ld Available=%@",
            (long)permission,
            available ? @"YES" : @"NO"
        );

        if (permission !=
            AVAudioApplicationMicrophoneInjectionPermissionGranted) {

            ShowResult(
                @"Injection permission is not GRANTED."
            );

            return;
        }

        if (!available) {

            ShowResult(
                @"Injection is currently unavailable.\n\n"
                 "Start a Discord voice call first."
            );

            return;
        }

        NSError *error = nil;

        BOOL enabled =
            [session
                setPreferredMicrophoneInjectionMode:
                    AVAudioSessionMicrophoneInjectionModeSpokenAudio
                error:&error];

        if (!enabled) {

            NSString *errorText =
                error.localizedDescription
                ?: @"Unknown AVAudioSession error.";

            ShowResult(
                [NSString stringWithFormat:
                    @"FAILED TO ENABLE INJECTION\n\n%@",
                    errorText]
            );

            return;
        }

        NSLog(
            @"[SanneRealtime] SpokenAudio injection enabled."
        );

        /*
         * Keep the synthesizer alive while it speaks.
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
            @"INJECTION ENABLED\n\n"
             "Sending test speech now."
        );

        /*
         * Give the alert a moment to appear, then speak.
         */
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                2 * NSEC_PER_SEC
            ),
            dispatch_get_main_queue(),
            ^{
                NSLog(
                    @"[SanneRealtime] Speaking test sentence."
                );

                [synthesizer speakUtterance:utterance];
            }
        );

    } else {

        ShowResult(
            @"Microphone injection requires iOS 18.2 or newer."
        );
    }
}

__attribute__((constructor))
static void SanneRealtimeLoaded(void) {

    NSLog(@"[SanneRealtime] DYLIB LOADED");

    dispatch_async(dispatch_get_main_queue(), ^{

        /*
         * Give Nobanny time to finish launching.
         */
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                3 * NSEC_PER_SEC
            ),
            dispatch_get_main_queue(),
            ^{
                StartInjectionTest();
            }
        );
    });
}
