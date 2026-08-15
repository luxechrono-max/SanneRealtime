#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static NSMutableArray<NSString *> *SREvents = nil;
static UILabel *SRLabel = nil;
static UIView *SRPanel = nil;
static UIWindow *SRHostWindow = nil;

#pragma mark - Audio

static AVAudioSession *SRSession(void)
{
    return [AVAudioSession sharedInstance];
}

static NSString *SRPermission(void)
{
    if (@available(iOS 18.2, *)) {

        AVAudioApplicationMicrophoneInjectionPermission p =
            [AVAudioApplication sharedInstance]
                .microphoneInjectionPermission;

        switch (p) {

            case AVAudioApplicationMicrophoneInjectionPermissionGranted:
                return @"GRANTED";

            case AVAudioApplicationMicrophoneInjectionPermissionDenied:
                return @"DENIED";

            case AVAudioApplicationMicrophoneInjectionPermissionUndetermined:
                return @"UNDETERMINED";

            case AVAudioApplicationMicrophoneInjectionPermissionServiceDisabled:
                return @"SERVICE OFF";
        }
    }

    return @"UNAVAILABLE";
}

static NSString *SRInjectionMode(
    AVAudioSessionMicrophoneInjectionMode mode)
{
    switch (mode) {

        case AVAudioSessionMicrophoneInjectionModeNone:
            return @"NONE";

        case AVAudioSessionMicrophoneInjectionModeSpokenAudio:
            return @"SPOKEN";
    }

    return @"UNKNOWN";
}

static NSString *SRRoute(void)
{
    AVAudioSession *session =
        SRSession();

    AVAudioSessionRouteDescription *route =
        session.currentRoute;

    NSString *input = @"NONE";
    NSString *output = @"NONE";

    if (route.inputs.count > 0) {

        AVAudioSessionPortDescription *port =
            route.inputs.firstObject;

        input =
            port.portName ?: @"UNKNOWN";
    }

    if (route.outputs.count > 0) {

        AVAudioSessionPortDescription *port =
            route.outputs.firstObject;

        output =
            port.portName ?: @"UNKNOWN";
    }

    return [NSString stringWithFormat:
        @"IN:%@ OUT:%@",
        input,
        output];
}

#pragma mark - Time

static NSString *SRTime(void)
{
    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.dateFormat =
        @"HH:mm:ss.SSS";

    return [formatter stringFromDate:[NSDate date]];
}

#pragma mark - Existing Window

static UIWindow *SRFindHostWindow(void)
{
    UIApplication *application =
        [UIApplication sharedApplication];

    UIWindow *fallback = nil;

    for (UIScene *scene
         in application.connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateUnattached) {
            continue;
        }

        for (UIWindow *window
             in windowScene.windows) {

            if (window.hidden) {
                continue;
            }

            if (window.isKeyWindow) {
                return window;
            }

            if (!fallback &&
                window.windowLevel ==
                    UIWindowLevelNormal) {

                fallback = window;
            }
        }
    }

    return fallback;
}

#pragma mark - Overlay Text

static void SRRefreshOverlay(void);

static void SREvent(NSString *event)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (!SREvents) {
                SREvents =
                    [NSMutableArray array];
            }

            NSString *line =
                [NSString stringWithFormat:
                    @"%@ %@",
                    SRTime(),
                    event];

            [SREvents addObject:line];

            if (SREvents.count > 10) {
                [SREvents removeObjectAtIndex:0];
            }

            NSLog(
                @"[SanneRealtime] %@",
                line);

            SRRefreshOverlay();
        });
}

#pragma mark - Overlay Creation

static void SRCreateOverlay(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (SRPanel &&
                SRPanel.superview) {

                SRRefreshOverlay();
                return;
            }

            UIWindow *window =
                SRFindHostWindow();

            if (!window) {
                return;
            }

            SRHostWindow =
                window;

            UIViewController *controller =
                window.rootViewController;

            if (!controller) {
                return;
            }

            /*
             Put the diagnostic panel directly into the
             existing host window.

             It is deliberately non-interactive.
            */

            SRPanel =
                [[UIView alloc] init];

            SRPanel.translatesAutoresizingMaskIntoConstraints =
                NO;

            SRPanel.backgroundColor =
                [[UIColor blackColor]
                    colorWithAlphaComponent:0.86];

            SRPanel.layer.cornerRadius =
                10.0;

            SRPanel.layer.masksToBounds =
                YES;

            SRPanel.userInteractionEnabled =
                NO;

            [window addSubview:SRPanel];

            CGFloat width = 275.0;
            CGFloat height = 145.0;

            [NSLayoutConstraint activateConstraints:@[

                [SRPanel.topAnchor
                    constraintEqualToAnchor:
                        window.safeAreaLayoutGuide.topAnchor
                    constant:8.0],

                [SRPanel.trailingAnchor
                    constraintEqualToAnchor:
                        window.trailingAnchor
                    constant:-8.0],

                [SRPanel.widthAnchor
                    constraintEqualToConstant:width],

                [SRPanel.heightAnchor
                    constraintEqualToConstant:height]
            ]];

            SRLabel =
                [[UILabel alloc] init];

            SRLabel.translatesAutoresizingMaskIntoConstraints =
                NO;

            SRLabel.numberOfLines =
                0;

            SRLabel.font =
                [UIFont monospacedSystemFontOfSize:
                    9.5
                    weight:UIFontWeightRegular];

            SRLabel.textColor =
                UIColor.whiteColor;

            SRLabel.backgroundColor =
                UIColor.clearColor;

            SRLabel.userInteractionEnabled =
                NO;

            [SRPanel addSubview:SRLabel];

            [NSLayoutConstraint activateConstraints:@[

                [SRLabel.topAnchor
                    constraintEqualToAnchor:
                        SRPanel.topAnchor
                    constant:7.0],

                [SRLabel.leadingAnchor
                    constraintEqualToAnchor:
                        SRPanel.leadingAnchor
                    constant:8.0],

                [SRLabel.trailingAnchor
                    constraintEqualToAnchor:
                        SRPanel.trailingAnchor
                    constant:-8.0],

                [SRLabel.bottomAnchor
                    constraintEqualToAnchor:
                        SRPanel.bottomAnchor
                    constant:-7.0]
            ]];

            [window bringSubviewToFront:SRPanel];

            SREvent(
                @"OVERLAY ATTACHED TO HOST WINDOW");

            SRRefreshOverlay();
        });
}

#pragma mark - Overlay Refresh

static void SRRefreshOverlay(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (!SRLabel) {
                return;
            }

            AVAudioSession *session =
                SRSession();

            NSMutableString *text =
                [NSMutableString string];

            [text appendFormat:
                @"SANNE REALTIME\n"];

            [text appendFormat:
                @"P:%@  I:%@  M:%@\n",
                SRPermission(),
                session.isMicrophoneInjectionAvailable
                    ? @"YES"
                    : @"NO",
                SRInjectionMode(
                    session.preferredMicrophoneInjectionMode)];

            [text appendFormat:
                @"CAT:%@  MODE:%@\n",
                session.category ?: @"NONE",
                session.mode ?: @"NONE"];

            [text appendFormat:
                @"INPUT:%@  CH:%ld  SR:%.0f\n",
                session.isInputAvailable
                    ? @"YES"
                    : @"NO",
                (long)session.inputNumberOfChannels,
                session.sampleRate];

            [text appendFormat:
                @"ROUTE:%@\n",
                SRRoute()];

            [text appendString:
                @"----------------------\n"];

            if (SREvents.count == 0) {

                [text appendString:
                    @"Waiting for events..."];

            } else {

                for (NSString *event
                     in SREvents) {

                    [text appendString:event];
                    [text appendString:@"\n"];
                }
            }

            SRLabel.text =
                text;

            if (SRPanel &&
                SRPanel.superview) {

                [SRPanel.superview
                    bringSubviewToFront:SRPanel];
            }
        });
}

#pragma mark - Injection Capability

static void SRInjectionCapabilityChanged(
    NSNotification *notification)
{
    AVAudioSession *session =
        SRSession();

    NSNumber *reported =
        notification.userInfo[
            AVAudioSessionMicrophoneInjectionIsAvailableKey
        ];

    BOOL available =
        session.isMicrophoneInjectionAvailable;

    if (reported) {
        available =
            reported.boolValue;
    }

    SREvent(
        [NSString stringWithFormat:
            @"INJECTION EVENT:%@",
            available
                ? @"YES"
                : @"NO"]);

    SREvent(
        [NSString stringWithFormat:
            @"INPUT:%@/%ld",
            session.isInputAvailable
                ? @"YES"
                : @"NO",
            (long)session.inputNumberOfChannels]);

    SREvent(
        [NSString stringWithFormat:
            @"SESSION:%@/%@",
            session.category ?: @"NONE",
            session.mode ?: @"NONE"]);

    if (available) {

        if (@available(iOS 18.2, *)) {

            NSError *error = nil;

            BOOL success =
                [session
                    setPreferredMicrophoneInjectionMode:
                        AVAudioSessionMicrophoneInjectionModeSpokenAudio
                    error:&error];

            if (success) {

                SREvent(
                    @"SPOKEN MODE:SUCCESS");

            } else {

                SREvent(
                    [NSString stringWithFormat:
                        @"SPOKEN MODE:FAILED:%@",
                        error.localizedDescription
                            ?: @"UNKNOWN"]);
            }
        }
    }
}

#pragma mark - Route

static void SRRouteChanged(
    NSNotification *notification)
{
    NSNumber *reason =
        notification.userInfo[
            AVAudioSessionRouteChangeReasonKey];

    SREvent(
        [NSString stringWithFormat:
            @"ROUTE CHANGE:%ld",
            (long)reason.integerValue]);

    SREvent(
        [NSString stringWithFormat:
            @"ROUTE:%@",
            SRRoute()]);
}

#pragma mark - Interruption

static void SRInterruptionChanged(
    NSNotification *notification)
{
    NSNumber *type =
        notification.userInfo[
            AVAudioSessionInterruptionTypeKey];

    if (type.integerValue ==
        AVAudioSessionInterruptionTypeBegan) {

        SREvent(
            @"INTERRUPTION:BEGAN");

    } else {

        SREvent(
            @"INTERRUPTION:ENDED");
    }
}

#pragma mark - Application Lifecycle

static void SRApplicationActive(
    NSNotification *notification)
{
    SREvent(
        @"APPLICATION:ACTIVE");
}

static void SRApplicationInactive(
    NSNotification *notification)
{
    SREvent(
        @"APPLICATION:INACTIVE");
}

#pragma mark - Observers

static void SRInstallObservers(void)
{
    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    [center
        addObserverForName:
            AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRInjectionCapabilityChanged(
                notification);
        }];

    [center
        addObserverForName:
            AVAudioSessionRouteChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRRouteChanged(notification);
        }];

    [center
        addObserverForName:
            AVAudioSessionInterruptionNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRInterruptionChanged(
                notification);
        }];

    [center
        addObserverForName:
            UIApplicationDidBecomeActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRApplicationActive(
                notification);
        }];

    [center
        addObserverForName:
            UIApplicationWillResignActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRApplicationInactive(
                notification);
        }];
}

#pragma mark - Constructor

__attribute__((constructor))
static void SanneRealtimeInit(void)
{
    @autoreleasepool {

        SREvents =
            [NSMutableArray array];

        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                SRInstallObservers();

                SREvent(
                    @"DIAGNOSTIC STARTED");

                SREvent(
                    @"PASSIVE AUDIO MODE");

                SREvent(
                    @"NO AVAUDIOENGINE");

                SREvent(
                    @"NO MICROPHONE TAP");

                SREvent(
                    @"NO SESSION ACTIVATION");

                SRCreateOverlay();

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        1000 * NSEC_PER_MSEC),
                    dispatch_get_main_queue(),
                    ^{

                        SRCreateOverlay();
                    });

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        2500 * NSEC_PER_MSEC),
                    dispatch_get_main_queue(),
                    ^{

                        SRCreateOverlay();
                    });
            });
    }
}
