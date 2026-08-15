#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static NSMutableArray<NSString *> *SRLog;
static UIView *SROverlay;
static UILabel *SRLabel;
static NSTimer *SRRefreshTimer;

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

    if (SRLog.count > 120) {
        [SRLog removeObjectAtIndex:0];
    }

    NSLog(@"[SanneRealtime] %@", line);
}

static NSString *SRPermission(void) {
    if (@available(iOS 18.2, *)) {
        AVAudioApplication *application =
            [AVAudioApplication sharedInstance];

        AVAudioApplicationMicrophoneInjectionPermission permission =
            application.microphoneInjectionPermission;

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

static NSString *SRRouteReason(AVAudioSessionRouteChangeReason reason) {
    switch (reason) {
        case AVAudioSessionRouteChangeReasonUnknown:
            return @"UNKNOWN";

        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            return @"NEW_DEVICE_AVAILABLE";

        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            return @"OLD_DEVICE_UNAVAILABLE";

        case AVAudioSessionRouteChangeReasonCategoryChange:
            return @"CATEGORY_CHANGE";

        case AVAudioSessionRouteChangeReasonOverride:
            return @"OVERRIDE";

        case AVAudioSessionRouteChangeReasonWakeFromSleep:
            return @"WAKE_FROM_SLEEP";

        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
            return @"NO_SUITABLE_ROUTE";

        case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
            return @"ROUTE_CONFIGURATION_CHANGE";

        default:
            return [NSString stringWithFormat:@"UNKNOWN_%ld",
                    (long)reason];
    }
}

static NSString *SRPortDescription(AVAudioSessionPortDescription *port) {
    if (!port) {
        return @"NONE";
    }

    NSString *name = port.portName ?: @"?";
    NSString *type = port.portType ?: @"?";

    return [NSString stringWithFormat:@"%@/%@",
            name,
            type];
}

static NSString *SRCategory(AVAudioSession *session) {
    return session.category ?: @"<none>";
}

static NSString *SRMode(AVAudioSession *session) {
    return session.mode ?: @"<none>";
}

static NSString *SRCurrentRoute(void) {
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    AVAudioSessionRouteDescription *route =
        session.currentRoute;

    NSMutableArray<NSString *> *inputs =
        [NSMutableArray array];

    NSMutableArray<NSString *> *outputs =
        [NSMutableArray array];

    for (AVAudioSessionPortDescription *port in route.inputs) {
        [inputs addObject:SRPortDescription(port)];
    }

    for (AVAudioSessionPortDescription *port in route.outputs) {
        [outputs addObject:SRPortDescription(port)];
    }

    NSString *inputText =
        inputs.count
        ? [inputs componentsJoinedByString:@","]
        : @"NONE";

    NSString *outputText =
        outputs.count
        ? [outputs componentsJoinedByString:@","]
        : @"NONE";

    return [NSString stringWithFormat:
            @"IN:%@ OUT:%@",
            inputText,
            outputText];
}

static NSString *SRInjectionState(void) {
    if (@available(iOS 18.2, *)) {
        return
            [AVAudioSession sharedInstance].isMicrophoneInjectionAvailable
            ? @"YES"
            : @"NO";
    }

    return @"UNAVAILABLE";
}

static void SRLogSessionState(NSString *reason) {
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    SRLogLine(
        [NSString stringWithFormat:
            @"SESSION:%@ CAT:%@ MODE:%@ INPUT:%@ CH:%ld SR:%.0f ROUTE:%@",
            reason,
            SRCategory(session),
            SRMode(session),
            session.isInputAvailable ? @"YES" : @"NO",
            (long)session.inputNumberOfChannels,
            session.sampleRate,
            SRCurrentRoute()]);
}

static UIWindow *SRKeyWindow(void) {
    UIApplication *application =
        [UIApplication sharedApplication];

    for (UIScene *scene in application.connectedScenes) {
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

static void SRUpdateOverlay(void);

static void SRCreateOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = SRKeyWindow();

        if (!window) {
            SRLogLine(@"OVERLAY:NO KEY WINDOW");
            return;
        }

        if (SROverlay &&
            SROverlay.superview == window) {
            SRUpdateOverlay();
            return;
        }

        [SROverlay removeFromSuperview];

        SROverlay = nil;
        SRLabel = nil;

        CGFloat width =
            MIN(585.0,
                window.bounds.size.width - 24.0);

        CGFloat height = 310.0;

        CGFloat x =
            (window.bounds.size.width - width) / 2.0;

        UIView *overlay =
            [[UIView alloc]
                initWithFrame:
                    CGRectMake(x,
                               118.0,
                               width,
                               height)];

        overlay.backgroundColor =
            [UIColor colorWithWhite:0.0
                              alpha:0.88];

        overlay.layer.cornerRadius = 16.0;
        overlay.clipsToBounds = YES;
        overlay.userInteractionEnabled = NO;

        UILabel *label =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(12.0,
                               10.0,
                               width - 24.0,
                               height - 20.0)];

        label.textColor =
            UIColor.whiteColor;

        label.backgroundColor =
            UIColor.clearColor;

        label.font =
            [UIFont monospacedSystemFontOfSize:13.0
                                         weight:UIFontWeightRegular];

        label.numberOfLines = 0;
        label.lineBreakMode =
            NSLineBreakByClipping;

        label.adjustsFontSizeToFitWidth = NO;
        label.userInteractionEnabled = NO;

        [overlay addSubview:label];
        [window addSubview:overlay];

        SROverlay = overlay;
        SRLabel = label;

        SRLogLine(@"OVERLAY ATTACHED");

        SRUpdateOverlay();
    });
}

static void SRUpdateOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!SROverlay || !SRLabel) {
            return;
        }

        UIWindow *window = SRKeyWindow();

        if (!window) {
            return;
        }

        if (SROverlay.superview != window) {
            [SROverlay removeFromSuperview];
            [window addSubview:SROverlay];

            SRLogLine(@"OVERLAY REATTACHED");
        }

        AVAudioSession *session =
            [AVAudioSession sharedInstance];

        NSString *latest = @"";

        if (SRLog.count > 0) {
            NSUInteger start =
                SRLog.count > 11
                ? SRLog.count - 11
                : 0;

            NSArray<NSString *> *lines =
                [SRLog subarrayWithRange:
                    NSMakeRange(start,
                                SRLog.count - start)];

            latest =
                [lines componentsJoinedByString:@"\n"];
        }

        UIApplicationState state =
            [UIApplication sharedApplication].applicationState;

        NSString *applicationState =
            state == UIApplicationStateActive
            ? @"ACTIVE"
            : state == UIApplicationStateInactive
                ? @"INACTIVE"
                : @"BACKGROUND";

        NSString *header =
            [NSString stringWithFormat:
                @"SANNE REALTIME\n"
                 "P:%@  I:%@  M:%@\n"
                 "CAT:%@\n"
                 "MODE:%@\n"
                 "INPUT:%@  CH:%ld  SR:%.0f\n"
                 "ROUTE:%@\n"
                 "APP:%@\n"
                 "--------------------------------\n",
                SRPermission(),
                SRInjectionState(),
                session.isInputAvailable
                    ? @"INPUT"
                    : @"NONE",
                SRCategory(session),
                SRMode(session),
                session.isInputAvailable
                    ? @"YES"
                    : @"NO",
                (long)session.inputNumberOfChannels,
                session.sampleRate,
                SRCurrentRoute(),
                applicationState];

        SRLabel.text =
            [header stringByAppendingString:latest];
    });
}

static void SRRouteChanged(NSNotification *notification) {
    NSNumber *reasonNumber =
        notification.userInfo[
            AVAudioSessionRouteChangeReasonKey];

    AVAudioSessionRouteChangeReason reason =
        reasonNumber
        ? reasonNumber.unsignedIntegerValue
        : AVAudioSessionRouteChangeReasonUnknown;

    SRLogLine(
        [NSString stringWithFormat:
            @"ROUTE CHANGE:%ld",
            (long)reason]);

    SRLogLine(
        [NSString stringWithFormat:
            @"ROUTE REASON:%@",
            SRRouteReason(reason)]);

    if (notification.userInfo[
            AVAudioSessionRouteChangePreviousRouteKey]) {
        SRLogLine(@"PREVIOUS ROUTE OBJECT PRESENT");
    }

    SRLogLine(
        [NSString stringWithFormat:
            @"ROUTE:%@",
            SRCurrentRoute()]);

    SRLogSessionState(@"AFTER_ROUTE_CHANGE");

    SRUpdateOverlay();
}

static void SRInterruption(NSNotification *notification) {
    NSNumber *typeNumber =
        notification.userInfo[
            AVAudioSessionInterruptionTypeKey];

    AVAudioSessionInterruptionType type =
        typeNumber
        ? typeNumber.unsignedIntegerValue
        : AVAudioSessionInterruptionTypeBegan;

    if (type ==
        AVAudioSessionInterruptionTypeBegan) {

        SRLogLine(@"INTERRUPTION:BEGAN");

    } else {

        SRLogLine(@"INTERRUPTION:ENDED");

        NSNumber *optionsNumber =
            notification.userInfo[
                AVAudioSessionInterruptionOptionKey];

        if (optionsNumber) {
            SRLogLine(
                [NSString stringWithFormat:
                    @"INTERRUPTION OPTIONS:%lu",
                    (unsigned long)
                    optionsNumber.unsignedIntegerValue]);
        }
    }

    SRLogSessionState(@"AFTER_INTERRUPTION");

    SRUpdateOverlay();
}

static void SRMediaServicesLost(NSNotification *notification) {
    SRLogLine(@"MEDIA SERVICES:LOST");
    SRLogSessionState(@"MEDIA_SERVICES_LOST");
    SRUpdateOverlay();
}

static void SRMediaServicesReset(NSNotification *notification) {
    SRLogLine(@"MEDIA SERVICES:RESET");
    SRLogSessionState(@"MEDIA_SERVICES_RESET");
    SRUpdateOverlay();
}

static void SRApplicationActive(NSNotification *notification) {
    SRLogLine(@"APPLICATION:ACTIVE");
    SRLogSessionState(@"APPLICATION_ACTIVE");
    SRCreateOverlay();
}

static void SRApplicationInactive(NSNotification *notification) {
    SRLogLine(@"APPLICATION:INACTIVE");
    SRLogSessionState(@"APPLICATION_INACTIVE");
    SRUpdateOverlay();
}

static void SRApplicationBackground(NSNotification *notification) {
    SRLogLine(@"APPLICATION:BACKGROUND");
    SRLogSessionState(@"APPLICATION_BACKGROUND");
    SRUpdateOverlay();
}

static void SRApplicationForeground(NSNotification *notification) {
    SRLogLine(@"APPLICATION:FOREGROUND");
    SRLogSessionState(@"APPLICATION_FOREGROUND");
    SRCreateOverlay();
}

static void SRSilenceHint(NSNotification *notification) {
    NSNumber *type =
        notification.userInfo[
            AVAudioSessionSilenceSecondaryAudioHintTypeKey];

    if (type) {
        if (type.unsignedIntegerValue ==
            AVAudioSessionSilenceSecondaryAudioHintTypeBegin) {

            SRLogLine(@"SECONDARY AUDIO SILENCE:BEGIN");

        } else {

            SRLogLine(@"SECONDARY AUDIO SILENCE:END");
        }
    } else {
        SRLogLine(@"SECONDARY AUDIO SILENCE:HINT");
    }

    SRUpdateOverlay();
}

static void SRInjectionCapabilityChanged(NSNotification *notification) {
    SRLogLine(@"MICROPHONE INJECTION CAPABILITY EVENT");

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION:%@",
            SRInjectionState()]);

    SRLogLine(
        [NSString stringWithFormat:
            @"PERMISSION:%@",
            SRPermission()]);

    SRLogSessionState(@"INJECTION_CAPABILITY_EVENT");

    SRUpdateOverlay();
}

static void SRInstallObservers(void) {
    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    [center addObserverForName:
        AVAudioSessionRouteChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
            SRRouteChanged(notification);
        }];

    [center addObserverForName:
        AVAudioSessionInterruptionNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
            SRInterruption(notification);
        }];

    [center addObserverForName:
        AVAudioSessionMediaServicesWereLostNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
            SRMediaServicesLost(notification);
        }];

    [center addObserverForName:
        AVAudioSessionMediaServicesWereResetNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
            SRMediaServicesReset(notification);
        }];

    [center addObserverForName:
        AVAudioSessionSilenceSecondaryAudioHintNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
            SRSilenceHint(notification);
        }];

    [center addObserverForName:
        UIApplicationDidBecomeActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
            SRApplicationActive(notification);
        }];

    [center addObserverForName:
        UIApplicationWillResignActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
            SRApplicationInactive(notification);
        }];

    [center addObserverForName:
        UIApplicationDidEnterBackgroundNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
            SRApplicationBackground(notification);
        }];

    [center addObserverForName:
        UIApplicationWillEnterForegroundNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
            SRApplicationForeground(notification);
        }];

    if (@available(iOS 18.2, *)) {
        [center addObserverForName:
            AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {
                SRInjectionCapabilityChanged(notification);
            }];
    }

    SRLogLine(@"DIAGNOSTIC OBSERVERS INSTALLED");
}

static void SRInitialDiagnostic(void) {
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    SRLogLine(@"================================");
    SRLogLine(@"SANNE REALTIME DIAGNOSTIC");
    SRLogLine(@"================================");
    SRLogLine(@"PASSIVE AUDIO MODE");
    SRLogLine(@"NO AVAUDIOENGINE");
    SRLogLine(@"NO MICROPHONE TAP");
    SRLogLine(@"NO SESSION ACTIVATION");
    SRLogLine(@"NO AUDIO GENERATION");

    SRLogLine(
        [NSString stringWithFormat:
            @"PERMISSION:%@",
            SRPermission()]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION:%@",
            SRInjectionState()]);

    SRLogLine(
        [NSString stringWithFormat:
            @"CATEGORY:%@",
            SRCategory(session)]);

    SRLogLine(
        [NSString stringWithFormat:
            @"MODE:%@",
            SRMode(session)]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT AVAILABLE:%@",
            session.isInputAvailable
            ? @"YES"
            : @"NO"]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT CHANNELS:%ld",
            (long)session.inputNumberOfChannels]);

    SRLogLine(
        [NSString stringWithFormat:
            @"SAMPLE RATE:%.0f",
            session.sampleRate]);

    SRLogLine(
        [NSString stringWithFormat:
            @"ROUTE:%@",
            SRCurrentRoute()]);

    SRCreateOverlay();
}

static void SRStartRefreshTimer(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (SRRefreshTimer) {
            [SRRefreshTimer invalidate];
            SRRefreshTimer = nil;
        }

        SRRefreshTimer =
            [NSTimer scheduledTimerWithTimeInterval:0.5
                                             repeats:YES
                                               block:^(NSTimer *timer) {
            SRUpdateOverlay();
        }];
    });
}

__attribute__((constructor))
static void SanneRealtimeInit(void) {
    @autoreleasepool {
        SRLog =
            [NSMutableArray array];

        SRInstallObservers();

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SRInitialDiagnostic();
                SRStartRefreshTimer();
            });
    }
}
