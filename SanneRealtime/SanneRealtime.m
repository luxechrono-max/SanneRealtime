#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

#pragma mark ============================================================
#pragma mark Forward Declarations
#pragma mark ============================================================

static void SRUpdateOverlay(void);
static void SRCreateOverlay(void);
static void SRStartTimer(void);
static void SRRequestInjectionPermission(void);
static void SRInitialState(void);
static void SRInstallObservers(void);
static void SRLogSession(NSString *reason);

#pragma mark ============================================================
#pragma mark Globals
#pragma mark ============================================================

static NSMutableArray<NSString *> *SRLog = nil;

static UIWindow *SROverlayWindow = nil;
static UILabel *SRLabel = nil;
static NSTimer *SRRefreshTimer = nil;

#pragma mark ============================================================
#pragma mark Time / Logging
#pragma mark ============================================================

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
        [NSString stringWithFormat:
            @"[%@] %@",
            SRNow(),
            text];

    [SRLog addObject:line];

    if (SRLog.count > 150) {
        [SRLog removeObjectAtIndex:0];
    }

    NSLog(@"[SanneRealtime] %@", line);

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SRUpdateOverlay();
        });
}

#pragma mark ============================================================
#pragma mark Permission
#pragma mark ============================================================

static NSString *SRPermission(void)
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
                return @"SERVICE_DISABLED";
        }
    }

    return @"UNAVAILABLE";
}

static void SRRequestInjectionPermission(void)
{
    if (@available(iOS 18.2, *)) {

        NSString *current =
            SRPermission();

        SRLogLine(
            [NSString stringWithFormat:
                @"PERMISSION BEFORE:%@",
                current]);

        if (![current isEqualToString:@"UNDETERMINED"]) {

            SRLogLine(
                @"PERMISSION ALREADY RESOLVED");

            return;
        }

        SRLogLine(
            @"REQUESTING MICROPHONE INJECTION PERMISSION");

        /*
         Apple's documented class method.

         This does NOT:
         - activate an audio session
         - create AVAudioEngine
         - create a microphone tap
         - generate audio
         - inject audio
        */

        [AVAudioApplication
            requestMicrophoneInjectionPermissionWithCompletionHandler:
            ^(AVAudioApplicationMicrophoneInjectionPermission permission) {

                NSString *result = @"UNKNOWN";

                switch (permission) {

                    case AVAudioApplicationMicrophoneInjectionPermissionGranted:
                        result = @"GRANTED";
                        break;

                    case AVAudioApplicationMicrophoneInjectionPermissionDenied:
                        result = @"DENIED";
                        break;

                    case AVAudioApplicationMicrophoneInjectionPermissionUndetermined:
                        result = @"UNDETERMINED";
                        break;

                    case AVAudioApplicationMicrophoneInjectionPermissionServiceDisabled:
                        result = @"SERVICE_DISABLED";
                        break;
                }

                SRLogLine(
                    [NSString stringWithFormat:
                        @"PERMISSION RESULT:%@",
                        result]);

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        SRUpdateOverlay();
                    });
            }];
    }
    else {

        SRLogLine(
            @"MICROPHONE INJECTION REQUIRES iOS 18.2+");
    }
}

#pragma mark ============================================================
#pragma mark Audio State
#pragma mark ============================================================

static NSString *SRCategory(
    AVAudioSession *session)
{
    if (session.category) {
        return session.category;
    }

    return @"<none>";
}

static NSString *SRMode(
    AVAudioSession *session)
{
    if (session.mode) {
        return session.mode;
    }

    return @"<none>";
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

#pragma mark ============================================================
#pragma mark Route
#pragma mark ============================================================

static NSString *SRRoute(void)
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

        NSString *name =
            port.portName ?: @"?";

        NSString *type =
            port.portType ?: @"?";

        [inputs addObject:
            [NSString stringWithFormat:
                @"%@/%@",
                name,
                type]];
    }

    for (AVAudioSessionPortDescription *port
         in route.outputs) {

        NSString *name =
            port.portName ?: @"?";

        NSString *type =
            port.portType ?: @"?";

        [outputs addObject:
            [NSString stringWithFormat:
                @"%@/%@",
                name,
                type]];
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

#pragma mark ============================================================
#pragma mark Session Report
#pragma mark ============================================================

static void SRLogSession(
    NSString *reason)
{
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    SRLogLine(
        [NSString stringWithFormat:
            @"SESSION:%@",
            reason]);

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
            @"INJECTION:%@",
            SRInjectionState()]);

    SRLogLine(
        [NSString stringWithFormat:
            @"ROUTE:%@",
            SRRoute()]);
}

#pragma mark ============================================================
#pragma mark Active Scene
#pragma mark ============================================================

static UIWindowScene *SRActiveScene(void)
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

#pragma mark ============================================================
#pragma mark Overlay
#pragma mark ============================================================

static void SRCreateOverlay(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            UIWindowScene *scene =
                SRActiveScene();

            if (!scene) {
                return;
            }

            if (SROverlayWindow &&
                SROverlayWindow.windowScene == scene &&
                !SROverlayWindow.hidden) {

                SRUpdateOverlay();

                return;
            }

            if (SROverlayWindow) {

                SROverlayWindow.hidden =
                    YES;

                SROverlayWindow =
                    nil;

                SRLabel =
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
             Important:
             This window never becomes key.
             It doesn't receive touches.
            */

            SROverlayWindow.userInteractionEnabled =
                NO;

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
                            18.0,
                            60.0,
                            370.0,
                            370.0)];

            panel.backgroundColor =
                [UIColor
                    colorWithWhite:0.0
                    alpha:0.88];

            panel.layer.cornerRadius =
                15.0;

            panel.clipsToBounds =
                YES;

            panel.userInteractionEnabled =
                NO;

            [controller.view
                addSubview:panel];

            SRLabel =
                [[UILabel alloc]
                    initWithFrame:
                        CGRectMake(
                            12.0,
                            10.0,
                            346.0,
                            350.0)];

            SRLabel.textColor =
                UIColor.whiteColor;

            SRLabel.backgroundColor =
                UIColor.clearColor;

            SRLabel.font =
                [UIFont
                    monospacedSystemFontOfSize:
                        11.0
                    weight:UIFontWeightRegular];

            SRLabel.numberOfLines =
                0;

            SRLabel.lineBreakMode =
                NSLineBreakByClipping;

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

#pragma mark ============================================================
#pragma mark Overlay Update
#pragma mark ============================================================

static void SRUpdateOverlay(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (!SROverlayWindow ||
                !SRLabel) {

                return;
            }

            AVAudioSession *session =
                [AVAudioSession sharedInstance];

            UIApplicationState state =
                [UIApplication sharedApplication]
                    .applicationState;

            NSString *appState;

            switch (state) {

                case UIApplicationStateActive:
                    appState = @"ACTIVE";
                    break;

                case UIApplicationStateInactive:
                    appState = @"INACTIVE";
                    break;

                case UIApplicationStateBackground:
                    appState = @"BACKGROUND";
                    break;

                default:
                    appState = @"UNKNOWN";
                    break;
            }

            NSUInteger start =
                SRLog.count > 14
                    ? SRLog.count - 14
                    : 0;

            NSArray<NSString *> *lines =
                [SRLog
                    subarrayWithRange:
                        NSMakeRange(
                            start,
                            SRLog.count - start)];

            NSString *events =
                [lines
                    componentsJoinedByString:@"\n"];

            NSString *header =
                [NSString stringWithFormat:
                    @"SANNE REALTIME\n"
                     "P:%@  INJ:%@\n"
                     "CAT:%@\n"
                     "MODE:%@\n"
                     "INPUT:%@ CH:%ld\n"
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
                    SRRoute(),
                    appState];

            SRLabel.text =
                [header
                    stringByAppendingString:
                        events];

            SROverlayWindow.hidden =
                NO;
        });
}

#pragma mark ============================================================
#pragma mark Route Notification
#pragma mark ============================================================

static void SRRouteChanged(
    NSNotification *notification)
{
    NSNumber *reason =
        notification.userInfo[
            AVAudioSessionRouteChangeReasonKey];

    SRLogLine(
        [NSString stringWithFormat:
            @"ROUTE CHANGE:%ld",
            reason
                ? (long)reason.unsignedIntegerValue
                : -1]);

    SRLogLine(
        [NSString stringWithFormat:
            @"ROUTE:%@",
            SRRoute()]);

    SRLogSession(
        @"AFTER_ROUTE_CHANGE");

    SRUpdateOverlay();
}

#pragma mark ============================================================
#pragma mark Interruption Notification
#pragma mark ============================================================

static void SRInterruption(
    NSNotification *notification)
{
    NSNumber *type =
        notification.userInfo[
            AVAudioSessionInterruptionTypeKey];

    if (type &&
        type.unsignedIntegerValue ==
            AVAudioSessionInterruptionTypeBegan) {

        SRLogLine(
            @"INTERRUPTION:BEGAN");

    } else {

        SRLogLine(
            @"INTERRUPTION:ENDED");
    }

    SRLogSession(
        @"AFTER_INTERRUPTION");

    SRUpdateOverlay();
}

#pragma mark ============================================================
#pragma mark Application Notifications
#pragma mark ============================================================

static void SRAppActive(
    NSNotification *notification)
{
    SRLogLine(
        @"APPLICATION:ACTIVE");

    SRLogSession(
        @"APPLICATION_ACTIVE");

    SRCreateOverlay();
}

static void SRAppInactive(
    NSNotification *notification)
{
    SRLogLine(
        @"APPLICATION:INACTIVE");

    SRLogSession(
        @"APPLICATION_INACTIVE");

    SRUpdateOverlay();
}

static void SRForeground(
    NSNotification *notification)
{
    SRLogLine(
        @"APPLICATION:FOREGROUND");

    SRCreateOverlay();
}

static void SRBackground(
    NSNotification *notification)
{
    SRLogLine(
        @"APPLICATION:BACKGROUND");

    SRLogLine(
        @"APPLICATION ENTERED BACKGROUND");

    SRUpdateOverlay();
}

#pragma mark ============================================================
#pragma mark Injection Capability Notification
#pragma mark ============================================================

static void SRInjectionChanged(
    NSNotification *notification)
{
    NSNumber *reported =
        notification.userInfo[
            AVAudioSessionMicrophoneInjectionIsAvailableKey];

    NSString *reportedValue =
        reported
            ? (reported.boolValue
                ? @"YES"
                : @"NO")
            : @"UNKNOWN";

    SRLogLine(
        @"================================");

    SRLogLine(
        @"INJECTION CAPABILITY CHANGED");

    SRLogLine(
        [NSString stringWithFormat:
            @"NOTIFICATION VALUE:%@",
            reportedValue]);

    SRLogLine(
        [NSString stringWithFormat:
            @"CURRENT INJECTION:%@",
            SRInjectionState()]);

    SRLogLine(
        [NSString stringWithFormat:
            @"PERMISSION:%@",
            SRPermission()]);

    SRLogSession(
        @"INJECTION_EVENT");

    SRUpdateOverlay();
}

#pragma mark ============================================================
#pragma mark Observer Installation
#pragma mark ============================================================

static void SRInstallObservers(void)
{
    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    [center
        addObserverForName:
            AVAudioSessionRouteChangeNotification
        object:nil
        queue:
            [NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRRouteChanged(notification);
        }];

    [center
        addObserverForName:
            AVAudioSessionInterruptionNotification
        object:nil
        queue:
            [NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRInterruption(notification);
        }];

    [center
        addObserverForName:
            UIApplicationDidBecomeActiveNotification
        object:nil
        queue:
            [NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRAppActive(notification);
        }];

    [center
        addObserverForName:
            UIApplicationWillResignActiveNotification
        object:nil
        queue:
            [NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRAppInactive(notification);
        }];

    [center
        addObserverForName:
            UIApplicationWillEnterForegroundNotification
        object:nil
        queue:
            [NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRForeground(notification);
        }];

    [center
        addObserverForName:
            UIApplicationDidEnterBackgroundNotification
        object:nil
        queue:
            [NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRBackground(notification);
        }];

    if (@available(iOS 18.2, *)) {

        [center
            addObserverForName:
                AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
            ^(NSNotification *notification) {

                SRInjectionChanged(notification);
            }];
    }

    SRLogLine(
        @"OBSERVERS INSTALLED");
}

#pragma mark ============================================================
#pragma mark Initial Diagnostic
#pragma mark ============================================================

static void SRInitialState(void)
{
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    SRLogLine(
        @"================================");

    SRLogLine(
        @"SANNE REALTIME - DIAGNOSTIC");

    SRLogLine(
        @"================================");

    SRLogLine(
        @"NO AUDIO GENERATION");

    SRLogLine(
        @"NO AVAUDIOENGINE");

    SRLogLine(
        @"NO MICROPHONE TAP");

    SRLogLine(
        @"NO SESSION ACTIVATION");

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
            SRRoute()]);
}

#pragma mark ============================================================
#pragma mark Timer
#pragma mark ============================================================

static void SRStartTimer(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (SRRefreshTimer) {

                [SRRefreshTimer invalidate];

                SRRefreshTimer =
                    nil;
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

                            SRCreateOverlay();
                        }

                        SRUpdateOverlay();
                    }];
        });
}

#pragma mark ============================================================
#pragma mark Constructor
#pragma mark ============================================================

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

                SRInitialState();

                SRCreateOverlay();

                SRStartTimer();

                /*
                 Give the host UI a moment to initialize
                 before displaying Apple's permission dialog.
                */

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        1200 * NSEC_PER_MSEC),
                    dispatch_get_main_queue(),
                    ^{

                        SRLogLine(
                            @"STARTING INJECTION PERMISSION REQUEST");

                        SRRequestInjectionPermission();

                        SRUpdateOverlay();
                    });
            });
    }
}
