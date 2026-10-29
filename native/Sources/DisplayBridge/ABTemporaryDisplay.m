#import "ABTemporaryDisplay.h"
#import <CoreGraphics/CoreGraphics.h>

// Runtime-only declarations for the constructors/operations used by this bridge.
// No private framework symbols are linked; unsupported OS versions fail the capability check.
@protocol ABDisplayInitializer
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@end
@protocol ABModeInitializer
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)rate;
@end

@implementation ABTemporaryDisplay {
    id _display;
    CGDirectDisplayID _physical;
    CGDisplayModeRef _originalMode;
}
+ (BOOL)available {
    Class display = NSClassFromString(@"CGVirtualDisplay");
    Class descriptor = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class settings = NSClassFromString(@"CGVirtualDisplaySettings");
    Class mode = NSClassFromString(@"CGVirtualDisplayMode");
    return [display instancesRespondToSelector:@selector(initWithDescriptor:)] &&
           [display instancesRespondToSelector:@selector(applySettings:)] &&
           [display instancesRespondToSelector:NSSelectorFromString(@"displayID")] &&
           [descriptor instancesRespondToSelector:NSSelectorFromString(@"setMaxPixelsWide:")] &&
           [descriptor instancesRespondToSelector:NSSelectorFromString(@"setQueue:")] &&
           [settings instancesRespondToSelector:NSSelectorFromString(@"setModes:")] &&
           [mode instancesRespondToSelector:@selector(initWithWidth:height:refreshRate:)];
}
- (BOOL)isActive { return _display != nil; }
- (BOOL)fail:(NSError **)error message:(NSString *)message {
    if (error) *error = [NSError errorWithDomain:@"AppleBlox.TemporaryDisplay" code:1
                                      userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}
- (BOOL)beginWithError:(NSError **)error {
    if (![NSThread isMainThread]) return [self fail:error message:@"Display changes require the main thread."];
    if (_display) return YES;
    if (!ABTemporaryDisplay.available) return [self fail:error message:@"Temporary 240 Hz displays are unavailable on this macOS version."];
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(0, NULL, &count) != kCGErrorSuccess || count != 1)
        return [self fail:error message:@"The experimental FPS workaround currently requires one online display."];
    _physical = CGMainDisplayID();
    if (!_physical || CGDisplayIsInMirrorSet(_physical)) return [self fail:error message:@"Exit existing display mirroring before using this workaround."];
    _originalMode = CGDisplayCopyDisplayMode(_physical);
    if (!_originalMode) return [self fail:error message:@"Could not preserve the original display mode."];
    NSString *stage = @"display descriptor";
    @try {
        size_t width = CGDisplayModeGetPixelWidth(_originalMode), height = CGDisplayModeGetPixelHeight(_originalMode);
        size_t logicalWidth = CGDisplayModeGetWidth(_originalMode), logicalHeight = CGDisplayModeGetHeight(_originalMode);
        if (!width || !height || width > 16384 || height > 16384) @throw [NSException exceptionWithName:@"DisplayMode" reason:@"Unsupported dimensions" userInfo:nil];
        id descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
        [descriptor setValue:@"AppleBlox Temporary 240 Hz" forKey:@"name"];
        [descriptor setValue:dispatch_get_main_queue() forKey:@"queue"];
        [descriptor setValue:@(width) forKey:@"maxPixelsWide"];
        [descriptor setValue:@(height) forKey:@"maxPixelsHigh"];
        [descriptor setValue:[NSValue valueWithSize:CGDisplayScreenSize(_physical)] forKey:@"sizeInMillimeters"];
        [descriptor setValue:@(0xAB10) forKey:@"vendorID"];
        [descriptor setValue:@(240) forKey:@"productID"];
        [descriptor setValue:@(arc4random_uniform(UINT32_MAX - 1) + 1) forKey:@"serialNum"];
        stage = @"virtual display creation";
        _display = [(id<ABDisplayInitializer>)[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
        if (!_display) @throw [NSException exceptionWithName:@"DisplayCreation" reason:@"Display unavailable" userInfo:nil];
        stage = @"virtual display settings";
        BOOL retina = logicalWidth > 0 && logicalHeight > 0 && width == logicalWidth * 2 && height == logicalHeight * 2;
        size_t modeWidth = retina ? logicalWidth : width, modeHeight = retina ? logicalHeight : height;
        id mode = [(id<ABModeInitializer>)[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:modeWidth height:modeHeight refreshRate:240.0];
        id fallback = [(id<ABModeInitializer>)[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:modeWidth height:modeHeight refreshRate:60.0];
        id settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
        [settings setValue:@[mode, fallback] forKey:@"modes"];
        [settings setValue:@(retina ? 1 : 0) forKey:@"hiDPI"];
        if (![(id<ABDisplayInitializer>)_display applySettings:settings]) @throw [NSException exceptionWithName:@"DisplaySettings" reason:@"Settings rejected" userInfo:nil];
        CGDirectDisplayID virtualID = [[_display valueForKey:@"displayID"] unsignedIntValue];
        if (!virtualID || virtualID == _physical) @throw [NSException exceptionWithName:@"DisplayIdentity" reason:@"Invalid display" userInfo:nil];
        // Registration is asynchronous. Swift waits without blocking the main run loop.
        return YES;
    } @catch (NSException *exception) {
        // Exception descriptions can contain system details. Return a fixed user-facing error below.
    }
    NSError *cleanupError = nil;
    if (![self stopWithError:&cleanupError]) {
        if (error) *error = cleanupError;
        return NO;
    }
    return [self fail:error message:[NSString stringWithFormat:@"The temporary display could not start (%@). The original display mode was restored.", stage]];
}
- (BOOL)mirrorWhenReady:(BOOL *)ready error:(NSError **)error {
    *ready = NO;
    if (![NSThread isMainThread]) return [self fail:error message:@"Display changes require the main thread."];
    if (!_display) return [self fail:error message:@"The temporary display was stopped before it became ready."];
    CGDirectDisplayID virtualID = [[_display valueForKey:@"displayID"] unsignedIntValue];
    CGDirectDisplayID ids[32];
    uint32_t count = 0;
    if (CGGetActiveDisplayList(32, ids, &count) != kCGErrorSuccess)
        return [self fail:error message:@"Could not check temporary display readiness."];
    BOOL found = NO;
    for (uint32_t index = 0; index < count; index++) if (ids[index] == virtualID) found = YES;
    if (!found) return YES;
    CGDisplayConfigRef transaction = NULL;
    CGError result = CGBeginDisplayConfiguration(&transaction);
    if (result == kCGErrorSuccess) {
        result = CGConfigureDisplayMirrorOfDisplay(transaction, _physical, virtualID);
        if (result == kCGErrorSuccess) result = CGCompleteDisplayConfiguration(transaction, kCGConfigureForSession);
        else CGCancelDisplayConfiguration(transaction);
    }
    if (result != kCGErrorSuccess)
        return [self fail:error message:@"macOS rejected temporary display mirroring."];
    *ready = YES;
    return YES;
}
- (BOOL)stopWithError:(NSError **)error {
    if (![NSThread isMainThread]) return [self fail:error message:@"Display changes require the main thread."];
    // No resources means no display configuration calls, including during ordinary app shutdown.
    if (!_display) {
        if (_originalMode) { CGDisplayModeRelease(_originalMode); _originalMode = NULL; }
        _physical = 0;
        return YES;
    }
    if (CGDisplayIsOnline(_physical)) {
        CGDisplayConfigRef transaction = NULL;
        CGError result = CGBeginDisplayConfiguration(&transaction);
        if (result == kCGErrorSuccess) {
            result = CGConfigureDisplayMirrorOfDisplay(transaction, _physical, kCGNullDirectDisplay);
            if (result == kCGErrorSuccess && _originalMode)
                result = CGConfigureDisplayWithDisplayMode(transaction, _physical, _originalMode, NULL);
            if (result == kCGErrorSuccess) result = CGCompleteDisplayConfiguration(transaction, kCGConfigureForSession);
            else CGCancelDisplayConfiguration(transaction);
        }
        if (result != kCGErrorSuccess) return [self fail:error message:@"Could not restore the original display mode. Keep AppleBlox open and retry Stop FPS Workaround."];
    }
    _display = nil;
    if (_originalMode) { CGDisplayModeRelease(_originalMode); _originalMode = NULL; }
    _physical = 0;
    return YES;
}
- (void)dealloc {
    // Normal termination calls stop explicitly. Releasing the virtual display also removes it after failure.
    if ([NSThread isMainThread]) [self stopWithError:nil];
    if (_originalMode) CGDisplayModeRelease(_originalMode);
}
@end
