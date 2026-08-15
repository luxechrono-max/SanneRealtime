//
//  SanneRealtime.m
//  Diagnostic build
//
//  IMPORTANT:
//  This version ONLY OBSERVES the audio session.
//  It does NOT:
//    - setCategory:
//    - setMode:
//    - setActive:
//    - change audio routes
//    - request microphone injection
//    - inject audio
//
//  Goal:
//  Determine whether the host call remains stable when SanneRealtime
//  does not manipulate the host AVAudioSession.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#pragma mark - Globals

static UIWindow *SRWindow = nil;
static UITextView *SRTextView = nil;
static NSTimer *SRTimer = nil;

static NSMutableArray<NSString *> *SRLogLines = nil;

static BOOL SRInstalled = NO;
static BOOL SRLastActive = NO;
static BOOL SRLastInjection = NO;
static AVAudioSessionCategory SRLastCategory = nil;
static AVAudioSessionMode SRLastMode = nil;
static NSInteger SRLastChannels = -1;

#pragma mark - Logging

static NSString *SRTimeString(void)
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss.SSS";
    return [formatter stringFromDate:[NSDate date]];
}

static void SRLog(NSString *format, ...)
{
    if (!SRLogLines) {
        SRLogLines = [NSMutableArray array];
    }

    va_list args;
    va_start(args, format);

    NSString *message =
        [[NSString alloc] initWithFormat:format arguments:args];

    va_end(args);

    NSString *line =
        [NSString stringWithFormat:@"[%@] %@",
         SRTimeString(),
         message];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!SRLogLines) {
            SRLogLines = [NSMutableArray array];
        }

        [SRLogLines addObject:line];

        /*
         Keep the overlay reasonably small.
         */
        while (SRLogLines.count > 40) {
            [SRLogLines removeObjectAtIndex:0];
        }

        if (SRTextView) {
            NSMutableString *text =
                [NSMutableString string];

            for (NSString *item in SRLogLines) {
                [text appendString:item];
                [text appendString:@"\n"];
            }

            SRTextView.text = text;
        }
    });
}

#pragma mark - Safe string helpers

static NSString *SRCategoryName(AVAudioSession *session)
{
    NSString *value = session.category;

    if (!value) {
        return @"NONE";
    }

    return value;
}

static NSString *SRModeName(AVAudioSession *session)
{
    NSString *value = session.mode;

    if (!value) {
        return @"NONE";
    }

    return value;
}

static NSString *SRRouteDescription(AVAudioSession *session)
{
    AVAudioSessionRouteDescription *route =
        session.currentRoute;

    NSMutableArray<NSString *> *inputs =
        [NSMutableArray array];

    NSMutableArray<NSString *> *outputs =
        [NSMutableArray array];

    for (AVAudioSessionPortDescription *port in route.inputs) {
        if (port.portName.length > 0) {
            [inputs addObject:port.portName];
        }
    }

    for (AVAudioSessionPortDescription *port in route.outputs) {
        if (port.portName.length > 0) {
            [outputs addObject:port.portName];
        }
    }

    NSString *inputText =
        inputs.count ? [inputs componentsJoinedByString:@"/"] : @"NONE";

    NSString *outputText =
        outputs.count ? [outputs componentsJoinedByString:@"/"] : @"NONE";

    return [NSString stringWithFormat:
            @"IN:%@ OUT:%@",
            inputText,
            outputText];
}

#pragma mark - Snapshot

static void SRPrintSnapshot(NSString *reason)
{
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    BOOL active =
        session.isOtherAudioPlaying ? YES : session.isInputAvailable;

    BOOL injectionAvailable = NO;

    /*
     iOS 26 microphone-injection capability.
     We ONLY READ this property.
     */
    @try {
        injectionAvailable =
            session.isMicrophoneInjectionAvailable;
    }
    @catch (__unused NSException *exception) {
        injectionAvailable = NO;
    }

    NSInteger channels =
        session.inputNumberOfChannels;

    double sampleRate =
        session.sampleRate;

    NSString *category =
        SRCategoryName(session);

    NSString *mode =
        SRModeName(session);

    NSString *route =
        SRRouteDescription(session);

    SRLog(@"SNAPSHOT:%@",
          reason ?: @"UNKNOWN");

    SRLog(@"ACTIVE:%@",
          active ? @"YES" : @"NO");

    SRLog(@"INJECTION_AVAILABLE:%@",
          injectionAvailable ? @"YES" : @"NO");

    SRLog(@"CATEGORY:%@",
          category);

    SRLog(@"MODE:%@",
          mode);

    SRLog(@"INPUT_AVAILABLE:%@",
          session.isInputAvailable ? @"YES" : @"NO");

    SRLog(@"INPUT_CHANNELS:%ld",
          (long)channels);

    SRLog(@"SAMPLE_RATE:%.0f",
          sampleRate);

    SRLog(@"ROUTE:%@",
          route);

    SRLog(@"APP_STATE:%@",
          UIApplication.sharedApplication.applicationState ==
          UIApplicationStateActive
          ? @"ACTIVE"
          :
          UIApplication.sharedApplication.applicationState ==
          UIApplicationStateBackground
          ? @"BACKGROUND"
          : @"INACTIVE");

    SRLog(@"------------------------------");
}

#pragma mark - Polling

static void SRPollAudioState(void)
{
    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    BOOL injectionAvailable = NO;

    @try {
        injectionAvailable =
            session.isMicrophoneInjectionAvailable;
    }
    @catch (__unused NSException *exception) {
        injectionAvailable = NO;
    }

    BOOL active =
        session.isInputAvailable;

    AVAudioSessionCategory category =
        session.category;

    AVAudioSessionMode mode =
        session.mode;

    NSInteger channels =
        session.inputNumberOfChannels;

    BOOL changed = NO;

    if (active != SRLastActive) {
        SRLastActive = active;

        SRLog(@"OBSERVED INPUT_STATE:%@",
              active ? @"AVAILABLE" : @"UNAVAILABLE");

        changed = YES;
    }

    if (injectionAvailable != SRLastInjection) {
        SRLastInjection =
            injectionAvailable;

        SRLog(@"OBSERVED INJECTION:%@",
              injectionAvailable ? @"YES" : @"NO");

        changed = YES;
    }

    if (![SRLastCategory isEqualToString:category]) {
        SRLastCategory =
            [category copy];

        SRLog(@"OBSERVED CATEGORY:%@",
              category ?: @"NONE");

        changed = YES;
    }

    if (![SRLastMode isEqualToString:mode]) {
        SRLastMode =
            [mode copy];

        SRLog(@"OBSERVED MODE:%@",
              mode ?: @"NONE");

        changed = YES;
    }

    if (channels != SRLastChannels) {
        SRLastChannels =
            channels;

        SRLog(@"OBSERVED INPUT_CHANNELS:%ld",
              (long)channels);

        changed = YES;
    }

    if (changed) {
        SRPrintSnapshot(@"STATE_CHANGE");
    }
}

#pragma mark - Application notifications

static void SRApplicationDidBecomeActive(NSNotification *notification)
{
    (void)notification;

    SRLog(@"APPLICATION:ACTIVE");
    SRPrintSnapshot(@"APPLICATION_ACTIVE");
}

static void SRApplicationWillResignActive(NSNotification *notification)
{
    (void)notification;

    SRLog(@"APPLICATION:WILL_RESIGN_ACTIVE");
    SRPrintSnapshot(@"APPLICATION_WILL_RESIGN_ACTIVE");
}

static void SRApplicationDidEnterBackground(NSNotification *notification)
{
    (void)notification;

    SRLog(@"APPLICATION:BACKGROUND");
    SRPrintSnapshot(@"APPLICATION_BACKGROUND");
}

static void SRApplicationWillEnterForeground(NSNotification *notification)
{
    (void)notification;

    SRLog(@"APPLICATION:FOREGROUND");
    SRPrintSnapshot(@"APPLICATION_FOREGROUND");
}

#pragma mark - Audio notifications

static void SRRouteChanged(NSNotification *notification)
{
    AVAudioSessionRouteChangeReason reason =
        [notification.userInfo[
            AVAudioSessionRouteChangeReasonKey
        ] integerValue];

    SRLog(@"AUDIO_ROUTE_CHANGE:REASON:%ld",
          (long)reason);

    SRPrintSnapshot(@"ROUTE_CHANGE");
}

static void SRInterruption(NSNotification *notification)
{
    NSNumber *typeNumber =
        notification.userInfo[
            AVAudioSessionInterruptionTypeKey
        ];

    NSInteger type =
        typeNumber ? typeNumber.integerValue : -1;

    if (type ==
        AVAudioSessionInterruptionTypeBegan) {

        SRLog(@"AUDIO_INTERRUPTION:BEGAN");

    } else if (type ==
               AVAudioSessionInterruptionTypeEnded) {

        SRLog(@"AUDIO_INTERRUPTION:ENDED");

    } else {

        SRLog(@"AUDIO_INTERRUPTION:TYPE:%ld",
              (long)type);
    }

    SRPrintSnapshot(@"INTERRUPTION");
}

static void SRMediaServicesReset(NSNotification *notification)
{
    (void)notification;

    SRLog(@"MEDIA_SERVICES:RESET");
    SRPrintSnapshot(@"MEDIA_SERVICES_RESET");
}

static void SRMediaServicesLost(NSNotification *notification)
{
    (void)notification;

    SRLog(@"MEDIA_SERVICES:LOST");
    SRPrintSnapshot(@"MEDIA_SERVICES_LOST");
}

#pragma mark - Injection capability notification

static void SRInjectionCapabilityChanged(NSNotification *notification)
{
    (void)notification;

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    BOOL available = NO;

    @try {
        available =
            session.isMicrophoneInjectionAvailable;
    }
    @catch (__unused NSException *exception) {
        available = NO;
    }

    SRLog(@"INJECTION_CAPABILITY_CHANGED:%@",
          available ? @"YES" : @"NO");

    SRPrintSnapshot(@"INJECTION_CAPABILITY_CHANGE");
}

#pragma mark - Overlay

static void SRUpdateOverlay(void)
{
    if (!SRTextView) {
        return;
    }

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    BOOL injection = NO;

    @try {
        injection =
            session.isMicrophoneInjectionAvailable;
    }
    @catch (__unused NSException *exception) {
        injection = NO;
    }

    NSString *header =
        [NSString stringWithFormat:
         @"SANNE REALTIME — OBSERVER\n"
         @"INJECTION:%@\n"
         @"CATEGORY:%@\n"
         @"MODE:%@\n"
         @"INPUT:%@\n"
         @"CH:%ld\n"
         @"RATE:%.0f\n"
         @"ROUTE:%@\n"
         @"------------------------------\n",
         injection ? @"YES" : @"NO",
         SRCategoryName(session),
         SRModeName(session),
         session.isInputAvailable ? @"YES" : @"NO",
         (long)session.inputNumberOfChannels,
         session.sampleRate,
         SRRouteDescription(session)];

    NSMutableString *body =
        [NSMutableString stringWithString:header];

    if (SRLogLines.count > 0) {
        for (NSString *line in SRLogLines) {
            [body appendString:line];
            [body appendString:@"\n"];
        }
    }

    SRTextView.text = body;
}

static void SRCreateOverlay(void)
{
    if (SRWindow) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{

        if (SRWindow) {
            return;
        }

        UIScreen *screen =
            UIScreen.mainScreen;

        CGRect bounds =
            screen.bounds;

        CGFloat width =
            MIN(CGRectGetWidth(bounds) - 24.0,
                760.0);

        CGFloat height = 420.0;

        CGFloat x =
            (CGRectGetWidth(bounds) - width) / 2.0;

        CGFloat y =
            70.0;

        SRWindow =
            [[UIWindow alloc]
             initWithFrame:CGRectMake(x, y, width, height)];

        SRWindow.windowLevel =
            UIWindowLevelAlert + 100.0;

        SRWindow.backgroundColor =
            [UIColor clearColor];

        SRWindow.hidden = NO;

        UIViewController *controller =
            [[UIViewController alloc] init];

        controller.view.backgroundColor =
            [UIColor clearColor];

        SRWindow.rootViewController =
            controller;

        UIView *panel =
            [[UIView alloc]
             initWithFrame:controller.view.bounds];

        panel.autoresizingMask =
            UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;

        panel.backgroundColor =
            [UIColor colorWithWhite:0.02 alpha:0.92];

        panel.layer.cornerRadius =
            18.0;

        panel.layer.masksToBounds =
            YES;

        [controller.view addSubview:panel];

        SRTextView =
            [[UITextView alloc]
             initWithFrame:CGRectInset(panel.bounds,
                                       14.0,
                                       14.0)];

        SRTextView.autoresizingMask =
            UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;

        SRTextView.backgroundColor =
            [UIColor clearColor];

        SRTextView.textColor =
            [UIColor whiteColor];

        SRTextView.font =
            [UIFont fontWithName:@"Menlo"
                            size:13.0];

        SRTextView.editable = NO;

        SRTextView.selectable = NO;

        SRTextView.scrollEnabled = YES;

        SRTextView.userInteractionEnabled = NO;

        SRTextView.textContainerInset =
            UIEdgeInsetsMake(4, 4, 4, 4);

        [panel addSubview:SRTextView];

        SRLog(@"DIAGNOSTIC OBSERVER STARTED");
        SRLog(@"NO AUDIO SESSION MODIFICATION");
        SRLog(@"NO INJECTION REQUEST");
        SRLog(@"NO SETACTIVE");
        SRLog(@"NO CATEGORY/MODE CHANGE");
        SRLog(@"------------------------------");

        SRPrintSnapshot(@"INITIAL");

        SRUpdateOverlay();
    });
}

#pragma mark - Notification registration

static void SRInstallObservers(void)
{
    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    [center addObserverForName:
        UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        SRApplicationDidBecomeActive(note);
    }];

    [center addObserverForName:
        UIApplicationWillResignActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        SRApplicationWillResignActive(note);
    }];

    [center addObserverForName:
        UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        SRApplicationDidEnterBackground(note);
    }];

    [center addObserverForName:
        UIApplicationWillEnterForegroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        SRApplicationWillEnterForeground(note);
    }];

    [center addObserverForName:
        AVAudioSessionRouteChangeNotification
                        object:[AVAudioSession sharedInstance]
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        SRRouteChanged(note);
    }];

    [center addObserverForName:
        AVAudioSessionInterruptionNotification
                        object:[AVAudioSession sharedInstance]
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        SRInterruption(note);
    }];

    [center addObserverForName:
        AVAudioSessionMediaServicesWereResetNotification
                        object:[AVAudioSession sharedInstance]
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        SRMediaServicesReset(note);
    }];

    [center addObserverForName:
        AVAudioSessionMediaServicesWereLostNotification
                        object:[AVAudioSession sharedInstance]
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        SRMediaServicesLost(note);
    }];

    /*
     This notification is specifically associated with the
     microphone-injection capability.
     */
    [center addObserverForName:
        AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
                        object:[AVAudioSession sharedInstance]
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        SRInjectionCapabilityChanged(note);
    }];

    SRLog(@"NOTIFICATION OBSERVERS INSTALLED");
}

#pragma mark - Timer

static void SRStartTimer(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if (SRTimer) {
            [SRTimer invalidate];
            SRTimer = nil;
        }

        SRTimer =
            [NSTimer scheduledTimerWithTimeInterval:0.5
                                              repeats:YES
                                                block:^(NSTimer *timer) {
            (void)timer;

            SRPollAudioState();
            SRUpdateOverlay();
        }];

    });
}

#pragma mark - Bootstrap

static void SRBootstrap(void)
{
    if (SRInstalled) {
        return;
    }

    SRInstalled = YES;

    SRLogLines =
        [NSMutableArray array];

    /*
     IMPORTANT:
     We deliberately do NOT touch AVAudioSession configuration here.
     */

    SRInstallObservers();

    SRCreateOverlay();

    SRStartTimer();
}

#pragma mark - Constructor

__attribute__((constructor))
static void SanneRealtimeLoad(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        SRBootstrap();
    });
}
