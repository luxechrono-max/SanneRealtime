#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static NSMutableArray<NSString *> *SRLog;

static NSString *SRNow(void) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss.SSS";
    return [formatter stringFromDate:[NSDate date]];
}

static void SRLogLine(NSString *text) {
    if (!SRLog) {
        SRLog = [NSMutableArray array];
    }

    NSString *line =
        [NSString stringWithFormat:@"[%@] %@",
         SRNow(),
         text];

    [SRLog addObject:line];

    if (SRLog.count > 100) {
        [SRLog removeObjectAtIndex:0];
    }

    NSLog(@"[SanneRealtime] %@", line);
}

static NSString *SRPermission(void) {

    if (@available(iOS 18.2, *)) {

        AVAudioApplicationMicrophoneInjectionPermission permission =
            [AVAudioApplication sharedInstance].microphoneInjectionPermission;

        switch (permission) {

            case AVAudioApplicationMicrophoneInjectionPermissionGranted:
                return @"GRANTED";

            case AVAudioApplicationMicrophoneInjectionPermissionDenied:
                return @"DENIED";

            case AVAudioApplicationMicrophoneInjectionPermissionUndetermined:
                return @"UNDETERMINED";

            case AVAudioApplicationMicrophoneInjectionPermissionServiceDisabled:
                return @"SERVICE_DISABLED";
        }
    }

    return @"UNAVAILABLE";
}

static NSString *SRCategory(AVAudioSession *session) {
    return session.category ?: @"<none>";
}

static NSString *SRMode(AVAudioSession *session) {
    return session.mode ?: @"<none>";
}

static NSString *SRSessionReport(void) {

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    return [NSString stringWithFormat:
        @"CATEGORY: %@\n"
         "MODE: %@\n"
         "INPUT AVAILABLE: %@\n"
         "INPUT CHANNELS: %ld\n"
         "SAMPLE RATE: %.2f\n"
         "INPUT LATENCY: %.6f\n"
         "OUTPUT LATENCY: %.6f\n"
         "INJECTION AVAILABLE: %@\n"
         "PREFERRED INJECTION MODE: %ld\n"
         "INJECTION PERMISSION: %@",
         
         SRCategory(session),
         SRMode(session),
         session.isInputAvailable ? @"YES" : @"NO",
         (long)session.inputNumberOfChannels,
         session.sampleRate,
         session.inputLatency,
         session.outputLatency,
         session.isMicrophoneInjectionAvailable ? @"YES" : @"NO",
         (long)session.preferredMicrophoneInjectionMode,
         SRPermission()];
}

static UIWindow *SRKeyWindow(void) {

    for (UIScene *scene in
         [UIApplication sharedApplication].connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        for (UIWindow *window in windowScene.windows) {

            if (window.isKeyWindow) {
                return window;
            }
        }
    }

    return nil;
}

static void SRPopup(NSString *title,
                    NSString *message) {

    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window = SRKeyWindow();

        if (!window) {
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
                alertControllerWithTitle:title
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

static void SRInjectionCapabilityChanged(NSNotification *notification) {

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    BOOL available =
        session.isMicrophoneInjectionAvailable;

    NSNumber *reported =
        notification.userInfo[
            AVAudioSessionMicrophoneInjectionIsAvailableKey
        ];

    if (reported) {
        available = reported.boolValue;
    }

    SRLogLine(@"========================================");
    SRLogLine(@"MICROPHONE INJECTION CAPABILITY CHANGED");
    SRLogLine(@"========================================");

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION AVAILABLE: %@",
            available ? @"YES" : @"NO"]);

    SRLogLine(
        [NSString stringWithFormat:
            @"PERMISSION: %@",
            SRPermission()]);

    SRLogLine(
        [NSString stringWithFormat:
            @"CATEGORY: %@",
            SRCategory(session)]);

    SRLogLine(
        [NSString stringWithFormat:
            @"MODE: %@",
            SRMode(session)]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT AVAILABLE: %@",
            session.isInputAvailable ? @"YES" : @"NO"]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT CHANNELS: %ld",
            (long)session.inputNumberOfChannels]);

    SRLogLine(
        [NSString stringWithFormat:
            @"SAMPLE RATE: %.2f",
            session.sampleRate]);

    SRLogLine(
        [NSString stringWithFormat:
            @"PREFERRED INJECTION MODE: %ld",
            (long)session.preferredMicrophoneInjectionMode]);

    if (available) {

        SRLogLine(@"*** REAL INJECTION CAPABILITY DETECTED ***");

        /*
         IMPORTANT:
         We are NOT generating audio.
         We are NOT creating AVAudioEngine.
         We are NOT tapping the microphone.
         We are only selecting Apple's documented
         SpokenAudio injection mode.
        */

        if (@available(iOS 18.2, *)) {

            NSError *error = nil;

            BOOL success =
                [session
                    setPreferredMicrophoneInjectionMode:
                        AVAudioSessionMicrophoneInjectionModeSpokenAudio
                    error:&error];

            if (success) {

                SRLogLine(
                    @"SPOKEN AUDIO MODE: SET SUCCESSFULLY");

                SRPopup(
                    @"SanneRealtime\nINJECTION AVAILABLE",
                    [NSString stringWithFormat:
                        @"iOS exposed microphone injection.\n\n"
                         "SpokenAudio mode: SUCCESS\n\n"
                         "CATEGORY: %@\n"
                         "MODE: %@\n"
                         "INPUT CHANNELS: %ld\n"
                         "SAMPLE RATE: %.0f\n\n"
                         "NO AUDIO WAS GENERATED.",
                         
                         SRCategory(session),
                         SRMode(session),
                         (long)session.inputNumberOfChannels,
                         session.sampleRate]);
                
            } else {

                SRLogLine(
                    [NSString stringWithFormat:
                        @"SPOKEN AUDIO MODE: FAILED\nERROR: %@",
                        error]);

                SRPopup(
                    @"SanneRealtime\nINJECTION AVAILABLE",
                    [NSString stringWithFormat:
                        @"iOS reports injection AVAILABLE,\n"
                         "but SpokenAudio mode failed.\n\n"
                         "ERROR:\n%@",
                        error]);
            }
        }

    } else {

        SRLogLine(@"INJECTION CAPABILITY: NO");

        SRPopup(
            @"SanneRealtime\nINJECTION NOT AVAILABLE",
            [NSString stringWithFormat:
                @"iOS currently reports microphone injection "
                 "as UNAVAILABLE.\n\n"
                 "Permission: %@\n\n"
                 "No audio was generated.",
                SRPermission()]);
    }
}

static void SRInstallObservers(void) {

    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    [center
        addObserverForName:
            AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {

            SRInjectionCapabilityChanged(notification);
        }];

    SRLogLine(
        @"MICROPHONE INJECTION CAPABILITY OBSERVER INSTALLED");
}

static void SRInitialState(void) {

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    SRLogLine(@"========================================");
    SRLogLine(@"SANNE REALTIME - CAPABILITY PROBE");
    SRLogLine(@"========================================");

    SRLogLine(@"ZERO AUDIO GENERATION");
    SRLogLine(@"ZERO AUDIO PLAYBACK");
    SRLogLine(@"ZERO AVAUDIOENGINE");
    SRLogLine(@"ZERO MICROPHONE TAP");
    SRLogLine(@"ZERO AUDIO SESSION ACTIVATION");

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION PERMISSION: %@",
            SRPermission()]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INITIAL INJECTION AVAILABLE: %@",
            session.isMicrophoneInjectionAvailable
                ? @"YES"
                : @"NO"]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INITIAL CATEGORY: %@",
            SRCategory(session)]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INITIAL MODE: %@",
            SRMode(session)]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INITIAL INPUT CHANNELS: %ld",
            (long)session.inputNumberOfChannels]);
}

__attribute__((constructor))
static void SanneRealtimeInit(void) {

    @autoreleasepool {

        SRLog = [NSMutableArray array];

        SRInstallObservers();

        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                SRInitialState();

                AVAudioSession *session =
                    [AVAudioSession sharedInstance];

                SRPopup(
                    @"SanneRealtime\nCAPABILITY PROBE READY",
                    [NSString stringWithFormat:
                        @"Permission: %@\n\n"
                         "Current injection: %@\n\n"
                         "This build is waiting for Apple's "
                         "microphone-injection capability event.\n\n"
                         "No test voice.\n"
                         "No AVAudioEngine.\n"
                         "No microphone tap.",
                        
                        SRPermission(),
                        session.isMicrophoneInjectionAvailable
                            ? @"YES"
                            : @"NO"]);
            });
    }
}
