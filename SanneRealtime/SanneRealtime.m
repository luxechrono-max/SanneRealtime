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
    AVAudioSession *session = [AVAudioSession sharedInstance];

    NSError *error = nil;

    [session setCategory:AVAudioSessionCategoryPlayAndRecord
                    mode:AVAudioSessionModeVoiceChat
                 options:AVAudioSessionCategoryOptionAllowBluetooth
                   error:&error];

    if (error) {
        NSLog(@"[SanneRealtime] setCategory error: %@", error);
        return;
    }

    [session setActive:YES error:&error];

    if (error) {
        NSLog(@"[SanneRealtime] setActive error: %@", error);
        return;
    }

    if (@available(iOS 18.2, *)) {
        NSLog(
            @"[SanneRealtime] Microphone injection available: %@",
            session.isMicrophoneInjectionAvailable ? @"YES" : @"NO"
        );
    }

    NSLog(@"[SanneRealtime] Audio session initialized");
}

@end
