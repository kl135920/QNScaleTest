#import <Foundation/Foundation.h>

@class QNBleDevice;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const QNScaleServiceAppId;

@protocol QNScaleServiceDelegate <NSObject>
- (void)scaleServiceDidUpdateState:(NSString *)state;
- (void)scaleServiceDidUpdateDevices:(NSArray<NSDictionary *> *)devices;
- (void)scaleServiceDidUpdateWeight:(double)weight state:(NSString *)state;
- (void)scaleServiceDidReceiveMeasurement:(NSDictionary *)measurement;
- (void)scaleServiceDidReceiveLog:(NSString *)line;
- (void)scaleServiceDidFinishInitialization:(BOOL)success error:(nullable NSError *)error;
@end

@interface QNScaleService : NSObject

+ (instancetype)sharedService;

@property (nonatomic, weak, nullable) id<QNScaleServiceDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *sdkVersion;
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@property (nonatomic, copy, readonly) NSString *sdkState;
@property (nonatomic, copy, readonly) NSString *bluetoothState;
@property (nonatomic, copy, readonly) NSString *connectionState;
@property (nonatomic, assign, readonly, getter=isScanning) BOOL scanning;
@property (nonatomic, copy, readonly, nullable) NSString *lastOperationError;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *devices;
@property (nonatomic, copy, readonly) NSString *debugLogText;
@property (nonatomic, copy, readonly, nullable) NSDictionary *latestRawMeasurement;
@property (nonatomic, copy, readonly) NSString *authorizationSummary;

- (void)initializeIfNeeded;
- (void)startScanning;
- (void)stopScanning;
- (void)connectToDeviceAtIndex:(NSUInteger)index
                        userId:(NSString *)userId
                      nickname:(NSString *)nickname
                        height:(NSInteger)height
                        gender:(NSString *)gender
                      birthday:(NSDate *)birthday
                   athleteType:(NSInteger)athleteType
                   previousHMAC:(nullable NSString *)previousHMAC;
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
