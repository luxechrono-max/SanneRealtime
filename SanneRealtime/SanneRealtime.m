#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static NSMutableArray<NSString *> *SRLog;
static BOOL SRInjectionYESSeen = NO;
static BOOL SRSpokenAudioSet = NO;

static NSString *SRNow(void) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"HH:mm:ss.SSS";
    return [f stringFromDate:[NSDate date]];
}

static void SRLogLine(NSString *line) {
    if (!SRLog) SRLog = [NSMutableArray array];

    NSString *entry = [NSString stringWithFormat:@"[%@] %@",
                       SRNow(), line];

    [SRLog addObject:entry];

    if (SRLog.count > 80) {
        [SRLog removeObjectAtIndex:0];
    }

    NSLog(@"SanneRealtime %@", entry);
}

static NSString *SRPermissionName(void) {
    if (@available(iOS 18.2, *)) {
        AVAudioApplicationMicrophoneInjectionPermission p =
            AVAudioApplication.shared.microphoneInjectionPermission;

        switch (p) {
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

static NSString *SRModeName(AVAudioSession *session) {
    NSString *mode = session.mode;

    if ([mode isEqualToString:AVAudioSessionModeVoiceChat])
        return @"VoiceChat";

    if ([mode isEqualToString:AVAudioSessionModeVideoChat])
        return @"VideoChat";

    if ([mode isEqualToString:AVAudioSessionModeMeasurement])
        return @"Measurement";

    if ([mode isEqualToString:AVAudioSessionModeGameChat])
        return @"GameChat";

    return mode ?: @"<none>";
}

static NSString *SRCategoryName(AVAudioSession *session) {
    return session.category ?: @"<none>";
}

static void SRShowPopup(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;

        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]])
                continue;

            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }

            if (keyWindow)
                break;
        }

        if (!keyWindow)
            return;

        UIViewController *root = keyWindow.rootViewController;

        while (root.presentedViewController) {
            root = root.presentedViewController;
        }

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:title
                                                message:message
                                         preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction actionWithTitle:@"OK"
                                     style:UIAlertActionStyleDefault
                                   handler:nil]];

        [root presentViewController:alert animated:YES completion:nil];
    });
}

static NSString *SRSessionReport(AVAudioSession *session) {
    AVAudioFormat *inputFormat = session.inputFormatForBus:0;

    double sampleRate = session.sampleRate;
    NSInteger channels = session.inputNumberOfChannels;

    NSString *formatDescription = @"<none>";

    if (inputFormat) {
        formatDescription = [NSString stringWithFormat:
                             @"%@",
                             inputFormat];
    }

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
             "PERMISSION: %@\n"
             "INPUT FORMAT: %@",
            SRCategoryName(session),
            SRModeName(session),
            session.isInputAvailable ? @"YES" : @"NO",
            (long)channels,
            sampleRate,
            session.inputLatency,
            session.outputLatency,
            session.isMicrophoneInjectionAvailable ? @"YES" : @"NO",
            (long)session.preferredMicrophoneInjectionMode,
            SRPermissionName(),
            formatDescription];
}

static void SRRecordCurrentState(NSString *reason) {
    AVAudioSession *session = AVAudioSession.sharedInstance;

    SRLogLine([NSString stringWithFormat:
               @"STATE: %@\n%@",
               reason,
               SRSessionReport(session)]);
}

static void SRHandleInjectionCapabilityChange(NSNotification *notification) {
    AVAudioSession *session = AVAudioSession.sharedInstance;

    NSNumber *availableNumber =
        notification.userInfo[AVAudioSessionMicrophoneInjectionIsAvailableKey];

    BOOL available =
        availableNumber ? availableNumber.boolValue
                        : session.isMicrophoneInjectionAvailable;

    SRLogLine([NSString stringWithFormat:
               @"MICROPHONE INJECTION CAPABILITY CHANGED: %@",
               available ? @"YES" : @"NO"]);

    SRLogLine([NSString stringWithFormat:
               @"PERMISSION: %@",
               SRPermissionName()]);

    SRLogLine([NSString stringWithFormat:
               @"CATEGORY: %@",
               SRCategoryName(session)]);

    SRLogLine([NSString stringWithFormat:
               @"MODE: %@",
               SRModeName(session)]);

    SRLogLine([NSString stringWithFormat:
               @"INPUT AVAILABLE: %@",
               session.isInputAvailable ? @"YES" : @"NO"]);

    SRLogLine([NSString stringWithFormat:
               @"INPUT CHANNELS: %ld",
               (long)session.inputNumberOfChannels]);

    SRLogLine([NSString stringWithFormat:
               @"SAMPLE RATE: %.2f",
               session.sampleRate]);

    SRLogLine([NSString stringWithFormat:
               @"INJECTION AVAILABLE: %@",
               available ? @"YES" : @"NO"]);

    if (available && !SRInjectionYESSeen) {
        SRInjectionYESSeen = YES;

        SRLogLine(@"*** REAL INJECTION CAPABILITY DETECTED ***");

        if (@available(iOS 18.2, *)) {
            NSError *error = nil;

            BOOL success =
                [session setPreferredMicrophoneInjectionMode:
                    AVAudioSessionMicrophoneInjectionModeSpokenAudio
                                                        error:&error];

            if (success) {
                SRSpokenAudioSet = YES;

                SRLogLine(@"SPOKEN AUDIO MODE: SET SUCCESSFULLY");

                SRShowPopup(
                    @"SanneRealtime\nINJECTION CAPABILITY YES",
                    [NSString stringWithFormat:
                     @"iOS exposed microphone injection.\n\n"
                      "SpokenAudio mode was accepted.\n\n"
                      "CATEGORY: %@\n"
                      "MODE: %@\n"
                      "INPUT CHANNELS: %ld\n"
                      "SAMPLE RATE: %.0f\n\n"
                      "NO AUDIO WAS GENERATED.\n"
                      "NO AVAudioEngine WAS CREATED.",
                     SRCategoryName(session),
                     SRModeName(session),
                     (long)session.inputNumberOfChannels,
                     session.sampleRate]
                );
            } else {
                SRLogLine([NSString stringWithFormat:
                           @"SPOKEN AUDIO MODE: FAILED\nERROR: %@",
                           error]);

                SRShowPopup(
                    @"SanneRealtime\nINJECTION YES",
                    [NSString stringWithFormat:
                     @"iOS says injection is AVAILABLE,\n"
                      "but SpokenAudio mode failed.\n\n"
                      "Error:\n%@\n\n"
                      "NO AUDIO WAS GENERATED.",
                     error]
                );
            }
        }
    }

    if (!available) {
        SRInjectionYESSeen = NO;
        SRSpokenAudioSet = NO;

        SRLogLine(@"INJECTION CAPABILITY LOST");

        SRShowPopup(
            @"SanneRealtime\nINJECTION NO",
            @"iOS currently reports microphone injection unavailable.\n\n"
             "No audio was generated."
        );
    }
}

static void SRHandleAudioSessionNotification(NSNotification *notification) {
    NSString *name = notification.name;

    if ([name isEqualToString:AVAudioSessionDidBecomeActiveNotification]) {
        SRLogLine(@"AUDIO SESSION DID BECOME ACTIVE");
        SRRecordCurrentState(@"AFTER SESSION ACTIVE");
        return;
    }

    if ([name isEqualToString:AVAudioSessionDidBecomeInactiveNotification]) {
        SRLogLine(@"AUDIO SESSION DID BECOME INACTIVE");
        SRRecordCurrentState(@"AFTER SESSION INACTIVE");
        return;
    }

    if ([name isEqualToString:AVAudioSessionRouteChangeNotification]) {
        NSNumber *reason =
            notification.userInfo[AVAudioSessionRouteChangeReasonKey];

        SRLogLine([NSString stringWithFormat:
                   @"ROUTE CHANGE REASON: %@",
                   reason ?: @"<unknown>"]);

        SRRecordCurrentState(@"AFTER ROUTE CHANGE");
        return;
    }

    if ([name isEqualToString:AVAudioSessionInterruptionNotification]) {
        SRLogLine(@"AUDIO SESSION INTERRUPTION");
        SRRecordCurrentState(@"AFTER INTERRUPTION");
        return;
    }
}

static void SRInstallObservers(void) {
    NSNotificationCenter *nc =
        NSNotificationCenter.defaultCenter;

    [nc addObserverForName:
        AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        SRHandleInjectionCapabilityChange(note);
    }];

    [nc addObserverForName:
        AVAudioSessionDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        SRHandleAudioSessionNotification(note);
    }];

    [nc addObserverForName:
        AVAudioSessionDidBecomeInactiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        SRHandleAudioSessionNotification(note);
    }];

    [nc addObserverForName:
        AVAudioSessionRouteChangeNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        SRHandleAudioSessionNotification(note);
    }];

    [nc addObserverForName:
        AVAudioSessionInterruptionNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        SRHandleAudioSessionNotification(note);
    }];

    SRLogLine(@"MICROPHONE INJECTION CAPABILITY OBSERVER INSTALLED");
    SRLogLine(@"AUDIO SESSION OBSERVERS INSTALLED");
}

__attribute__((constructor))
static void SanneRealtimeInit(void) {

    @autoreleasepool {

        SRLog = [NSMutableArray array];

        SRLogLine(@"========================================");
        SRLogLine(@"SANNE REALTIME - CAPABILITY PROBE BUILD");
        SRLogLine(@"========================================");

        SRLogLine(@"ZERO AUDIO INJECTION");
        SRLogLine(@"ZERO AUDIO GENERATION");
        SRLogLine(@"ZERO AVAUDIOENGINE");
        SRLogLine(@"ZERO MICROPHONE TAP");
        SRLogLine(@"ZERO AUDIO SESSION ACTIVATION");

        SRLogLine([NSString stringWithFormat:
                   @"MICROPHONE INJECTION PERMISSION: %@",
                   SRPermissionName()]);

        SRInstallObservers();

        dispatch_async(dispatch_get_main_queue(), ^{
            AVAudioSession *session =
                AVAudioSession.sharedInstance;

            SRRecordCurrentState(@"INITIAL OBSERVATION");

            BOOL available =
                session.isMicrophoneInjectionAvailable;

            SRLogLine([NSString stringWithFormat:
                       @"INITIAL INJECTION AVAILABLE: %@",
                       available ? @"YES" : @"NO"]);

            if (available) {
                SRHandleInjectionCapabilityChange(nil);
            }

            SRShowPopup(
                @"SanneRealtime\nCAPABILITY PROBE READY",
                [NSString stringWithFormat:
                 @"Permission: %@\n\n"
                  "Current injection: %@\n\n"
                  "This build is PASSIVE.\n"
                  "It will wait for iOS to report an injection capability change.\n\n"
                  "No test voice.\n"
                  "No AVAudioEngine.\n"
                  "No microphone tap.",
                 SRPermissionName(),
                 available ? @"YES" : @"NO"]
            );
        });
    }
}
