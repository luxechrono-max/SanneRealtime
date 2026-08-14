#import <Foundation/Foundation.h>

__attribute__((constructor))
static void SanneRealtimeLoaded(void) {
    NSLog(@"[SanneRealtime] DYLIB LOADED");
}
