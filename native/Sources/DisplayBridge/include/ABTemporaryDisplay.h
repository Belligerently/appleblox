#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Main-thread-only bridge. Availability checks never create a display or change configuration.
@interface ABTemporaryDisplay : NSObject
@property(nonatomic, readonly, getter=isActive) BOOL active;
@property(class, nonatomic, readonly) BOOL available;
- (BOOL)beginWithError:(NSError **)error NS_SWIFT_NAME(begin());
/// Successful calls set ready to NO while registering and YES once mirrored.
- (BOOL)mirrorWhenReady:(BOOL *)ready error:(NSError **)error NS_SWIFT_NAME(mirrorWhenReady(_:));
- (BOOL)stopWithError:(NSError **)error NS_SWIFT_NAME(stop());
@end
NS_ASSUME_NONNULL_END
