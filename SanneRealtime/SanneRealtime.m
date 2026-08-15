#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static UIWindow *SRWindow = nil;
static UITextView *SRTextView = nil;
static NSTimer *SRTimer = nil;

static NSMutableArray<NSString *> *SRLogLines = nil;
static BOOL SRInstalled = NO;

static BOOL SRLastInput = NO;
static BOOL SRLastInjection = NO;
static NSString *SRLastCategory = nil;
static NSString *SRLastMode = nil;
static NSInteger SRLastChannels = -1;

#pragma mark - Logging

static NSString *SRNow(void)
{
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"HH:mm:ss.SSS";
    return [f stringFromDate:[NSDate date]];
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
         SRNow(),
         message];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!SRLogLines) {
            SRLogLines = [NSMutableArray array];
        }

        [SRLogLines addObject:line];

        while (SRLogLines.count > 35) {
            [SRLogLines removeObjectAtIndex:0];
        }
    });
}

#pragma mark - Audio information

static NSString *SRRoute(void)
{
    AVAudioSession *s =
        [AVAudioSession sharedInstance];

    AVAudioSessionRouteDescription *route =
        s.currentRoute;

    NSMutableArray *ins =
        [NSMutableArray array];

    NSMutableArray *outs =
        [NSMutableArray array];

    for (AVAudioSessionPortDescription *p in route.inputs) {
        if (p.portName.length) {
            [ins addObject:p.portName];
        }
    }

    for (AVAudioSessionPortDescription *p in route.outputs) {
        if (p.portName.length) {
            [outs addObject:p.portName];
        }
    }

    NSString *input =
        ins.count ?
        [ins componentsJoinedByString:@"/"] :
        @"NONE";

    NSString *output =
        outs.count ?
        [outs componentsJoinedByString:@"/"] :
        @"NONE";

    return [NSString stringWithFormat:
            @"IN:%@ OUT:%@",
            input,
            output];
}

static BOOL SRInjectionAvailable(void)
{
    AVAudioSession *s =
        [AVAudioSession sharedInstance];

    BOOL result = NO;

    @try {
        result = s.isMicrophoneInjectionAvailable;
    }
    @catch (__unused NSException *e) {
        result = NO;
    }

    return result;
}

static void SRSnapshot(NSString *reason)
{
    AVAudioSession *s =
        [AVAudioSession sharedInstance];

    SRLog(@"SNAPSHOT:%@", reason);

    SRLog(@"INPUT_AVAILABLE:%@",
          s.isInputAvailable ? @"YES" : @"NO");

    SRLog(@"INPUT_CHANNELS:%ld",
          (long)s.inputNumberOfChannels);

    SRLog(@"SAMPLE_RATE:%.0f",
          s.sampleRate);

    SRLog(@"INJECTION:%@",
          SRInjectionAvailable() ? @"YES" : @"NO");

    SRLog(@"CATEGORY:%@",
          s.category ?: @"NONE");

    SRLog(@"MODE:%@",
          s.mode ?: @"NONE");

    SRLog(@"ROUTE:%@",
          SRRoute());

    UIApplicationState state =
        UIApplication.sharedApplication.applicationState;

    NSString *stateText;

    if (state == UIApplicationStateActive) {
        stateText = @"ACTIVE";
    }
    else if (state == UIApplicationStateBackground) {
        stateText = @"BACKGROUND";
    }
    else {
        stateText = @"INACTIVE";
    }

    SRLog(@"APP_STATE:%@", stateText);

    SRLog(@"------------------------------");
}

#pragma mark - Overlay update

static void SRUpdateOverlay(void)
{
    if (!SRTextView) {
        return;
    }

    AVAudioSession *s =
        [AVAudioSession sharedInstance];

    NSString *header =
        [NSString stringWithFormat:
         @"SANNE REALTIME — OBSERVER\n"
         @"P:%@\n"
         @"INJ:%@\n"
         @"CAT:%@\n"
         @"MODE:%@\n"
         @"INPUT:%@\n"
         @"CH:%ld\n"
         @"RATE:%.0f\n"
         @"ROUTE:%@\n"
         @"------------------------------\n",
         @"GRANTED",
         SRInjectionAvailable() ? @"YES" : @"NO",
         s.category ?: @"NONE",
         s.mode ?: @"NONE",
         s.isInputAvailable ? @"YES" : @"NO",
         (long)s.inputNumberOfChannels,
         s.sampleRate,
         SRRoute()];

    NSMutableString *text =
        [NSMutableString stringWithString:header];

    for (NSString *line in SRLogLines) {
        [text appendString:line];
        [text appendString:@"\n"];
    }

    SRTextView.text = text;
}

#pragma mark - Poll

static void SRPoll(void)
{
    AVAudioSession *s =
        [AVAudioSession sharedInstance];

    BOOL input =
        s.isInputAvailable;

    BOOL injection =
        SRInjectionAvailable();

    NSString *category =
        s.category ?: @"NONE";

    NSString *mode =
        s.mode ?: @"NONE";

    NSInteger channels =
        s.inputNumberOfChannels;

    if (input != SRLastInput) {

        SRLastInput = input;

        SRLog(@"OBSERVED INPUT:%@",
              input ? @"YES" : @"NO");

        SRSnapshot(@"INPUT_CHANGED");
    }

    if (injection != SRLastInjection) {

        SRLastInjection = injection;

        SRLog(@"OBSERVED INJECTION:%@",
              injection ? @"YES" : @"NO");

        SRSnapshot(@"INJECTION_CHANGED");
    }

    if (!SRLastCategory ||
        ![SRLastCategory isEqualToString:category]) {

        SRLastCategory =
            [category copy];

        SRLog(@"OBSERVED CATEGORY:%@",
              category);

        SRSnapshot(@"CATEGORY_CHANGED");
    }

    if (!SRLastMode ||
        ![SRLastMode isEqualToString:mode]) {

        SRLastMode =
            [mode copy];

        SRLog(@"OBSERVED MODE:%@",
              mode);

        SRSnapshot(@"MODE_CHANGED");
    }

    if (channels != SRLastChannels) {

        SRLastChannels =
            channels;

        SRLog(@"OBSERVED CHANNELS:%ld",
              (long)channels);

        SRSnapshot(@"CHANNELS_CHANGED");
    }

    SRUpdateOverlay();
}

#pragma mark - Application notifications

static void SRAppActive(NSNotification *n)
{
    (void)n;

    SRLog(@"APPLICATION:ACTIVE");
    SRSnapshot(@"APPLICATION_ACTIVE");
}

static void SRAppInactive(NSNotification *n)
{
    (void)n;

    SRLog(@"APPLICATION:INACTIVE");
    SRSnapshot(@"APPLICATION_INACTIVE");
}

static void SRAppBackground(NSNotification *n)
{
    (void)n;

    SRLog(@"APPLICATION:BACKGROUND");
    SRSnapshot(@"APPLICATION_BACKGROUND");
}

static void SRAppForeground(NSNotification *n)
{
    (void)n;

    SRLog(@"APPLICATION:FOREGROUND");
    SRSnapshot(@"APPLICATION_FOREGROUND");
}

#pragma mark - Audio notifications

static void SRRouteChanged(NSNotification *n)
{
    NSNumber *number =
        n.userInfo[AVAudioSessionRouteChangeReasonKey];

    NSInteger reason =
        number ? number.integerValue : -1;

    SRLog(@"ROUTE_CHANGED:REASON:%ld",
          (long)reason);

    SRSnapshot(@"ROUTE_CHANGE");
}

static void SRInterruption(NSNotification *n)
{
    NSNumber *number =
        n.userInfo[AVAudioSessionInterruptionTypeKey];

    NSInteger type =
        number ? number.integerValue : -1;

    if (type ==
        AVAudioSessionInterruptionTypeBegan) {

        SRLog(@"INTERRUPTION:BEGAN");
    }
    else if (type ==
             AVAudioSessionInterruptionTypeEnded) {

        SRLog(@"INTERRUPTION:ENDED");
    }
    else {

        SRLog(@"INTERRUPTION:TYPE:%ld",
              (long)type);
    }

    SRSnapshot(@"INTERRUPTION");
}

static void SRMediaReset(NSNotification *n)
{
    (void)n;

    SRLog(@"MEDIA_SERVICES:RESET");
    SRSnapshot(@"MEDIA_RESET");
}

static void SRMediaLost(NSNotification *n)
{
    (void)n;

    SRLog(@"MEDIA_SERVICES:LOST");
    SRSnapshot(@"MEDIA_LOST");
}

static void SRInjectionChanged(NSNotification *n)
{
    (void)n;

    SRLog(@"INJECTION_CAPABILITY_CHANGED:%@",
          SRInjectionAvailable() ? @"YES" : @"NO");

    SRSnapshot(@"INJECTION_CAPABILITY");
}

#pragma mark - Overlay

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
            [UIScreen mainScreen];

        CGRect screenBounds =
            screen.bounds;

        CGFloat screenWidth =
            screenBounds.size.width;

        CGFloat screenHeight =
            screenBounds.size.height;

        CGFloat width =
            screenWidth - 24.0;

        if (width > 760.0) {
            width = 760.0;
        }

        CGFloat height =
            420.0;

        CGFloat x =
            (screenWidth - width) / 2.0;

        CGFloat y =
            70.0;

        SRWindow =
            [[UIWindow alloc]
             initWithFrame:
             CGRectMake(x, y, width, height)];

        SRWindow.windowLevel =
            UIWindowLevelAlert + 100.0;

        SRWindow.backgroundColor =
            [UIColor clearColor];

        SRWindow.hidden = NO;

        UIViewController *vc =
            [[UIViewController alloc] init];

        vc.view.backgroundColor =
            [UIColor clearColor];

        SRWindow.rootViewController =
            vc;

        UIView *panel =
            [[UIView alloc]
             initWithFrame:
             CGRectMake(0,
                        0,
                        width,
                        height)];

        panel.backgroundColor =
            [UIColor colorWithWhite:0.02
                              alpha:0.94];

        panel.layer.cornerRadius =
            18.0;

        panel.layer.masksToBounds =
            YES;

        [vc.view addSubview:panel];

        CGFloat textX = 14.0;
        CGFloat textY = 14.0;
        CGFloat textWidth = width - 28.0;
        CGFloat textHeight = height - 28.0;

        SRTextView =
            [[UITextView alloc]
             initWithFrame:
             CGRectMake(textX,
                        textY,
                        textWidth,
                        textHeight)];

        SRTextView.backgroundColor =
            [UIColor clearColor];

        SRTextView.textColor =
            [UIColor whiteColor];

        SRTextView.font =
            [UIFont fontWithName:@"Menlo"
                            size:13.0];

        SRTextView.editable = NO;
        SRTextView.selectable = NO;
        SRTextView.userInteractionEnabled = NO;
        SRTextView.scrollEnabled = YES;

        SRTextView.textContainerInset =
            UIEdgeInsetsMake(4, 4, 4, 4);

        [panel addSubview:SRTextView];

        SRLog(@"DIAGNOSTIC OBSERVER STARTED");
        SRLog(@"NO SESSION ACTIVATION");
        SRLog(@"NO SESSION DEACTIVATION");
        SRLog(@"NO CATEGORY CHANGE");
        SRLog(@"NO MODE CHANGE");
        SRLog(@"NO ROUTE CHANGE");
        SRLog(@"NO INJECTION REQUEST");
        SRLog(@"------------------------------");

        SRSnapshot(@"INITIAL");
        SRUpdateOverlay();
    });
}

#pragma mark - Observers

static void SRInstallObservers(void)
{
    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    [center addObserverForName:
        UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
        SRAppActive(n);
    }];

    [center addObserverForName:
        UIApplicationWillResignActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
        SRAppInactive(n);
    }];

    [center addObserverForName:
        UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
        SRAppBackground(n);
    }];

    [center addObserverForName:
        UIApplicationWillEnterForegroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
        SRAppForeground(n);
    }];

    AVAudioSession *session =
        [AVAudioSession sharedInstance];

    [center addObserverForName:
        AVAudioSessionRouteChangeNotification
                        object:session
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
        SRRouteChanged(n);
    }];

    [center addObserverForName:
        AVAudioSessionInterruptionNotification
                        object:session
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
        SRInterruption(n);
    }];

    [center addObserverForName:
        AVAudioSessionMediaServicesWereResetNotification
                        object:session
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
        SRMediaReset(n);
    }];

    [center addObserverForName:
        AVAudioSessionMediaServicesWereLostNotification
                        object:session
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
        SRMediaLost(n);
    }];

    [center addObserverForName:
        AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
                        object:session
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
        SRInjectionChanged(n);
    }];

    SRLog(@"OBSERVERS INSTALLED");
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
            SRPoll();
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
     There is intentionally NO AVAudioSession configuration here.
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
