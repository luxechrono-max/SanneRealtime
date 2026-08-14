#import <Foundation/Foundation.h>
#import <AVFAudio/AVFAudio.h>

@interface SanneRealtime : NSObject
@end

@implementation SanneRealtime

+ (instancetype)shared {
    static SanneRealtime *instance;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        instance = [[SanneRealtime alloc] init];
    });

    return instance;
}

- (void)start {
    NSLog(@"[SanneRealtime] Starting...");

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    NSError *error = nil;

    [session setCategory:AVAudioSessionCategoryPlayAndRecord
                    mode:AVAudioSessionModeVoiceChat
                 options:AVAudioSessionCategoryOptionAllowBluetoothHFP
                   error:&error];

    if (error) {
        NSLog(@"[SanneRealtime] Category error: %@", error);
        return;
    }

    [session setActive:YES error:&error];

    if (error) {
        NSLog(@"[SanneRealtime] Activation error: %@", error);
        return;
    }

    if (@available(iOS 18.2, *)) {

        AVAudioApplication *application =
            [AVAudioApplication sharedInstance];

        NSLog(
            @"[SanneRealtime] Injection permission: %ld",
            (long)application.microphoneInjectionPermission
        );

        [AVAudioApplication
            requestMicrophoneInjectionPermissionWithCompletionHandler:
            ^(AVAudioApplicationMicrophoneInjectionPermission permission) {

                NSLog(
                    @"[SanneRealtime] Injection permission result: %ld",
                    (long)permission
                );

                if (
                    permission ==
                    AVAudioApplicationMicrophoneInjectionPermissionGranted
                ) {

                    dispatch_async(
                        dispatch_get_main_queue(),
                        ^{

                            NSError *injectionError = nil;

                            BOOL available =
                                session.isMicrophoneInjectionAvailable;

                            NSLog(
                                @"[SanneRealtime] Injection available: %@",
                                available ? @"YES" : @"NO"
                            );

                            if (!available) {
                                return;
                            }

                            BOOL success =
                                [session
                                    setPreferredMicrophoneInjectionMode:
                                        AVAudioSessionMicrophoneInjectionModeSpokenAudio
                                    error:&injectionError];

                            NSLog(
                                @"[SanneRealtime] Injection enabled: %@",
                                success ? @"YES" : @"NO"
                            );

                            if (injectionError) {
                                NSLog(
                                    @"[SanneRealtime] Injection error: %@",
                                    injectionError
                                );
                            }
                        }
                    );
                }
            }
        ];
    }
}

@end
