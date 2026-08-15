#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static NSMutableArray<NSString *> *SREvents;
static UILabel *SROverlayLabel = nil;
static UIWindow *SROverlayWindow = nil;

#pragma mark - Audio Helpers

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
    AVAudioSession *session = SRSession();

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

#pragma mark - Event Logging

static NSString *SRTime(void)
{
    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.dateFormat =
        @"HH:mm:ss.SSS";

    return [formatter stringFromDate:[NSDate date]];
}

static void SRRefreshOverlay(void);

static void SREvent(NSString *event)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (!SREvents) {
                SREvents = [NSMutableArray array];
            }

            NSString *line =
                [NSString stringWithFormat:
                    @"%@ %@",
                    SRTime(),
                    event];

            [SREvents addObject:line];

            if (SREvents.count > 12) {
                [SREvents removeObjectAtIndex:0];
            }

            NSLog(
                @"[SanneRealtime] %@",
                line);

            SRRefreshOverlay();
        });
}

#pragma mark - Overlay

static UIWindowScene *SRActiveWindowScene(void)
{
    for (UIScene *scene
         in UIApplication.sharedApplication.connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateForegroundActive) {

            return windowScene;
        }
    }

    return nil;
}

static void SRCreateOverlay(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (SROverlayWindow) {
                return;
            }

            UIWindowScene *scene =
                SRActiveWindowScene();

            if (!scene) {

                SREvent(
                    @"OVERLAY: waiting for window");

                return;
            }

            CGRect bounds =
                scene.screen.bounds;

            /*
             Small overlay.

             It does NOT receive touches, so the
             underlying Nobanny UI remains usable.
            */

            SROverlayWindow =
                [[UIWindow alloc]
                    initWithFrame:CGRectMake(
                        bounds.size.width - 292.0,
                        70.0,
                        282.0,
                        175.0)];

            SROverlayWindow.windowScene =
                scene;

            SROverlayWindow.windowLevel =
                UIWindowLevelAlert + 1;

            SROverlayWindow.backgroundColor =
                [UIColor clearColor];

            SROverlayWindow.userInteractionEnabled =
                NO;

            UIViewController *controller =
                [[UIViewController alloc] init];

            controller.view.backgroundColor =
                [UIColor clearColor];

            SROverlayWindow.rootViewController =
                controller;

            UIView *panel =
                [[UIView alloc] init];

            panel.frame =
                controller.view.bounds;

            panel.autoresizingMask =
                UIViewAutoresizingFlexibleWidth |
                UIViewAutoresizingFlexibleHeight;

            panel.backgroundColor =
                [[UIColor blackColor]
                    colorWithAlphaComponent:0.82];

            panel.layer.cornerRadius =
                12.0;

            panel.layer.masksToBounds =
                YES;

            [controller.view addSubview:panel];

            SROverlayLabel =
                [[UILabel alloc] init];

            SROverlayLabel.frame =
                CGRectInset(
                    panel.bounds,
                    10.0,
                    7.0);

            SROverlayLabel.autoresizingMask =
                UIViewAutoresizingFlexibleWidth |
                UIViewAutoresizingFlexibleHeight;

            SROverlayLabel.numberOfLines =
                0;

            SROverlayLabel.font =
                [UIFont monospacedSystemFontOfSize:
                    10.0
                    weight:UIFontWeightRegular];

            SROverlayLabel.textColor =
                UIColor.whiteColor;

            SROverlayLabel.adjustsFontSizeToFitWidth =
                NO;

            [panel addSubview:
                SROverlayLabel];

            SROverlayWindow.hidden =
                NO;

            [SROverlayWindow makeKeyAndVisible];

            /*
             Return key-window status to Nobanny.
             The overlay itself remains visible.
            */

            [scene.windows.firstObject
                makeKeyWindow];

            SREvent(
                @"OVERLAY: READY");

            SRRefreshOverlay();
        });
}

static void SRRefreshOverlay(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (!SROverlayLabel) {
                return;
            }

            AVAudioSession *session =
                SRSession();

            NSString *current =
                [NSString stringWithFormat:

                    @"SANNE REALTIME\n"
                     "P:%@  I:%@  M:%@\n"
                     "CAT:%@  IN:%ld  SR:%.0f\n"
                     "ROUTE: %@\n"
                     "--------------------\n",

                    SRPermission(),

                    session.isMicrophoneInjectionAvailable
                        ? @"YES"
                        : @"NO",

                    SRInjectionMode(
                        session.preferredMicrophoneInjectionMode),

                    session.category ?: @"NONE",

                    (long)session.inputNumberOfChannels,

                    session.sampleRate,

                    SRRoute()];

            NSMutableString *text =
                [NSMutableString stringWithString:current];

            if (SREvents.count == 0) {

                [text appendString:
                    @"Waiting for events..."];

            } else {

                for (NSString *event in SREvents) {

                    [text appendString:event];
                    [text appendString:@"\n"];
                }
            }

            SROverlayLabel.text =
                text;
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
            @"INJECTION EVENT: %@",
            available
                ? @"YES"
                : @"NO"]);

    SREvent(
        [NSString stringWithFormat:
            @"INPUT: %@/%ld",
            session.isInputAvailable
                ? @"YES"
                : @"NO",
            (long)session.inputNumberOfChannels]);

    SREvent(
        [NSString stringWithFormat:
            @"SESSION: %@/%@",
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
                    @"SPOKEN MODE: SUCCESS");

            } else {

                SREvent(
                    [NSString stringWithFormat:
                        @"SPOKEN MODE: FAILED %@",
                        error.localizedDescription
                            ?: @"UNKNOWN"]);
            }
        }
    }
}

#pragma mark - Route Changes

static void SRRouteChanged(
    NSNotification *notification)
{
    AVAudioSession *session =
        SRSession();

    NSNumber *reason =
        notification.userInfo[
            AVAudioSessionRouteChangeReasonKey];

    SREvent(
        [NSString stringWithFormat:
            @"ROUTE CHANGE: %ld",
            (long)reason.integerValue]);

    SREvent(
        [NSString stringWithFormat:
            @"ROUTE: %@",
            SRRoute()]);

    SREvent(
        [NSString stringWithFormat:
            @"INPUT: %@/%ld",
            session.isInputAvailable
                ? @"YES"
                : @"NO",
            (long)session.inputNumberOfChannels]);
}

#pragma mark - Interruptions

static void SRInterruptionChanged(
    NSNotification *notification)
{
    NSNumber *type =
        notification.userInfo[
            AVAudioSessionInterruptionTypeKey];

    if (type.integerValue ==
        AVAudioSessionInterruptionTypeBegan) {

        SREvent(
            @"INTERRUPTION: BEGAN");

    } else {

        SREvent(
            @"INTERRUPTION: ENDED");
    }
}

#pragma mark - App Lifecycle

static void SRAppActive(
    NSNotification *notification)
{
    AVAudioSession *session =
        SRSession();

    SREvent(
        [NSString stringWithFormat:
            @"APP ACTIVE: I=%@ C=%@",
            session.isMicrophoneInjectionAvailable
                ? @"YES"
                : @"NO",
            session.category ?: @"NONE"]);
}

static void SRAppInactive(
    NSNotification *notification)
{
    SREvent(
        @"APP RESIGN ACTIVE");
}

#pragma mark - Observer Installation

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

            SRAppActive(notification);
        }];

    [center
        addObserverForName:
            UIApplicationWillResignActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SRAppInactive(notification);
        }];

    SREvent(
        @"OBSERVERS INSTALLED");
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
                    @"NO MIC TAP");

                SREvent(
                    @"NO SESSION ACTIVATION");

                SRCreateOverlay();

                /*
                 Retry overlay creation in case the host
                 application's window is not ready yet.
                */

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        1500 * NSEC_PER_MSEC),
                    dispatch_get_main_queue(),
                    ^{

                        if (!SROverlayWindow) {
                            SRCreateOverlay();
                        }
                    });

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        3000 * NSEC_PER_MSEC),
                    dispatch_get_main_queue(),
                    ^{

                        if (!SROverlayWindow) {
                            SRCreateOverlay();
                        }
                    });
            });
    }
}
