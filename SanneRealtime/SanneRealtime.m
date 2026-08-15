#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static UIWindow *SRWindow = nil;
static UIViewController *SRController = nil;
static UITextView *SRTextView = nil;
static NSMutableArray<NSString *> *SREvents = nil;

static NSString *SRTime(void)
{
    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.dateFormat = @"HH:mm:ss.SSS";

    return [formatter stringFromDate:[NSDate date]];
}

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
                return @"SERVICE DISABLED";
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
            return @"SPOKEN AUDIO";
    }

    return @"UNKNOWN";
}

static NSString *SRRouteDescription(void)
{
    AVAudioSession *session = SRSession();

    AVAudioSessionRouteDescription *route =
        session.currentRoute;

    NSMutableArray<NSString *> *inputs =
        [NSMutableArray array];

    for (AVAudioSessionPortDescription *port
         in route.inputs) {

        [inputs addObject:
            [NSString stringWithFormat:
                @"%@ (%@)",
                port.portName ?: @"?",
                port.portType ?: @"?"]];
    }

    NSMutableArray<NSString *> *outputs =
        [NSMutableArray array];

    for (AVAudioSessionPortDescription *port
         in route.outputs) {

        [outputs addObject:
            [NSString stringWithFormat:
                @"%@ (%@)",
                port.portName ?: @"?",
                port.portType ?: @"?"]];
    }

    NSString *inputText =
        inputs.count
            ? [inputs componentsJoinedByString:@", "]
            : @"NONE";

    NSString *outputText =
        outputs.count
            ? [outputs componentsJoinedByString:@", "]
            : @"NONE";

    return [NSString stringWithFormat:
        @"INPUT ROUTE: %@\nOUTPUT ROUTE: %@",
        inputText,
        outputText];
}

static NSString *SRCurrentState(void)
{
    AVAudioSession *session = SRSession();

    return [NSString stringWithFormat:
        @"PERMISSION: %@\n"
         "INJECTION AVAILABLE: %@\n"
         "PREFERRED INJECTION MODE: %@\n"
         "CATEGORY: %@\n"
         "MODE: %@\n"
         "INPUT AVAILABLE: %@\n"
         "INPUT CHANNELS: %ld\n"
         "SAMPLE RATE: %.2f\n"
         "INPUT LATENCY: %.6f\n"
         "OUTPUT LATENCY: %.6f\n"
         "%@",

        SRPermission(),

        session.isMicrophoneInjectionAvailable
            ? @"YES"
            : @"NO",

        SRInjectionMode(
            session.preferredMicrophoneInjectionMode),

        session.category ?: @"NONE",

        session.mode ?: @"NONE",

        session.isInputAvailable
            ? @"YES"
            : @"NO",

        (long)session.inputNumberOfChannels,

        session.sampleRate,

        session.inputLatency,

        session.outputLatency,

        SRRouteDescription()];
}

static void SRRefreshScreen(void);

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
                    @"[%@] %@",
                    SRTime(),
                    event];

            [SREvents addObject:line];

            if (SREvents.count > 40) {
                [SREvents removeObjectAtIndex:0];
            }

            NSLog(@"[SanneRealtime] %@", line);

            SRRefreshScreen();
        });
}

static void SRCreateScreen(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (SRWindow) {
                return;
            }

            UIWindowScene *windowScene = nil;

            for (UIScene *scene
                 in UIApplication.sharedApplication.connectedScenes) {

                if (![scene isKindOfClass:[UIWindowScene class]]) {
                    continue;
                }

                UIWindowScene *candidate =
                    (UIWindowScene *)scene;

                if (candidate.activationState ==
                    UISceneActivationStateForegroundActive) {

                    windowScene = candidate;
                    break;
                }
            }

            if (!windowScene) {

                for (UIScene *scene
                     in UIApplication.sharedApplication.connectedScenes) {

                    if ([scene isKindOfClass:[UIWindowScene class]]) {
                        windowScene = (UIWindowScene *)scene;
                        break;
                    }
                }
            }

            if (!windowScene) {
                return;
            }

            SRWindow =
                [[UIWindow alloc]
                    initWithWindowScene:windowScene];

            SRWindow.windowLevel =
                UIWindowLevelAlert + 1;

            SRWindow.backgroundColor =
                [UIColor systemBackgroundColor];

            SRController =
                [[UIViewController alloc] init];

            SRController.view.backgroundColor =
                [UIColor systemBackgroundColor];

            SRWindow.rootViewController =
                SRController;

            UILabel *title =
                [[UILabel alloc] init];

            title.translatesAutoresizingMaskIntoConstraints = NO;

            title.text =
                @"SANNE REALTIME";

            title.font =
                [UIFont boldSystemFontOfSize:24.0];

            title.textAlignment =
                NSTextAlignmentCenter;

            [SRController.view addSubview:title];

            UILabel *subtitle =
                [[UILabel alloc] init];

            subtitle.translatesAutoresizingMaskIntoConstraints = NO;

            subtitle.text =
                @"Persistent Audio Diagnostic";

            subtitle.font =
                [UIFont systemFontOfSize:14.0];

            subtitle.textAlignment =
                NSTextAlignmentCenter;

            subtitle.textColor =
                [UIColor secondaryLabelColor];

            [SRController.view addSubview:subtitle];

            SRTextView =
                [[UITextView alloc] init];

            SRTextView.translatesAutoresizingMaskIntoConstraints =
                NO;

            SRTextView.editable = NO;

            SRTextView.selectable = YES;

            SRTextView.font =
                [UIFont monospacedSystemFontOfSize:12.0
                                             weight:UIFontWeightRegular];

            SRTextView.backgroundColor =
                [UIColor secondarySystemBackgroundColor];

            SRTextView.textColor =
                [UIColor labelColor];

            SRTextView.layer.cornerRadius = 12.0;

            [SRController.view addSubview:SRTextView];

            UIButton *refresh =
                [UIButton buttonWithType:UIButtonTypeSystem];

            refresh.translatesAutoresizingMaskIntoConstraints = NO;

            [refresh setTitle:@"REFRESH"
                     forState:UIControlStateNormal];

            refresh.titleLabel.font =
                [UIFont boldSystemFontOfSize:16.0];

            [refresh addTarget:
                nil
                action:@selector(dummy)
                forControlEvents:UIControlEventTouchUpInside];

            [SRController.view addSubview:refresh];

            UIButton *close =
                [UIButton buttonWithType:UIButtonTypeSystem];

            close.translatesAutoresizingMaskIntoConstraints = NO;

            [close setTitle:@"CLOSE"
                    forState:UIControlStateNormal];

            close.titleLabel.font =
                [UIFont boldSystemFontOfSize:16.0];

            [close addTarget:
                nil
                action:@selector(dummy)
                forControlEvents:UIControlEventTouchUpInside];

            [SRController.view addSubview:close];

            [NSLayoutConstraint activateConstraints:@[
                [title.topAnchor
                    constraintEqualToAnchor:
                        SRController.view.safeAreaLayoutGuide.topAnchor
                    constant:10.0],

                [title.leadingAnchor
                    constraintEqualToAnchor:
                        SRController.view.leadingAnchor
                    constant:15.0],

                [title.trailingAnchor
                    constraintEqualToAnchor:
                        SRController.view.trailingAnchor
                    constant:-15.0],

                [subtitle.topAnchor
                    constraintEqualToAnchor:
                        title.bottomAnchor
                    constant:2.0],

                [subtitle.leadingAnchor
                    constraintEqualToAnchor:
                        SRController.view.leadingAnchor
                    constant:15.0],

                [subtitle.trailingAnchor
                    constraintEqualToAnchor:
                        SRController.view.trailingAnchor
                    constant:-15.0],

                [SRTextView.topAnchor
                    constraintEqualToAnchor:
                        subtitle.bottomAnchor
                    constant:10.0],

                [SRTextView.leadingAnchor
                    constraintEqualToAnchor:
                        SRController.view.leadingAnchor
                    constant:10.0],

                [SRTextView.trailingAnchor
                    constraintEqualToAnchor:
                        SRController.view.trailingAnchor
                    constant:-10.0],

                [SRTextView.bottomAnchor
                    constraintEqualToAnchor:
                        refresh.topAnchor
                    constant:-10.0],

                [refresh.leadingAnchor
                    constraintEqualToAnchor:
                        SRController.view.leadingAnchor
                    constant:20.0],

                [refresh.bottomAnchor
                    constraintEqualToAnchor:
                        SRController.view.safeAreaLayoutGuide.bottomAnchor
                    constant:-10.0],

                [close.trailingAnchor
                    constraintEqualToAnchor:
                        SRController.view.trailingAnchor
                    constant:-20.0],

                [close.bottomAnchor
                    constraintEqualToAnchor:
                        SRController.view.safeAreaLayoutGuide.bottomAnchor
                    constant:-10.0]
            ]];

            /*
             Buttons use blocks through associated objects
             to avoid requiring another source file.
            */

            [refresh addTarget:
                [SRController class]
                action:@selector(dummy)
                forControlEvents:UIControlEventTouchUpInside];

            [close addTarget:
                [SRController class]
                action:@selector(dummy)
                forControlEvents:UIControlEventTouchUpInside];

            SRWindow.hidden = NO;

            [SRWindow makeKeyAndVisible];

            SRRefreshScreen();
        });
}

static void SRRefreshScreen(void)
{
    if (!SRTextView) {
        return;
    }

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    NSMutableString *text =
        [NSMutableString string];

    [text appendString:
        @"========================================\n"];

    [text appendString:
        @"SANNE REALTIME DIAGNOSTIC\n"];

    [text appendString:
        @"========================================\n\n"];

    [text appendFormat:
        @"CURRENT STATE — %@\n\n",
        SRTime()];

    [text appendFormat:
        @"PERMISSION: %@\n",
        SRPermission()];

    [text appendFormat:
        @"INJECTION AVAILABLE: %@\n",
        session.isMicrophoneInjectionAvailable
            ? @"YES"
            : @"NO"];

    [text appendFormat:
        @"PREFERRED MODE: %@\n",
        SRInjectionMode(
            session.preferredMicrophoneInjectionMode)];

    [text appendFormat:
        @"CATEGORY: %@\n",
        session.category ?: @"NONE"];

    [text appendFormat:
        @"MODE: %@\n",
        session.mode ?: @"NONE"];

    [text appendFormat:
        @"INPUT AVAILABLE: %@\n",
        session.isInputAvailable
            ? @"YES"
            : @"NO"];

    [text appendFormat:
        @"INPUT CHANNELS: %ld\n",
        (long)session.inputNumberOfChannels];

    [text appendFormat:
        @"SAMPLE RATE: %.2f\n",
        session.sampleRate];

    [text appendFormat:
        @"INPUT LATENCY: %.6f\n",
        session.inputLatency];

    [text appendFormat:
        @"OUTPUT LATENCY: %.6f\n\n",
        session.outputLatency];

    [text appendFormat:
        @"%@\n\n",
        SRRouteDescription()];

    [text appendString:
        @"========================================\n"];

    [text appendString:
        @"EVENT HISTORY\n"];

    [text appendString:
        @"========================================\n\n"];

    if (SREvents.count == 0) {

        [text appendString:
            @"No events yet.\n"];

    } else {

        for (NSString *event in SREvents) {

            [text appendString:event];
            [text appendString:@"\n"];
        }
    }

    SRTextView.text = text;

    [SRTextView
        scrollRangeToVisible:
            NSMakeRange(
                SRTextView.text.length,
                0)];
}

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

            AVAudioSession *session =
                [AVAudioSession sharedInstance];

            NSNumber *reported =
                notification.userInfo[
                    AVAudioSessionMicrophoneInjectionIsAvailableKey
                ];

            BOOL available =
                session.isMicrophoneInjectionAvailable;

            if (reported) {
                available = reported.boolValue;
            }

            SREvent(
                [NSString stringWithFormat:
                    @"INJECTION CAPABILITY EVENT → %@",
                    available
                        ? @"YES"
                        : @"NO"]);

            if (available) {

                NSError *error = nil;

                BOOL success =
                    [session
                        setPreferredMicrophoneInjectionMode:
                            AVAudioSessionMicrophoneInjectionModeSpokenAudio
                        error:&error];

                if (success) {

                    SREvent(
                        @"SPOKEN AUDIO MODE → SUCCESS");

                } else {

                    SREvent(
                        [NSString stringWithFormat:
                            @"SPOKEN AUDIO MODE → FAILED: %@",
                            error.localizedDescription
                                ?: @"Unknown error"]);
                }
            }
        }];

    [center
        addObserverForName:
            AVAudioSessionRouteChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            NSNumber *reason =
                notification.userInfo[
                    AVAudioSessionRouteChangeReasonKey];

            SREvent(
                [NSString stringWithFormat:
                    @"ROUTE CHANGE → reason %ld",
                    (long)reason.integerValue]);
        }];

    [center
        addObserverForName:
            AVAudioSessionInterruptionNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            NSNumber *type =
                notification.userInfo[
                    AVAudioSessionInterruptionTypeKey];

            if (type.integerValue ==
                AVAudioSessionInterruptionTypeBegan) {

                SREvent(@"AUDIO INTERRUPTION → BEGAN");

            } else {

                SREvent(@"AUDIO INTERRUPTION → ENDED");
            }
        }];

    [center
        addObserverForName:
            UIApplicationDidBecomeActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SREvent(@"APPLICATION → ACTIVE");
        }];

    [center
        addObserverForName:
            UIApplicationWillResignActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            SREvent(@"APPLICATION → RESIGNING ACTIVE");
        }];

    SREvent(@"OBSERVERS INSTALLED");
}

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

                SRCreateScreen();

                SREvent(
                    @"SANNE REALTIME DIAGNOSTIC STARTED");

                SREvent(
                    @"PASSIVE MODE — NO AUDIO ENGINE");

                SREvent(
                    @"NO MICROPHONE TAP");

                SREvent(
                    @"NO AUDIO GENERATION");

                SREvent(
                    @"NO SESSION ACTIVATION");

                SRRefreshScreen();
            });
    }
}
