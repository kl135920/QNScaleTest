#import "QNScaleService.h"
#import "QNDeviceSDK.h"
#import <math.h>

NSString * const QNScaleServiceAppId = @"123456789";

@interface QNScaleService () <QNBleStateListener,
                                QNBleDeviceDiscoveryListener,
                                QNBleConnectionChangeListener,
                                QNScaleDataListener,
                                QNUserScaleDataListener,
                                QNLogProtocol>
@property (nonatomic, strong) QNBleApi *bleApi;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *mutableDevices;
@property (nonatomic, strong) NSMutableArray<NSString *> *logEntries;
@property (nonatomic, strong, nullable) QNBleDevice *selectedDevice;
@property (nonatomic, strong, nullable) QNUser *currentUser;
@property (nonatomic, copy) NSString *sdkVersion;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *sdkState;
@property (nonatomic, copy) NSString *bluetoothState;
@property (nonatomic, copy) NSString *connectionState;
@property (nonatomic, copy) NSString *authorizationSummary;
@property (nonatomic, copy, nullable) NSDictionary *latestRawMeasurement;
@property (nonatomic, assign) BOOL initialized;
@property (nonatomic, assign) BOOL scanning;
@property (nonatomic, assign) NSUInteger selectedIndex;
@end

@implementation QNScaleService

+ (instancetype)sharedService {
    static QNScaleService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [[self alloc] init];
    });
    return service;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableDevices = [NSMutableArray array];
        _logEntries = [NSMutableArray array];
        _sdkVersion = QNBleApi.sdkVersion ?: @"未知";
        _bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"<nil>";
        _sdkState = @"未初始化";
        _bluetoothState = @"未知";
        _connectionState = @"未连接";
        _authorizationSummary = @"等待初始化";
    }
    return self;
}

- (NSArray<NSDictionary *> *)devices {
    @synchronized (self) {
        return [self.mutableDevices copy];
    }
}

- (NSString *)debugLogText {
    @synchronized (self) {
        return [self.logEntries componentsJoinedByString:@"\n"];
    }
}

- (void)initializeIfNeeded {
    if (self.initialized || [self.sdkState hasPrefix:@"初始化中"]) {
        return;
    }
    self.bleApi = [QNBleApi sharedBleApi];
    self.bleApi.bleStateListener = self;
    self.bleApi.discoveryListener = self;
    self.bleApi.connectionChangeListener = self;
    self.bleApi.dataListener = self;
    self.bleApi.logListener = self;

    QNConfig *config = [self.bleApi getConfig];
    config.showPowerAlertKey = NO;
    config.onlyScreenOn = NO;
    config.allowDuplicates = YES;
    config.duration = 0;
    config.unit = QNUnitKG;
    [config save];
    QNBleApi.debug = YES;

    self.sdkVersion = QNBleApi.sdkVersion ?: @"未知";
    self.bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"<nil>";
    NSString *path = [NSBundle.mainBundle pathForResource:QNScaleServiceAppId ofType:@"qn"];
    [self appendLogCategory:@"SDK" message:[NSString stringWithFormat:@"初始化开始 sdkVersion=%@ appId=%@ bundleId=%@ firstDataFile=%@", self.sdkVersion, QNScaleServiceAppId, self.bundleIdentifier, path ?: @"<nil>"]];
    if (path.length == 0 || ![NSFileManager.defaultManager fileExistsAtPath:path]) {
        NSError *error = [NSError errorWithDomain:@"QNScaleService" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"Bundle 中缺少 123456789.qn"}];
        self.sdkState = @"初始化失败";
        [self finishInitialization:NO error:error];
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.sdkState = @"初始化中";
    [self.bleApi initSdk:QNScaleServiceAppId firstDataFile:path callback:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (error) {
                self.initialized = NO;
                self.sdkState = @"初始化失败";
                [self appendError:error category:@"SDK" context:@"初始化失败"];
                [self finishInitialization:NO error:error];
                return;
            }
            self.initialized = YES;
            self.sdkState = @"初始化成功";
            [self updateAuthorizationSummary];
            [self appendLogCategory:@"SDK" message:@"初始化成功"]; 
            [self finishInitialization:YES error:nil];
            [self updateBluetoothState:self.bleApi.getCurSystemBleState];
            if (self.bleApi.getCurSystemBleState == QNBLEStatePoweredOn) {
                [self startScanning];
            }
        });
    }];
}

- (void)finishInitialization:(BOOL)success error:(NSError *)error {
    id<QNScaleServiceDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(scaleServiceDidFinishInitialization:error:)]) {
        [delegate scaleServiceDidFinishInitialization:success error:error];
    }
}

- (void)updateAuthorizationSummary {
    NSDictionary *list = [self.bleApi readAuthDeviceInfoList];
    NSString *configuration = [self.bleApi readSDKConfigurationInfo] ?: @"<nil>";
    self.authorizationSummary = [NSString stringWithFormat:@"Bundle ID=%@\nauthorizationDeviceList=%@\nSDK configuration=%@", self.bundleIdentifier, list.description ?: @"<nil>", configuration];
    [self appendLogCategory:@"SDK" message:self.authorizationSummary];
}

- (void)startScanning {
    if (!self.initialized) {
        [self appendLogCategory:@"BLE" message:@"不能扫描：SDK 尚未初始化成功"];
        return;
    }
    [self appendLogCategory:@"BLE" message:@"开始扫描"]; 
    __weak typeof(self) weakSelf = self;
    [self.bleApi startBleDeviceDiscovery:^(NSError *error) {
        if (error) {
            [weakSelf appendError:error category:@"BLE" context:@"启动扫描失败"];
        }
    }];
}

- (void)stopScanning {
    if (!self.scanning) { return; }
    [self appendLogCategory:@"BLE" message:@"停止扫描"]; 
    __weak typeof(self) weakSelf = self;
    [self.bleApi stopBleDeviceDiscorvery:^(NSError *error) {
        if (error) {
            [weakSelf appendError:error category:@"BLE" context:@"停止扫描失败"];
        }
    }];
}

- (void)connectToDeviceAtIndex:(NSUInteger)index
                        userId:(NSString *)userId
                      nickname:(NSString *)nickname
                        height:(NSInteger)height
                        gender:(NSString *)gender
                      birthday:(NSDate *)birthday
                   athleteType:(NSInteger)athleteType
                   previousHMAC:(NSString *)previousHMAC {
    if (!self.initialized || index >= self.mutableDevices.count) {
        [self appendLogCategory:@"BLE" message:@"不能连接：SDK 未初始化或设备索引无效"]; 
        return;
    }
    self.selectedIndex = index;
    NSDictionary *deviceInfo = self.mutableDevices[index];
    QNBleDevice *device = deviceInfo[@"object"];
    if (![device isKindOfClass:QNBleDevice.class]) { return; }
    self.selectedDevice = device;
    [self stopScanning];
    __weak typeof(self) weakSelf = self;
    QNUser *user = [self.bleApi buildUser:userId height:(int)height gender:gender birthday:birthday callback:^(NSError *error) {
        if (error) { [weakSelf appendError:error category:@"SDK" context:@"buildUser 失败"]; }
    }];
    if (!user) {
        [self appendLogCategory:@"SDK" message:@"buildUser 返回 nil"]; 
        return;
    }
    user.athleteType = (YLAthleteType)athleteType;
    user.hmac = previousHMAC ?: @"";
    self.currentUser = user;
    self.connectionState = @"连接中";
    [self appendLogCategory:@"BLE" message:[NSString stringWithFormat:@"连接开始 name=%@ mac=%@ modeId=%@ type=%lu", device.bluetoothName ?: @"<nil>", device.mac ?: @"<nil>", device.modeId ?: @"<nil>", (unsigned long)device.deviceType]];
    QNResultCallback callback = ^(NSError *error) {
        if (error) { [weakSelf appendError:error category:@"BLE" context:@"连接请求失败"]; }
    };
    if (device.deviceType == QNDeviceTypeUserScale || device.deviceType == QNDeviceTypeSlimScale) {
        QNUserScaleConfig *config = [[QNUserScaleConfig alloc] init];
        config.curUser = user;
        config.isVisitor = YES;
        config.isCloseMeasureFat = NO;
        [self.bleApi connectUserScaleDevice:device config:config callback:callback];
    } else if (device.deviceType == QNDeviceTypeHeightScale) {
        QNHeightDeviceConfig *config = [[QNHeightDeviceConfig alloc] init];
        config.curUser = user;
        config.weightUnit = QNUnitKG;
        config.heightUnit = QNHeightUnitCM;
        config.voiceLanguage = QNLanguageZH;
        [self.bleApi connectHeightScaleDevice:device config:config callback:callback];
    } else {
        [self.bleApi connectDevice:device user:user callback:callback];
    }
}

- (void)disconnect {
    if (!self.selectedDevice) { return; }
    __weak typeof(self) weakSelf = self;
    [self.bleApi disconnectDevice:self.selectedDevice callback:^(NSError *error) {
        if (error) { [weakSelf appendError:error category:@"BLE" context:@"断开失败"]; }
    }];
}

#pragma mark - SDK delegates

- (void)onBleSystemState:(QNBLEState)state {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateBluetoothState:state]; });
}

- (void)updateBluetoothState:(QNBLEState)state {
    NSArray *names = @[@"未知", @"重置中", @"不支持", @"未授权", @"关闭", @"开启"];
    self.bluetoothState = state < names.count ? names[state] : [NSString stringWithFormat:@"未知(%lu)", (unsigned long)state];
    [self appendLogCategory:@"BLE" message:[NSString stringWithFormat:@"蓝牙状态：%@", self.bluetoothState]];
    [self notifyState];
}

- (void)onStartScan { self.scanning = YES; [self notifyState]; }
- (void)onStopScan { self.scanning = NO; [self notifyState]; }

- (void)onDeviceDiscover:(QNBleDevice *)device {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *key = device.mac.length ? device.mac : [NSString stringWithFormat:@"%@|%@", device.bluetoothName ?: @"", device.modeId ?: @""];
        for (NSUInteger i = 0; i < self.mutableDevices.count; i++) {
            if ([self.mutableDevices[i][@"deviceIdentifier"] isEqual:key]) {
                NSMutableDictionary *updated = [self deviceDictionary:device];
                [self.mutableDevices replaceObjectAtIndex:i withObject:updated];
                [self notifyDevices];
                return;
            }
        }
        [self.mutableDevices addObject:[self deviceDictionary:device]];
        [self appendLogCategory:@"BLE" message:[NSString stringWithFormat:@"发现设备 name=%@ bluetoothName=%@ deviceIdentifier=%@ modeId=%@ deviceType=%lu eight=%@", device.name ?: @"<nil>", device.bluetoothName ?: @"<nil>", device.mac ?: @"<nil>", device.modeId ?: @"<nil>", (unsigned long)device.deviceType, device.isSupportEightElectrodes ? @"YES" : @"NO"]];
        [self notifyDevices];
    });
}

- (NSMutableDictionary *)deviceDictionary:(QNBleDevice *)device {
    return [@{ @"object": device,
               @"bluetoothName": device.bluetoothName ?: NSNull.null,
               @"name": device.name ?: NSNull.null,
               @"deviceIdentifier": device.mac ?: NSNull.null,
               @"modeId": device.modeId ?: NSNull.null,
               @"deviceType": @(device.deviceType),
               @"deviceTypeName": [self deviceTypeName:device.deviceType],
               @"rssi": device.RSSI ?: NSNull.null,
               @"isSupportEightElectrodes": @(device.isSupportEightElectrodes),
               @"serviceUUIDs": device.advData.serviceUUIDs ?: @[] } mutableCopy];
}

- (void)onBroadcastDeviceDiscover:(QNBleBroadcastDevice *)device { [self appendLogCategory:@"BLE" message:[NSString stringWithFormat:@"发现广播秤 %@", device.name ?: @"<nil>"]]; }
- (void)onKitchenDeviceDiscover:(QNBleKitchenDevice *)device { [self appendLogCategory:@"BLE" message:[NSString stringWithFormat:@"发现厨房秤 %@", device.name ?: @"<nil>"]]; }

- (void)onConnecting:(QNBleDevice *)device { self.connectionState = @"连接中"; [self notifyState]; [self appendLogCategory:@"BLE" message:@"连接中"]; }
- (void)onConnected:(QNBleDevice *)device { self.connectionState = @"已连接"; [self notifyState]; [self appendLogCategory:@"BLE" message:@"连接成功"]; }
- (void)onServiceSearchComplete:(QNBleDevice *)device { [self appendLogCategory:@"BLE" message:@"服务搜索完成"]; }
- (void)onDisconnecting:(QNBleDevice *)device { self.connectionState = @"断开中"; [self notifyState]; }
- (void)onDisconnected:(QNBleDevice *)device { self.connectionState = @"未连接"; [self notifyState]; [self appendLogCategory:@"BLE" message:@"已断开"]; }
- (void)onConnectError:(QNBleDevice *)device error:(NSError *)error { self.connectionState = @"连接失败"; [self notifyState]; [self appendError:error category:@"BLE" context:@"连接错误"]; }
- (void)onStartInteracting:(QNBleDevice *)device { [self appendLogCategory:@"BLE" message:@"设备开始交互"]; }

- (void)onGetUnsteadyWeight:(QNBleDevice *)device weight:(double)weight {
    double kilograms = [self.bleApi convertWeightWithTargetUnit:weight unit:QNUnitKG];
    [self appendLogCategory:@"MEASURE" message:[NSString stringWithFormat:@"实时重量 %.2f kg", kilograms]];
    id<QNScaleServiceDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(scaleServiceDidUpdateWeight:state:)]) {
        [delegate scaleServiceDidUpdateWeight:kilograms state:@"实时重量"];
    }
}

- (void)onGetScaleData:(QNBleDevice *)device data:(QNScaleData *)scaleData {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *items = [scaleData getAllItem] ?: @[];
        NSMutableArray *itemJSON = [NSMutableArray arrayWithCapacity:items.count];
        for (QNScaleItemData *item in items) {
            [itemJSON addObject:@{ @"type": @(item.type), @"value": [self jsonNumber:item.value], @"valueType": @(item.valueType), @"name": item.name ?: NSNull.null, @"unit": NSNull.null, @"description": NSNull.null }];
        }
        QNUser *user = scaleData.user ?: self.currentUser;
        NSMutableDictionary *deviceJSON = [[self deviceDictionary:device] mutableCopy];
        [deviceJSON removeObjectForKey:@"object"];
        NSDictionary *measurement = @{
            @"metadata": @{ @"exportedAt": [self isoDate: NSDate.date], @"sdkVersion": self.sdkVersion ?: NSNull.null, @"appId": QNScaleServiceAppId, @"bundleIdentifier": self.bundleIdentifier ?: NSNull.null, @"authorizationDeviceList": self.authorizationSummary ?: NSNull.null },
            @"device": deviceJSON,
            @"user": @{ @"userId": user.userId ?: NSNull.null, @"height": @(user.height), @"gender": user.gender ?: NSNull.null, @"birthday": user.birthday ? [self isoDateOnly:user.birthday] : NSNull.null, @"athleteType": @(user.athleteType), @"hmac": user.hmac ?: NSNull.null, @"measureNum": @(user.measureNum) },
            @"scaleData": @{ @"measureTime": scaleData.measureTime ? [self isoDate:scaleData.measureTime] : NSNull.null, @"hmac": scaleData.hmac ?: NSNull.null, @"height": [self jsonNumber:scaleData.height], @"heightMode": @(scaleData.heightMode), @"weight": [self jsonNumber:scaleData.weight], @"resistance50": @(scaleData.resistance50), @"resistance500": @(scaleData.resistance500), @"barCode": scaleData.barCode ?: NSNull.null, @"newEightModel": @(scaleData.newEightModel), @"eightIsAbnormal": @(scaleData.eightIsAbnormal), @"eightReasonMask": @(scaleData.eightReasonMask) },
            @"items": itemJSON
        };
        self.latestRawMeasurement = measurement;
        [self appendLogCategory:@"DATA" message:[NSString stringWithFormat:@"QNScaleData=%@", measurement[@"scaleData"]]];
        [self appendLogCategory:@"DATA" message:[NSString stringWithFormat:@"device=%@", measurement[@"device"]]];
        [self appendLogCategory:@"DATA" message:[NSString stringWithFormat:@"user=%@", measurement[@"user"]]];
        [self appendLogCategory:@"DATA" message:[NSString stringWithFormat:@"收到最终数据，%lu 项，eightIsAbnormal=%ld reasonMask=%ld", (unsigned long)items.count, (long)scaleData.eightIsAbnormal, (long)scaleData.eightReasonMask]];
        for (NSDictionary *item in itemJSON) { [self appendLogCategory:@"DATA" message:item.description]; }
        id<QNScaleServiceDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(scaleServiceDidReceiveMeasurement:)]) { [delegate scaleServiceDidReceiveMeasurement:measurement]; }
    });
}

- (void)onGetStoredScale:(QNBleDevice *)device data:(NSArray<QNScaleStoreData *> *)storedDataList { [self appendLogCategory:@"DATA" message:[NSString stringWithFormat:@"收到存储数据 %lu 条", (unsigned long)storedDataList.count]]; }
- (void)onGetElectric:(NSUInteger)electric device:(QNBleDevice *)device { [self appendLogCategory:@"MEASURE" message:[NSString stringWithFormat:@"设备电量 %lu", (unsigned long)electric]]; }
- (void)onScaleStateChange:(QNBleDevice *)device scaleState:(QNScaleState)state { NSArray *names=@[@"未连接",@"连接丢失",@"已连接",@"正在连接",@"正在断开",@"开始测量",@"实时体重",@"测量生物阻抗",@"测量心率",@"测量完成"]; NSString *name=(state>=0 && state<names.count)?names[state]:[NSString stringWithFormat:@"状态 %ld",(long)state]; [self appendLogCategory:@"MEASURE" message:[NSString stringWithFormat:@"测量状态：%@", name]]; [self notifyWeightState:name]; }
- (void)onScaleEventChange:(QNBleDevice *)device scaleEvent:(QNScaleEvent)scaleEvent { [self appendLogCategory:@"MEASURE" message:[NSString stringWithFormat:@"秤事件：%ld", (long)scaleEvent]]; }
- (void)registerUserComplete:(QNBleDevice *)device user:(QNUser *)user { [self appendLogCategory:@"MEASURE" message:@"秤端注册用户完成"]; }
- (void)onLog:(NSString *)log { [self appendLogCategory:@"SDK" message:log ?: @"<nil>"]; }

#pragma mark - Presentation helpers

- (void)notifyState {
    dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate scaleServiceDidUpdateState:[NSString stringWithFormat:@"%@ / %@ / %@", self.sdkState, self.bluetoothState, self.connectionState]]; });
}
- (void)notifyDevices { dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate scaleServiceDidUpdateDevices:self.devices]; }); }
- (void)notifyWeightState:(NSString *)state { dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate scaleServiceDidUpdateWeight:NAN state:state]; }); }

- (id)jsonNumber:(double)value { if (isfinite(value)) return @(value); if (isnan(value)) return @"NaN"; return value > 0 ? @"Infinity" : @"-Infinity"; }
- (NSString *)isoDate:(NSDate *)date { NSDateFormatter *f=[NSDateFormatter new]; f.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; f.timeZone=NSTimeZone.localTimeZone; f.dateFormat=@"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"; return [f stringFromDate:date]; }
- (NSString *)isoDateOnly:(NSDate *)date { NSDateFormatter *f=[NSDateFormatter new]; f.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; f.dateFormat=@"yyyy-MM-dd"; return [f stringFromDate:date]; }
- (NSString *)deviceTypeName:(QNDeviceType)type { switch(type){case QNDeviceTypeScaleBleDefault:return @"ScaleBleDefault";case QNDeviceTypeScaleBroadcast:return @"ScaleBroadcast";case QNDeviceTypeScaleKitchen:return @"ScaleKitchen";case QNDeviceTypeUserScale:return @"UserScale";case QNDeviceTypeHeightScale:return @"HeightScale";case QNDeviceTypeSlimScale:return @"SlimScale";} return [NSString stringWithFormat:@"Unknown(%lu)",(unsigned long)type]; }
- (void)appendError:(NSError *)error category:(NSString *)category context:(NSString *)context { [self appendLogCategory:category message:[NSString stringWithFormat:@"%@ domain=%@ code=%ld description=%@ userInfo=%@", context,error.domain ?: @"<nil>",(long)error.code,error.localizedDescription ?: @"<nil>",error.userInfo ?: @{}]]; }
- (void)appendLogCategory:(NSString *)category message:(NSString *)message { dispatch_async(dispatch_get_main_queue(), ^{ NSDateFormatter *f=[NSDateFormatter new]; f.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; f.dateFormat=@"yyyy-MM-dd HH:mm:ss.SSS"; NSString *line=[NSString stringWithFormat:@"[%@][%@] %@",[f stringFromDate:NSDate.date],category,message]; @synchronized(self){[self.logEntries addObject:line];} NSLog(@"%@",line); [self.delegate scaleServiceDidReceiveLog:line]; }); }

@end
