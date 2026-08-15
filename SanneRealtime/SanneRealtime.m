#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static NSMutableArray<NSString *> *SRLog = nil;

static UIWindow *SROverlayWindow = nil;
static UILabel *SRLabel = nil;
static NSTimer *SRRefreshTimer = nil;

#pragma mark - Logging

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

    if (SRLog.count > 120) {
        [SRLog removeObjectAtIndex:0];
    }

    NSLog(@"[SanneRealtime] %@", line);

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (!SRLabel) {
                return;
            }

            NSUInteger start =
                SRLog.count > 13
                ? SRLog.count - 13
                : 0;

            NSArray<NSString *> *lines =
                [SRLog subarrayWithRange:
                    NSMakeRange(
                        start,
                        SRLog.count - start)];

            SRLabel.text =
                [lines componentsJoinedByString:@"\n"];
        });
}

#pragma mark - Permission

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

        NSString *before =
            SRPermission();

        SRLogLine(
            [NSString stringWithFormat:
                @"INJECTION PERMISSION BEFORE:%@",
                before]);

        if (![before isEqualToString:@"UNDETERMINED"]) {

            SRLogLine(
                @"PERMISSION ALREADY RESOLVED");

            return;
        }

        SRLogLine(
            @"REQUESTING MICROPHONE INJECTION PERMISSION");

        /*
         IMPORTANT:

         This is Apple's documented permission request.

         We do NOT:
         - activate AVAudioSession
         - create AVAudioEngine
         - create a microphone tap
         - generate audio
         - inject audio

         This only asks iOS for permission.
        */

        [AVAudioApplication
            requestMicrophoneInjectionPermissionWithCompletionHandler:
            ^(AVAudioApplicationMicrophoneInjectionPermission permission) {

                NSString *result;

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

                        /*
                         Do not activate or alter the audio
                         session here.
                        */
                    });
            }];
    }
    else {

        SRLogLine(
            @"MICROPHONE INJECTION REQUIRES iOS 18.2+");
    }
}

#pragma mark - Audio Diagnostics

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

    return [NSString stringWithFormat:
        @"IN:%@ OUT:%@",
        input,
        output];
}

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
            @"CAT:%@",
            SRCategory(session)]);

    SRLogLine(
        [NSString stringWithFormat:
            @"MODE:%@",
            SRMode(session)]);

    SRLogLine(
        [NSString stringWithFormat:
            @"INPUT:%@",
            session.isInputAvailable
                ? @"YES"
                : @"NO"]);

    SRLogLine(
        [NSString stringWithFormat:
            @"CHANNELS:%ld",
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

#pragma mark - Overlay

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

static void SRUpdateOverlay(void);

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
             Never become key window.
             Never consume touches.
            */

            SROverlayWindow.userInteractionEnabled =
                NO;

            SROverlayWindow.windowLevel =
                UIWindowLevelNormal + 1.0;

            SROverlayWindow.hidden =
                NO;

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
                            350.0)];

            panel.backgroundColor =
                [UIColor colorWithWhite:0.0
                                  alpha:0.88];

            panel.layer.cornerRadius =
                15.0;

            panel.clipsToBounds =
                YES;

            panel.userInteractionEnabled =
                NO;

            [controller.view addSubview:panel];

            SRLabel =
                [[UILabel alloc]
                    initWithFrame:
                        CGRectMake(
                            12.0,
                            10.0,
                            346.0,
                            330.0)];

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

            SRLabel.userInteractionEnabled =
                NO;

            [panel addSubview:SRLabel];

            SRLogLine(
                @"INDEPENDENT OVERLAY CREATED");

            SRUpdateOverlay();
        });
}

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

            NSString *appState =
                state == UIApplicationStateActive
                ? @"ACTIVE"
                : state == UIApplicationStateInactive
                    ? @"INACTIVE"
                    : @"BACKGROUND";

            NSUInteger start =
                SRLog.count > 13
                ? SRLog.count - 13
                : 0;

            NSArray<NSString *> *lines =
                [SRLog subarrayWithRange:
                    NSMakeRange(
                        start,
                        SRLog.count - start)];

            NSString *events =
                [lines componentsJoinedByString:@"\n"];

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
                [header stringByAppendingString:
                    events];

            SROverlayWindow.hidden =
                NO;
        });
}

#pragma mark - Notifications

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

    SRUpdateOverlay();
}

static void SRInjectionChanged(
    NSNotification *notification)
{
    SRLogLine(
        @"INJECTION CAPABILITY CHANGED");

    SRLogLine(
        [NSString stringWithFormat:
            @"INJECTION:%@",
            SRInjectionState()]);

    SRLogLine(
        [NSString stringWithFormat:
            @"PERMISSION:%@",
            SRPermission()]);

    SRLogSession(
        @"INJECTION_EVENT");

    SRUpdateOverlay();
}

#pragma mark - Observer Installation

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
        UIApplicationDidBecomeActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRAppActive(notification);
        }];

    [center addObserverForName:
        UIApplicationWillResignActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRAppInactive(notification);
        }];

    [center addObserverForName:
        UIApplicationWillEnterForegroundNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRForeground(notification);
        }];

    [center addObserverForName:
        UIApplicationDidEnterBackgroundNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRBackground(notification);
        }];

    if (@available(iOS 18.2, *)) {

        [center addObserverForName:
            AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:
            ^(NSNotification *notification) {

                SRInjectionChanged(notification);
            }];
    }

    SRLogLine(
        @"OBSERVERS INSTALLED");
}

#pragma mark - Initial State

static void SRInitialState(void)
{
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    SRLogLine(
        @"================================");

    SRLogLine(
        @"SANNE REALTIME - PERMISSION TEST");

    SRLogLine(
        @"================================");

    SRLogLine(
        @"NO AVAUDIOENGINE");

    SRLogLine(
        @"NO MICROPHONE TAP");

    SRLogLine(
        @"NO AUDIO GENERATION");

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

    SRLogSession(
        @"INITIAL");
}

#pragma mark - Refresh

static void SRStartTimer(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (SRRefreshTimer) {
                [SRRefreshTimer invalidate];
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

#pragma mark - Constructor

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
                 Request permission after the UI exists,
                 so the system dialog can appear normally.
                */

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        1200 * NSEC_PER_MSEC),
                    dispatch_get_main_queue(),
                    ^{

                        SRLogLine(
                            @"STARTING PERMISSION REQUEST");

                        SRRequestInjectionPermission();

                        SRUpdateOverlay();
                    });
            });
    }
}
