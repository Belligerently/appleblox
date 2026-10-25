#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Main-thread-only bridge. Availability checks never create a display or change configuration.
@interface ABTemporaryDisplay : NSObject
@property(nonatomic, readonly, getter=isActive) BOOL active;
@property(class, nonatomic, readonly) BOOL available;
- (BOOL)beginWithError:(NSError **)error NS_SWIFT_NAME(begin());
- (BOOL)stopWithError:(NSError **)error NS_SWIFT_NAME(stop());
@end
NS_ASSUME_NONNULL_END
