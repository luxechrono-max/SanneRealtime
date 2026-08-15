#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static NSMutableArray<NSString *> *SRLog = nil;
static UIWindow *SROverlayWindow = nil;
static UILabel *SRLabel = nil;
static NSTimer *SRRefreshTimer = nil;

static NSString *SRNow(void)
{
    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.dateFormat = @"HH:mm:ss.SSS";

    return [formatter stringFromDate:[NSDate date]];
}

static void SRLogLine(NSString *text)
{
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

    dispatch_async(dispatch_get_main_queue(), ^{
        if (SRLabel) {
            NSString *latest = @"";

            NSUInteger start =
                SRLog.count > 13
                ? SRLog.count - 13
                : 0;

            if (SRLog.count > start) {
                NSArray<NSString *> *lines =
                    [SRLog subarrayWithRange:
                        NSMakeRange(start,
                                    SRLog.count - start)];

                latest =
                    [lines componentsJoinedByString:@"\n"];
            }

            SRLabel.text = latest;
        }
    });
}

static NSString *SRPermission(void)
{
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

static NSString *SRInjectionState(void)
{
    if (@available(iOS 18.2, *)) {

        AVAudioSession *session =
            [AVAudioSession sharedInstance];

        return session.isMicrophoneInjectionAvailable
            ? @"YES"
            : @"NO";
    }

    return @"UNAVAILABLE";
}

static NSString *SRRouteReason(
    AVAudioSessionRouteChangeReason reason)
{
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
            return [NSString stringWithFormat:
                @"UNKNOWN_%ld",
                (long)reason];
    }
}

static NSString *SRPortDescription(
    AVAudioSessionPortDescription *port)
{
    if (!port) {
        return @"NONE";
    }

    NSString *name =
        port.portName ?: @"?";

    NSString *type =
        port.portType ?: @"?";

    return [NSString stringWithFormat:
        @"%@/%@",
        name,
        type];
}

static NSString *SRCategory(
    AVAudioSession *session)
{
    return session.category ?: @"<none>";
}

static NSString *SRMode(
    AVAudioSession *session)
{
    return session.mode ?: @"<none>";
}

static NSString *SRCurrentRoute(void)
{
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    AVAudioSessionRouteDescription *route =
        session.currentRoute;

    NSMutableArray<NSString *> *inputs =
        [NSMutableArray array];

    NSMutableArray<NSString *> *outputs =
        [NSMutableArray array];

    for (AVAudioSessionPortDescription *port
         in route.inputs) {

        [inputs addObject:
            SRPortDescription(port)];
    }

    for (AVAudioSessionPortDescription *port
         in route.outputs) {

        [outputs addObject:
            SRPortDescription(port)];
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

static UIWindowScene *SRActiveWindowScene(void)
{
    UIApplication *application =
        [UIApplication sharedApplication];

    for (UIScene *scene
         in application.connectedScenes) {

        if (![scene isKindOfClass:
                [UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateForegroundActive) {

            return windowScene;
        }
    }

    for (UIScene *scene
         in application.connectedScenes) {

        if (![scene isKindOfClass:
                [UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState !=
            UISceneActivationStateUnattached) {

            return windowScene;
        }
    }

    return nil;
}

static void SRUpdateOverlay(void);

static void SRCreateOverlayWindow(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindowScene *scene =
            SRActiveWindowScene();

        if (!scene) {
            SRLogLine(
                @"OVERLAY: NO ACTIVE WINDOW SCENE");
            return;
        }

        if (SROverlayWindow &&
            SROverlayWindow.windowScene == scene &&
            !SROverlayWindow.hidden) {

            SRUpdateOverlay();
            return;
        }

        if (SROverlayWindow) {
            SROverlayWindow.hidden = YES;
            SROverlayWindow =
                nil;
        }

        SROverlayWindow =
            [[UIWindow alloc]
                initWithWindowScene:scene];

        SROverlayWindow.frame =
            scene.coordinateSpace.bounds;

        SROverlayWindow.backgroundColor =
            UIColor.clearColor;

        /*
         Never become the key window.
         Never receive touch events.
        */
        SROverlayWindow.userInteractionEnabled =
            NO;

        SROverlayWindow.hidden =
            NO;

        /*
         Keep it above normal application content,
         but below the system alert level.
        */
        SROverlayWindow.windowLevel =
            UIWindowLevelNormal + 1.0;

        UIViewController *controller =
            [[UIViewController alloc] init];

        controller.view.backgroundColor =
            UIColor.clearColor;

        controller.view.userInteractionEnabled =
            NO;

        SROverlayWindow.rootViewController =
            controller;

        UIView *panel =
            [[UIView alloc]
                initWithFrame:
                    CGRectMake(
                        8.0,
                        60.0,
                        350.0,
                        330.0)];

        panel.backgroundColor =
            [UIColor colorWithWhite:0.0
                              alpha:0.88];

        panel.layer.cornerRadius =
            14.0;

        panel.clipsToBounds =
            YES;

        panel.userInteractionEnabled =
            NO;

        [controller.view addSubview:panel];

        SRLabel =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(
                        10.0,
                        8.0,
                        330.0,
                        314.0)];

        SRLabel.textColor =
            UIColor.whiteColor;

        SRLabel.backgroundColor =
            UIColor.clearColor;

        SRLabel.font =
            [UIFont monospacedSystemFontOfSize:
                11.0
                weight:UIFontWeightRegular];

        SRLabel.numberOfLines =
            0;

        SRLabel.lineBreakMode =
            NSLineBreakByClipping;

        SRLabel.adjustsFontSizeToFitWidth =
            NO;

        SRLabel.userInteractionEnabled =
            NO;

        [panel addSubview:SRLabel];

        SROverlayWindow.hidden =
            NO;

        SRLogLine(
            @"INDEPENDENT OVERLAY CREATED");

        SRUpdateOverlay();
    });
}

static void SRUpdateOverlay(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if (!SROverlayWindow ||
            !SRLabel) {

            return;
        }

        UIWindowScene *scene =
            SRActiveWindowScene();

        if (!scene) {
            return;
        }

        if (SROverlayWindow.windowScene != scene) {

            SRLogLine(
                @"SCENE CHANGED - REBUILDING OVERLAY");

            SROverlayWindow.hidden =
                YES;

            SROverlayWindow =
                nil;

            SRLabel =
                nil;

            SRCreateOverlayWindow();

            return;
        }

        AVAudioSession *session =
            [AVAudioSession sharedInstance];

        UIApplicationState appState =
            [UIApplication sharedApplication]
                .applicationState;

        NSString *state =
            appState == UIApplicationStateActive
            ? @"ACTIVE"
            : appState == UIApplicationStateInactive
                ? @"INACTIVE"
                : @"BACKGROUND";

        NSString *events = @"";

        NSUInteger start =
            SRLog.count > 12
            ? SRLog.count - 12
            : 0;

        if (SRLog.count > start) {

            NSArray<NSString *> *lines =
                [SRLog subarrayWithRange:
                    NSMakeRange(
                        start,
                        SRLog.count - start)];

            events =
                [lines componentsJoinedByString:@"\n"];
        }

        NSString *header =
            [NSString stringWithFormat:
                @"SANNE REALTIME\n"
                 "P:%@  INJ:%@\n"
                 "CAT:%@\n"
                 "MODE:%@\n"
                 "INPUT:%@  CH:%ld\n"
                 "RATE:%.0f\n"
                 "ROUTE:%@\n"
                 "APP:%@\n"
                 "------------------------------\n",
                SRPermission(),
                SRInjectionState(),
                SRCategory(session),
                SRMode(session),
                session.isInputAvailable
                    ? @"YES"
                    : @"NO",
                (long)session.inputNumberOfChannels,
                session.sampleRate,
                SRCurrentRoute(),
                state];

        SRLabel.text =
            [header stringByAppendingString:
                events];

        SROverlayWindow.hidden =
            NO;
    });
}

static void SRLogSessionState(
    NSString *reason)
{
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    SRLogLine(
        [NSString stringWithFormat:
            @"SESSION:%@ CAT:%@ MODE:%@ INPUT:%@ CH:%ld SR:%.0f ROUTE:%@",
            reason,
            SRCategory(session),
            SRMode(session),
            session.isInputAvailable
                ? @"YES"
                : @"NO",
            (long)session.inputNumberOfChannels,
            session.sampleRate,
            SRCurrentRoute()]);
}

static void SRRouteChanged(
    NSNotification *notification)
{
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

        SRLogLine(
            @"PREVIOUS ROUTE OBJECT PRESENT");
    }

    SRLogLine(
        [NSString stringWithFormat:
            @"ROUTE:%@",
            SRCurrentRoute()]);

    SRLogSessionState(
        @"AFTER_ROUTE_CHANGE");

    SRUpdateOverlay();
}

static void SRInterruption(
    NSNotification *notification)
{
    NSNumber *typeNumber =
        notification.userInfo[
            AVAudioSessionInterruptionTypeKey];

    AVAudioSessionInterruptionType type =
        typeNumber
        ? typeNumber.unsignedIntegerValue
        : AVAudioSessionInterruptionTypeBegan;

    if (type ==
        AVAudioSessionInterruptionTypeBegan) {

        SRLogLine(
            @"INTERRUPTION:BEGAN");

    } else {

        SRLogLine(
            @"INTERRUPTION:ENDED");

        NSNumber *options =
            notification.userInfo[
                AVAudioSessionInterruptionOptionKey];

        if (options) {

            SRLogLine(
                [NSString stringWithFormat:
                    @"INTERRUPTION OPTIONS:%lu",
                    (unsigned long)
                    options.unsignedIntegerValue]);
        }
    }

    SRLogSessionState(
        @"AFTER_INTERRUPTION");

    SRUpdateOverlay();
}

static void SRMediaServicesLost(
    NSNotification *notification)
{
    SRLogLine(
        @"MEDIA SERVICES:LOST");

    SRLogSessionState(
        @"MEDIA_SERVICES_LOST");

    SRUpdateOverlay();
}

static void SRMediaServicesReset(
    NSNotification *notification)
{
    SRLogLine(
        @"MEDIA SERVICES:RESET");

    SRLogSessionState(
        @"MEDIA_SERVICES_RESET");

    SRUpdateOverlay();
}

static void SRApplicationActive(
    NSNotification *notification)
{
    SRLogLine(
        @"APPLICATION:ACTIVE");

    SRLogSessionState(
        @"APPLICATION_ACTIVE");

    SRCreateOverlayWindow();
}

static void SRApplicationInactive(
    NSNotification *notification)
{
    SRLogLine(
        @"APPLICATION:INACTIVE");

    SRLogSessionState(
        @"APPLICATION_INACTIVE");

    SRUpdateOverlay();
}

static void SRApplicationForeground(
    NSNotification *notification)
{
    SRLogLine(
        @"APPLICATION:FOREGROUND");

    SRLogSessionState(
        @"APPLICATION_FOREGROUND");

    SRCreateOverlayWindow();
}

static void SRApplicationBackground(
    NSNotification *notification)
{
    SRLogLine(
        @"APPLICATION:BACKGROUND");

    SRLogSessionState(
        @"APPLICATION_BACKGROUND");

    SRUpdateOverlay();
}

static void SRInjectionCapabilityChanged(
    NSNotification *notification)
{
    SRLogLine(
        @"INJECTION CAPABILITY EVENT");

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION:%@",
            SRInjectionState()]);

    SRLogLine(
        [NSString stringWithFormat:
            @"PERMISSION:%@",
            SRPermission()]);

    SRLogSessionState(
        @"INJECTION_CAPABILITY_EVENT");

    SRUpdateOverlay();
}

static void SRSilenceHint(
    NSNotification *notification)
{
    NSNumber *type =
        notification.userInfo[
            AVAudioSessionSilenceSecondaryAudioHintTypeKey];

    if (type) {

        if (type.unsignedIntegerValue ==
            AVAudioSessionSilenceSecondaryAudioHintTypeBegin) {

            SRLogLine(
                @"SECONDARY AUDIO SILENCE:BEGIN");

        } else {

            SRLogLine(
                @"SECONDARY AUDIO SILENCE:END");
        }

    } else {

        SRLogLine(
            @"SECONDARY AUDIO SILENCE:HINT");
    }

    SRUpdateOverlay();
}

static void SRInstallObservers(void)
{
    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    [center addObserverForName:
        AVAudioSessionRouteChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRRouteChanged(notification);
        }];

    [center addObserverForName:
        AVAudioSessionInterruptionNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRInterruption(notification);
        }];

    [center addObserverForName:
        AVAudioSessionMediaServicesWereLostNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRMediaServicesLost(notification);
        }];

    [center addObserverForName:
        AVAudioSessionMediaServicesWereResetNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRMediaServicesReset(notification);
        }];

    [center addObserverForName:
        AVAudioSessionSilenceSecondaryAudioHintNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRSilenceHint(notification);
        }];

    [center addObserverForName:
        UIApplicationDidBecomeActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRApplicationActive(notification);
        }];

    [center addObserverForName:
        UIApplicationWillResignActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRApplicationInactive(notification);
        }];

    [center addObserverForName:
        UIApplicationWillEnterForegroundNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRApplicationForeground(notification);
        }];

    [center addObserverForName:
        UIApplicationDidEnterBackgroundNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRApplicationBackground(notification);
        }];

    if (@available(iOS 18.2, *)) {

        [center addObserverForName:
            AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:
            ^(NSNotification *notification) {

                SRInjectionCapabilityChanged(
                    notification);
            }];
    }

    SRLogLine(
        @"OBSERVERS INSTALLED");
}

static void SRInitialDiagnostic(void)
{
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    SRLogLine(
        @"================================");

    SRLogLine(
        @"SANNE REALTIME DIAGNOSTIC");

    SRLogLine(
        @"================================");

    SRLogLine(
        @"PASSIVE AUDIO MODE");

    SRLogLine(
        @"NO AVAUDIOENGINE");

    SRLogLine(
        @"NO MICROPHONE TAP");

    SRLogLine(
        @"NO SESSION ACTIVATION");

    SRLogLine(
        @"NO AUDIO GENERATION");

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
}

static void SRStartRefreshTimer(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (SRRefreshTimer) {
                [SRRefreshTimer invalidate];
                SRRefreshTimer = nil;
            }

            SRRefreshTimer =
                [NSTimer
                    scheduledTimerWithTimeInterval:
                        0.5
                    repeats:YES
                    block:
                    ^(NSTimer *timer) {

                        if (!SROverlayWindow ||
                            SROverlayWindow.hidden) {

                            SRCreateOverlayWindow();
                        }

                        SRUpdateOverlay();
                    }];
        });
}

__attribute__((constructor))
static void SanneRealtimeInit(void)
{
    @autoreleasepool {

        SRLog =
            [NSMutableArray array];

        SRInstallObservers();

        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                SRInitialDiagnostic();

                SRCreateOverlayWindow();

                SRStartRefreshTimer();

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        1000 * NSEC_PER_MSEC),
                    dispatch_get_main_queue(),
                    ^{

                        SRCreateOverlayWindow();
                    });

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        3000 * NSEC_PER_MSEC),
                    dispatch_get_main_queue(),
                    ^{

                        SRCreateOverlayWindow();
                    });
            });
    }
}
