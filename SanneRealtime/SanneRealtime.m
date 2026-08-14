#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>

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

                UIWindowScene *ws = (UIWindowScene *)scene;

                for (UIWindow *w in ws.windows) {

                    if (w.isKeyWindow) {
                        window = w;
                        break;
                    }
                }

                if (window)
                    break;
            }
        }

        if (!window)
            return;

        UIViewController *vc = window.rootViewController;

        while (vc.presentedViewController)
            vc = vc.presentedViewController;

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

        [vc presentViewController:alert
                          animated:YES
                        completion:nil];
    });
}


static NSString *SRPermissionString(void)
{
    if (@available(iOS 18.2, *)) {

        AVAudioApplicationMicrophoneInjectionPermission p =
            AVAudioApplication.sharedInstance.microphoneInjectionPermission;

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


static NSString *SRRouteDescription(AVAudioSessionRouteDescription *route)
{
    NSMutableString *result =
        [NSMutableString string];

    [result appendFormat:
        @"INPUTS: %lu\n",
        (unsigned long)route.inputs.count];

    for (AVAudioSessionPortDescription *port in route.inputs) {

        [result appendFormat:
            @"  INPUT: %@ | %@ | channels=%lu\n",
            port.portType ?: @"?",
            port.portName ?: @"?",
            (unsigned long)port.channels.count];
    }

    [result appendFormat:
        @"OUTPUTS: %lu\n",
        (unsigned long)route.outputs.count];

    for (AVAudioSessionPortDescription *port in route.outputs) {

        [result appendFormat:
            @"  OUTPUT: %@ | %@ | channels=%lu\n",
            port.portType ?: @"?",
            port.portName ?: @"?",
            (unsigned long)port.channels.count];
    }

    return result;
}


static void SRInspectAudio(void)
{
    if (!@available(iOS 18.2, *)) {

        SRPopup(@"iOS 18.2+ required.");
        return;
    }


    AVAudioApplication *application =
        AVAudioApplication.sharedInstance;

    AVAudioSession *session =
        AVAudioSession.sharedInstance;


    BOOL injectionAvailable =
        session.isMicrophoneInjectionAvailable;


    NSString *permission =
        SRPermissionString();


    NSString *category =
        session.category ?: @"?";


    NSString *mode =
        session.mode ?: @"?";


    double sampleRate =
        session.sampleRate;


    double IOBuffer =
        session.IOBufferDuration;


    NSInteger inputChannels =
        session.inputNumberOfChannels;


    BOOL inputAvailable =
        session.isInputAvailable;


    AVAudioSessionRouteDescription *route =
        session.currentRoute;


    NSString *routeInfo =
        SRRouteDescription(route);


    NSString *preferredInput =
        session.preferredInput
        ? [NSString stringWithFormat:
           @"%@ | %@",
           session.preferredInput.portType ?: @"?",
           session.preferredInput.portName ?: @"?"]
        : @"NONE";


    BOOL otherAudio =
        session.isOtherAudioPlaying;


    BOOL recordPermission =
        (application.recordPermission ==
         AVAudioApplicationRecordPermissionGranted);


    NSString *message =
    [NSString stringWithFormat:

     @"INJECTION PERMISSION: %@\n"
     @"INJECTION AVAILABLE: %@\n\n"

     @"RECORD PERMISSION: %@\n"
     @"INPUT AVAILABLE: %@\n"
     @"INPUT CHANNELS: %ld\n\n"

     @"CATEGORY: %@\n"
     @"MODE: %@\n"
     @"SAMPLE RATE: %.1f Hz\n"
     @"IO BUFFER: %.4f sec\n\n"

     @"PREFERRED INPUT: %@\n"
     @"OTHER AUDIO PLAYING: %@\n\n"

     @"CURRENT ROUTE\n%@",

     permission,

     injectionAvailable
        ? @"YES"
        : @"NO",

     recordPermission
        ? @"GRANTED"
        : @"NOT GRANTED",

     inputAvailable
        ? @"YES"
        : @"NO",

     (long)inputChannels,

     category,

     mode,

     sampleRate,

     IOBuffer,

     preferredInput,

     otherAudio
        ? @"YES"
        : @"NO",

     routeInfo];


    NSLog(
        @"[SanneRealtime]\n%@",
        message
    );


    SRPopup(message);
}


static void SRSetInjectionMode(void)
{
    if (!@available(iOS 18.2, *))
        return;


    AVAudioSession *session =
        AVAudioSession.sharedInstance;


    if (!session.isMicrophoneInjectionAvailable) {

        SRPopup(
            @"Injection is currently NOT AVAILABLE.\n\n"
             "Start the Discord call and try again."
        );

        return;
    }


    NSError *error = nil;


    BOOL success =
        [session
         setPreferredMicrophoneInjectionMode:
            AVAudioSessionMicrophoneInjectionModeSpokenAudio
         error:&error];


    if (!success) {

        SRPopup(
            [NSString stringWithFormat:
                @"SPOKEN AUDIO FAILED\n\n%@",
                error.localizedDescription
                ?: @"Unknown error"]
        );

        return;
    }


    SRPopup(
        @"SPOKEN AUDIO MODE SET.\n\n"
         "No microphone engine was started.\n"
         "No audio session was taken over."
    );
}


static void SRRun(void)
{
    if (!@available(iOS 18.2, *)) {

        SRPopup(@"iOS 18.2+ required.");
        return;
    }


    /*
     * IMPORTANT:
     *
     * We intentionally do NOT:
     *
     * - create AVAudioEngine
     * - access inputNode
     * - install a tap
     * - change category
     * - change mode
     * - activate the session
     * - deactivate the session
     *
     * We only inspect the existing session.
     */


    SRInspectAudio();


    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            800 * NSEC_PER_MSEC
        ),
        dispatch_get_main_queue(),
        ^{

            SRSetInjectionMode();
        }
    );
}


__attribute__((constructor))
static void SanneRealtimeLoaded(void)
{
    NSLog(
        @"[SanneRealtime] ========================="
    );

    NSLog(
        @"[SanneRealtime] AUDIO ROUTE DIAGNOSTIC BUILD"
    );

    NSLog(
        @"[SanneRealtime] NO AVAudioEngine"
    );

    NSLog(
        @"[SanneRealtime] NO MICROPHONE CAPTURE"
    );

    NSLog(
        @"[SanneRealtime] ========================="
    );


    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    1500 * NSEC_PER_MSEC
                ),
                dispatch_get_main_queue(),
                ^{

                    SRRun();
                }
            );
        }
    );
}
