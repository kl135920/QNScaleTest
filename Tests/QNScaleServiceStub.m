#import "QNUITesting-Bridging-Header.h"

NSString * const QNScaleServiceAppId = @"ui-tests-only";

@interface QNScaleService ()
@property (nonatomic, copy, readwrite) NSString *connectionState;
@property (nonatomic, assign, readwrite, getter=isScanning) BOOL scanning;
@end

@implementation QNScaleService
+ (instancetype)sharedService {
    static QNScaleService *service;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        service = [[QNScaleService alloc] init];
        service.connectionState = @"未连接";
    });
    return service;
}
- (NSString *)sdkVersion { return @"2.37.1（模拟器隔离验证）"; }
- (NSString *)bundleIdentifier { return @"com.qingniu.sdk.test.tests"; }
- (NSString *)sdkState { return @"初始化成功"; }
- (NSString *)bluetoothState { return @"开启"; }
- (NSString *)lastOperationError { return nil; }
- (NSArray *)devices { return @[]; }
- (NSString *)debugLogText { return @"Simulator UI tests; no BLE session."; }
- (NSDictionary *)latestRawMeasurement { return nil; }
- (NSString *)authorizationSummary { return @"模拟器测试，不连接 QNSDK"; }
- (void)initializeIfNeeded {}
- (void)startScanning { self.scanning = YES; self.connectionState = @"未连接"; }
- (void)stopScanning { self.scanning = NO; }
- (void)disconnect { self.connectionState = @"未连接"; }
- (void)connectToDeviceAtIndex:(NSUInteger)index userId:(NSString *)userId nickname:(NSString *)nickname height:(NSInteger)height gender:(NSString *)gender birthday:(NSDate *)birthday athleteType:(NSInteger)athleteType previousHMAC:(NSString *)previousHMAC {}
@end

void QNSetScaleServiceTestState(NSString *connectionState, BOOL scanning) {
    QNScaleService.sharedService.connectionState = connectionState;
    QNScaleService.sharedService.scanning = scanning;
}
