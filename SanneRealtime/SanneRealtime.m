#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

static NSMutableArray<NSString *> *gRuntimeLog = nil;

static BOOL gObserversStarted = NO;
static BOOL gHasAudioEvents = NO;
static BOOL gShowingReport = NO;

static void SRRecordLog(NSString *message)
{
    if (!gRuntimeLog)
        gRuntimeLog = [NSMutableArray array];

    NSDateFormatter *formatter =
        [[NSDateFormatter alloc] init];

    formatter.dateFormat = @"HH:mm:ss.SSS";

    NSString *time =
        [formatter stringFromDate:[NSDate date]];

    NSString *entry =
        [NSString stringWithFormat:
            @"[%@] %@",
            time ?: @"?",
            message ?: @""];

    [gRuntimeLog addObject:entry];

    while (gRuntimeLog.count > 80) {
        [gRuntimeLog removeObjectAtIndex:0];
    }

    NSLog(
        @"[SanneRealtime] %@",
        entry
    );
}

static void SRPopup(NSString *message)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window = nil;

        if (@available(iOS 13.0, *)) {

            for (UIScene *scene in
                 UIApplication.sharedApplication.connectedScenes) {

                if (scene.activationState !=
                    UISceneActivationStateForegroundActive)
                    continue;

                if (![scene isKindOfClass:[UIWindowScene class]])
                    continue;

                UIWindowScene *windowScene =
                    (UIWindowScene *)scene;

                for (UIWindow *candidate in windowScene.windows) {

                    if (candidate.isKeyWindow) {
                        window = candidate;
                        break;
                    }
                }

                if (window)
                    break;
            }
        }

        if (!window)
            return;

        UIViewController *controller =
            window.rootViewController;

        while (controller.presentedViewController)
            controller =
                controller.presentedViewController;

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:@"SanneRealtime"
                message:message
                preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"OK"
                style:UIAlertActionStyleDefault
                handler:nil]];

        [controller presentViewController:alert
                                 animated:YES
                               completion:nil];
    });
}

static NSString *SRPermissionString(void)
{
    if (@available(iOS 18.2, *)) {

        AVAudioApplicationMicrophoneInjectionPermission permission =
            AVAudioApplication.sharedInstance.microphoneInjectionPermission;

        switch (permission) {

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

static NSString *SRPortDescription(
    AVAudioSessionPortDescription *port
)
{
    if (!port)
        return @"<none>";

    return [NSString stringWithFormat:
        @"%@ (%@)",
        port.portName ?: @"?",
        port.portType ?: @"?"];
}

static NSString *SRRouteDescription(
    AVAudioSessionRouteDescription *route
)
{
    if (!route)
        return @"<no route>";

    NSMutableString *result =
        [NSMutableString string];

    [result appendString:@"INPUTS:\n"];

    if (route.inputs.count == 0) {

        [result appendString:@"  <none>\n"];

    } else {

        for (AVAudioSessionPortDescription *port
             in route.inputs) {

            [result appendFormat:
                @"  %@\n",
                SRPortDescription(port)];
        }
    }

    [result appendString:@"OUTPUTS:\n"];

    if (route.outputs.count == 0) {

        [result appendString:@"  <none>\n"];

    } else {

        for (AVAudioSessionPortDescription *port
             in route.outputs) {

            [result appendFormat:
                @"  %@\n",
                SRPortDescription(port)];
        }
    }

    return result;
}

static NSString *SRSessionDiagnostic(void)
{
    if (!@available(iOS 18.2, *))
        return @"iOS 18.2 or newer required.";

    AVAudioSession *session =
        AVAudioSession.sharedInstance;

    return [NSString stringWithFormat:

        @"CATEGORY: %@\n"
         "MODE: %@\n"
         "INPUT AVAILABLE: %@\n"
         "INPUT CHANNELS: %ld\n"
         "SAMPLE RATE: %.2f\n"
         "INPUT LATENCY: %.6f\n"
         "OUTPUT LATENCY: %.6f\n"
         "INJECTION AVAILABLE: %@\n\n"
         "%@",

        session.category ?: @"?",
        session.mode ?: @"?",

        session.isInputAvailable
            ? @"YES"
            : @"NO",

        (long)session.inputNumberOfChannels,

        session.sampleRate,

        session.inputLatency,

        session.outputLatency,

        session.isMicrophoneInjectionAvailable
            ? @"YES"
            : @"NO",

        SRRouteDescription(
            session.currentRoute
        )
    ];
}

static void SRRecordSessionState(
    NSString *reason
)
{
    gHasAudioEvents = YES;

    SRRecordLog(
        [NSString stringWithFormat:
            @"STATE: %@\n%@",
            reason ?: @"UNKNOWN",
            SRSessionDiagnostic()]
    );
}

static void SRShowReport(void)
{
    if (gShowingReport)
        return;

    if (!gRuntimeLog ||
        gRuntimeLog.count == 0)
        return;

    gShowingReport = YES;

    NSMutableString *report =
        [NSMutableString string];

    [report appendString:
        @"PASSIVE AUDIO REPORT\n\n"];

    [report appendString:
        @"IMPORTANT:\n"
         "This build did NOT activate the audio session.\n"
         "This build did NOT enable microphone injection.\n"
         "This build did NOT play audio.\n"
         "This build did NOT create AVAudioEngine.\n"
         "This build only observed the session.\n\n"];

    [report appendString:
        @"RECENT EVENTS\n\n"];

    NSUInteger startIndex = 0;

    if (gRuntimeLog.count > 16) {

        startIndex =
            gRuntimeLog.count - 16;
    }

    for (NSUInteger i = startIndex;
         i < gRuntimeLog.count;
         i++) {

        [report appendFormat:
            @"%@\n\n",
            gRuntimeLog[i]];
    }

    [report appendString:
        @"CURRENT STATE\n\n"];

    [report appendString:
        SRSessionDiagnostic()];

    if (report.length > 7000) {

        report =
            [NSMutableString
                stringWithFormat:
                    @"...LAST EVENTS...\n\n%@",
                    [report substringFromIndex:
                        report.length - 7000]];
    }

    SRPopup(report);

    gShowingReport = NO;
}

static void SRHandleRouteChange(
    NSNotification *notification
)
{
    NSNumber *reason =
        notification.userInfo[
            AVAudioSessionRouteChangeReasonKey
        ];

    gHasAudioEvents = YES;

    SRRecordLog(
        [NSString stringWithFormat:
            @"ROUTE CHANGE\n"
             "REASON: %@",
            reason ?: @"unknown"]
    );

    SRRecordSessionState(
        @"AFTER ROUTE CHANGE"
    );
}

static void SRHandleCapabilityChange(
    NSNotification *notification
)
{
    gHasAudioEvents = YES;

    AVAudioSession *session =
        AVAudioSession.sharedInstance;

    NSNumber *available =
        notification.userInfo[
            AVAudioSessionMicrophoneInjectionIsAvailableKey
        ];

    SRRecordLog(
        [NSString stringWithFormat:
            @"INJECTION CAPABILITY CHANGE\n"
             "NOTIFICATION: %@\n"
             "CURRENT SESSION: %@",

            available
                ? (available.boolValue
                    ? @"YES"
                    : @"NO")
                : @"UNKNOWN",

            session.isMicrophoneInjectionAvailable
                ? @"YES"
                : @"NO"]
    );

    SRRecordSessionState(
        @"AFTER INJECTION CAPABILITY CHANGE"
    );
}

static void SRHandleInterruption(
    NSNotification *notification
)
{
    gHasAudioEvents = YES;

    NSNumber *type =
        notification.userInfo[
            AVAudioSessionInterruptionTypeKey
        ];

    NSNumber *reason =
        notification.userInfo[
            AVAudioSessionInterruptionReasonKey
        ];

    SRRecordLog(
        [NSString stringWithFormat:
            @"AUDIO INTERRUPTION\n"
             "TYPE: %@\n"
             "REASON: %@",
            type ?: @"unknown",
            reason ?: @"unknown"]
    );

    SRRecordSessionState(
        @"AFTER INTERRUPTION"
    );
}

static void SRHandleMediaServicesReset(
    NSNotification *notification
)
{
    gHasAudioEvents = YES;

    SRRecordLog(
        @"MEDIA SERVICES RESET"
    );

    SRRecordSessionState(
        @"AFTER MEDIA SERVICES RESET"
    );
}

static void SRHandleApplicationDidBecomeActive(
    NSNotification *notification
)
{
    SRRecordLog(
        @"NOBANNY BECAME ACTIVE."
    );

    SRRecordSessionState(
        @"NOBANNY BECAME ACTIVE"
    );

    if (gHasAudioEvents) {

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                1000 * NSEC_PER_MSEC
            ),
            dispatch_get_main_queue(),
            ^{

                SRRecordSessionState(
                    @"FINAL STATE BEFORE REPORT"
                );

                SRShowReport();
            }
        );
    }
}

static void SRStartObservers(void)
{
    if (gObserversStarted)
        return;

    gObserversStarted = YES;

    NSNotificationCenter *center =
        NSNotificationCenter.defaultCenter;

    [center addObserverForName:
                AVAudioSessionRouteChangeNotification
                object:nil
                queue:NSOperationQueue.mainQueue
                usingBlock:
        ^(NSNotification *notification) {

            SRHandleRouteChange(
                notification
            );
        }];

    if (@available(iOS 18.2, *)) {

        [center addObserverForName:
                    AVAudioSessionMicrophoneInjectionCapabilitiesChangeNotification
                    object:nil
                    queue:NSOperationQueue.mainQueue
                    usingBlock:
        ^(NSNotification *notification) {

            SRHandleCapabilityChange(
                notification
            );
        }];
    }

    [center addObserverForName:
                AVAudioSessionInterruptionNotification
                object:nil
                queue:NSOperationQueue.mainQueue
                usingBlock:
        ^(NSNotification *notification) {

            SRHandleInterruption(
                notification
            );
        }];

    [center addObserverForName:
                AVAudioSessionMediaServicesWereResetNotification
                object:nil
                queue:NSOperationQueue.mainQueue
                usingBlock:
        ^(NSNotification *notification) {

            SRHandleMediaServicesReset(
                notification
            );
        }];

    [center addObserverForName:
                UIApplicationDidBecomeActiveNotification
                object:nil
                queue:NSOperationQueue.mainQueue
                usingBlock:
        ^(NSNotification *notification) {

            SRHandleApplicationDidBecomeActive(
                notification
            );
        }];

    SRRecordLog(
        @"PASSIVE OBSERVERS INSTALLED."
    );
}

static void SRInitialState(void)
{
    SRRecordSessionState(
        @"INITIAL"
    );

    SRRecordLog(
        [NSString stringWithFormat:
            @"INJECTION PERMISSION: %@",
            SRPermissionString()]
    );

    SRRecordLog(
        @"NO INJECTION ACTION WILL BE PERFORMED."
    );

    SRRecordLog(
        @"NO AUDIO WILL BE GENERATED."
    );

    SRPopup(
        @"PASSIVE DIAGNOSTIC READY\n\n"
         "SanneRealtime is only observing Discord's "
         "audio session.\n\n"
         "No injection and no test voice will be used."
    );
}

__attribute__((constructor))
static void SanneRealtimeLoaded(void)
{
    gRuntimeLog =
        [NSMutableArray array];

    SRRecordLog(
        @"=========================================="
    );

    SRRecordLog(
        @"SANNE REALTIME - PASSIVE CALL TEST"
    );

    SRRecordLog(
        @"ZERO AUDIO INJECTION"
    );

    SRRecordLog(
        @"ZERO AUDIO GENERATION"
    );

    SRRecordLog(
        @"ZERO AUDIO SESSION OWNERSHIP"
    );

    SRRecordLog(
        @"=========================================="
    );

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            SRStartObservers();

            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    1000 * NSEC_PER_MSEC
                ),
                dispatch_get_main_queue(),
                ^{

                    SRInitialState();
                }
            );
        }
    );
}
