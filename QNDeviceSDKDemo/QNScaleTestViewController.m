#import "QNScaleTestViewController.h"

#import "QNDeviceSDK.h"
#import <math.h>

static NSString * const QNTestAppId = @"123456789";
static NSString * const QNTargetBluetoothName = @"QN-Scale";
static NSString * const QNExpectedModeId = @"CS10B";
static NSString * const QNExpectedBundleId = @"com.qingniu.sdk.test";
static NSString * const QNTestUserId = @"test001";
static NSString * const QNTestGender = @"male";
static NSString * const QNDefaultBirthday = @"1990-01-01";
static const NSInteger QNTestHeight = 169;

@interface QNScaleTestViewController () <UITableViewDataSource,
                                          UITableViewDelegate,
                                          QNBleStateListener,
                                          QNBleDeviceDiscoveryListener,
                                          QNBleConnectionChangeListener,
                                          QNUserScaleDataListener,
                                          QNLogProtocol>

@property (nonatomic, strong) QNBleApi *bleApi;
@property (nonatomic, strong) NSMutableArray<QNBleDevice *> *devices;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *deviceIndexes;
@property (nonatomic, strong) NSMutableArray<NSString *> *logEntries;
@property (nonatomic, strong, nullable) QNBleDevice *selectedDevice;
@property (nonatomic, strong, nullable) QNUser *currentUser;
@property (nonatomic, strong, nullable) NSDictionary *latestMeasurementJSON;
@property (nonatomic, strong, nullable) NSDictionary *authorizedDeviceList;

@property (nonatomic, strong) UILabel *sdkStatusLabel;
@property (nonatomic, strong) UILabel *authorizationStatusLabel;
@property (nonatomic, strong) UILabel *bleStatusLabel;
@property (nonatomic, strong) UILabel *weightLabel;
@property (nonatomic, strong) UILabel *measurementStatusLabel;
@property (nonatomic, strong) UIDatePicker *birthdayPicker;
@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *exportJSONButton;
@property (nonatomic, strong) UITableView *deviceTableView;
@property (nonatomic, strong) UITextView *logTextView;

@property (nonatomic, assign) BOOL sdkInitialized;
@property (nonatomic, assign) BOOL scanning;
@property (nonatomic, assign) BOOL didStartInitialScan;
@property (nonatomic, assign) QNBLEState bluetoothState;

@end

@implementation QNScaleTestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"QNScaleTest";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.devices = [NSMutableArray array];
    self.deviceIndexes = [NSMutableDictionary dictionary];
    self.logEntries = [NSMutableArray array];
    self.bluetoothState = QNBLEStateUnknown;

    [self buildInterface];
    [self configureAndInitializeSDK];
}

#pragma mark - Interface

- (UILabel *)statusLabelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.numberOfLines = 0;
    label.text = text;
    return label;
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.layer.cornerRadius = 8.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = UIColor.systemBlueColor.CGColor;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:42.0].active = YES;
    return button;
}

- (void)buildInterface {
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:scrollView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8.0;
    [scrollView addSubview:stack];

    UILabel *profileLabel = [self statusLabelWithText:
        [NSString stringWithFormat:@"测试用户：%@ / %ld cm / %@", QNTestUserId, (long)QNTestHeight, QNTestGender]];
    profileLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];

    self.sdkStatusLabel = [self statusLabelWithText:@"SDK 状态：未初始化"];
    self.authorizationStatusLabel = [self statusLabelWithText:@"授权检查：等待初始化"];
    self.bleStatusLabel = [self statusLabelWithText:@"蓝牙状态：未知"];

    UILabel *birthdayLabel = [self statusLabelWithText:@"生日（测真实体脂时请填写真实生日）："];
    self.birthdayPicker = [[UIDatePicker alloc] init];
    self.birthdayPicker.datePickerMode = UIDatePickerModeDate;
    self.birthdayPicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    self.birthdayPicker.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    self.birthdayPicker.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    self.birthdayPicker.minimumDate = [calendar dateByAddingUnit:NSCalendarUnitYear value:-80 toDate:NSDate.date options:0];
    self.birthdayPicker.maximumDate = [calendar dateByAddingUnit:NSCalendarUnitYear value:-3 toDate:NSDate.date options:0];
    self.birthdayPicker.date = [self dateFromISODateString:QNDefaultBirthday] ?: NSDate.date;

    UIStackView *birthdayStack = [[UIStackView alloc] initWithArrangedSubviews:@[birthdayLabel, self.birthdayPicker]];
    birthdayStack.axis = UILayoutConstraintAxisHorizontal;
    birthdayStack.alignment = UIStackViewAlignmentCenter;
    birthdayStack.distribution = UIStackViewDistributionFill;
    birthdayStack.spacing = 8.0;

    self.scanButton = [self buttonWithTitle:@"开始扫描" action:@selector(scanButtonTapped:)];
    self.scanButton.enabled = NO;

    UILabel *deviceTitle = [self statusLabelWithText:@"扫描结果（QN-Scale / CS10B 仅作提示，可任选设备）："];
    self.deviceTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.deviceTableView.dataSource = self;
    self.deviceTableView.delegate = self;
    self.deviceTableView.layer.borderWidth = 1.0;
    self.deviceTableView.layer.borderColor = UIColor.separatorColor.CGColor;
    self.deviceTableView.layer.cornerRadius = 8.0;
    [self.deviceTableView.heightAnchor constraintEqualToConstant:190.0].active = YES;

    self.connectButton = [self buttonWithTitle:@"请选择设备" action:@selector(connectButtonTapped:)];
    self.connectButton.enabled = NO;

    self.weightLabel = [self statusLabelWithText:@"实时重量：-- kg"];
    self.weightLabel.font = [UIFont monospacedDigitSystemFontOfSize:22.0 weight:UIFontWeightSemibold];
    self.measurementStatusLabel = [self statusLabelWithText:@"测量状态：等待连接"];

    UIButton *copyLogButton = [self buttonWithTitle:@"复制日志" action:@selector(copyLogTapped:)];
    UIButton *shareLogButton = [self buttonWithTitle:@"分享日志" action:@selector(shareLogTapped:)];
    self.exportJSONButton = [self buttonWithTitle:@"导出 JSON" action:@selector(exportJSONTapped:)];
    self.exportJSONButton.enabled = NO;
    UIStackView *exportStack = [[UIStackView alloc] initWithArrangedSubviews:@[copyLogButton, shareLogButton, self.exportJSONButton]];
    exportStack.axis = UILayoutConstraintAxisHorizontal;
    exportStack.distribution = UIStackViewDistributionFillEqually;
    exportStack.spacing = 8.0;

    UILabel *logTitle = [self statusLabelWithText:@"Debug Log："];
    self.logTextView = [[UITextView alloc] init];
    self.logTextView.editable = NO;
    self.logTextView.selectable = YES;
    self.logTextView.alwaysBounceVertical = YES;
    self.logTextView.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    self.logTextView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.logTextView.layer.cornerRadius = 8.0;
    [self.logTextView.heightAnchor constraintEqualToConstant:360.0].active = YES;

    for (UIView *view in @[profileLabel,
                           self.sdkStatusLabel,
                           self.authorizationStatusLabel,
                           self.bleStatusLabel,
                           birthdayStack,
                           self.scanButton,
                           deviceTitle,
                           self.deviceTableView,
                           self.connectButton,
                           self.weightLabel,
                           self.measurementStatusLabel,
                           exportStack,
                           logTitle,
                           self.logTextView]) {
        [stack addArrangedSubview:view];
    }

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:12.0],
        [stack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor constant:12.0],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor constant:-12.0],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor constant:-20.0],
        [stack.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor constant:-24.0],
    ]];
}

#pragma mark - SDK initialization and authorization

- (void)configureAndInitializeSDK {
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
    NSString *bundleId = NSBundle.mainBundle.bundleIdentifier ?: @"<nil>";
    NSString *configurationPath = [NSBundle.mainBundle pathForResource:QNTestAppId ofType:@"qn"];
    [self appendLog:@"SDK" message:[NSString stringWithFormat:@"初始化开始 sdkVersion=%@ appId=%@ bundleId=%@", QNBleApi.sdkVersion, QNTestAppId, bundleId]];
    [self appendLog:@"SDK" message:[NSString stringWithFormat:@"firstDataFile=%@", configurationPath ?: @"<nil>"]];

    if (configurationPath.length == 0 || ![NSFileManager.defaultManager fileExistsAtPath:configurationPath]) {
        self.sdkStatusLabel.text = @"SDK 状态：初始化失败（缺少 123456789.qn）";
        [self appendLog:@"SDK" message:@"初始化停止：bundle 中不存在 123456789.qn"];
        return;
    }

    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:configurationPath error:nil];
    [self appendLog:@"SDK" message:[NSString stringWithFormat:@"配置文件大小=%@ bytes", attributes[NSFileSize] ?: @"未知"]];

    __weak typeof(self) weakSelf = self;
    [self.bleApi initSdk:QNTestAppId firstDataFile:configurationPath callback:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (error) {
                self.sdkInitialized = NO;
                self.sdkStatusLabel.text = [NSString stringWithFormat:@"SDK 状态：初始化失败（%ld）%@", (long)error.code, error.localizedDescription ?: @""];
                [self appendError:error category:@"SDK" context:@"初始化失败"];
                [self updateAuthorizationStatusWithSDKInitialized:NO];
                return;
            }

            self.sdkInitialized = YES;
            self.sdkStatusLabel.text = [NSString stringWithFormat:@"SDK 状态：初始化成功（%@）", QNBleApi.sdkVersion];
            self.scanButton.enabled = YES;
            [self appendLog:@"SDK" message:@"初始化成功"];
            [self updateAuthorizationStatusWithSDKInitialized:YES];
            self.bluetoothState = [self.bleApi getCurSystemBleState];
            [self updateBluetoothState:self.bluetoothState];
            [self startInitialScanIfReady];
        });
    }];
}

- (void)updateAuthorizationStatusWithSDKInitialized:(BOOL)initialized {
    NSString *bundleId = NSBundle.mainBundle.bundleIdentifier ?: @"<nil>";
    BOOL bundleMatches = [bundleId isEqualToString:QNExpectedBundleId];
    if (!initialized) {
        self.authorizationStatusLabel.text = [NSString stringWithFormat:@"授权检查：初始化失败\n最终 Bundle ID：%@", bundleId];
        return;
    }

    self.authorizedDeviceList = [self.bleApi readAuthDeviceInfoList];
    NSString *configurationInfo = [self.bleApi readSDKConfigurationInfo];
    NSString *deviceListText = self.authorizedDeviceList.description ?: @"<nil>";
    BOOL containsModel = [deviceListText rangeOfString:QNExpectedModeId options:NSCaseInsensitiveSearch].location != NSNotFound;
    self.authorizationStatusLabel.text = [NSString stringWithFormat:
        @"授权检查：Bundle ID %@；设备列表%@ %@\n最终 Bundle ID：%@",
        bundleMatches ? @"与 Demo 一致" : @"已被重写",
        containsModel ? @"包含" : @"未直接发现",
        QNExpectedModeId,
        bundleId];
    [self appendLog:@"SDK" message:[NSString stringWithFormat:@"Bundle ID check expected=%@ actual=%@ match=%@", QNExpectedBundleId, bundleId, bundleMatches ? @"YES" : @"NO"]];
    [self appendLog:@"SDK" message:[NSString stringWithFormat:@"授权设备列表包含 %@=%@ list=%@", QNExpectedModeId, containsModel ? @"YES" : @"NO", deviceListText]];
    [self appendLog:@"SDK" message:[NSString stringWithFormat:@"SDK 配置信息=%@", configurationInfo ?: @"<nil>"]];
}

#pragma mark - Scan and connection

- (void)scanButtonTapped:(UIButton *)sender {
    if (self.scanning) {
        [self stopScanning];
    } else {
        [self startScanningClearingExistingDevices:YES];
    }
}

- (void)startInitialScanIfReady {
    if (self.sdkInitialized && self.bluetoothState == QNBLEStatePoweredOn && !self.didStartInitialScan) {
        self.didStartInitialScan = YES;
        [self startScanningClearingExistingDevices:YES];
    }
}

- (void)startScanningClearingExistingDevices:(BOOL)clearDevices {
    if (!self.sdkInitialized) {
        [self appendLog:@"BLE" message:@"不能扫描：SDK 尚未初始化成功"];
        return;
    }
    if (clearDevices) {
        [self.devices removeAllObjects];
        [self.deviceIndexes removeAllObjects];
        self.selectedDevice = nil;
        self.connectButton.enabled = NO;
        [self.connectButton setTitle:@"请选择设备" forState:UIControlStateNormal];
        [self.deviceTableView reloadData];
    }
    [self appendLog:@"BLE" message:@"开始扫描"];
    __weak typeof(self) weakSelf = self;
    [self.bleApi startBleDeviceDiscovery:^(NSError *error) {
        if (error) {
            [weakSelf appendError:error category:@"BLE" context:@"启动扫描失败"];
        } else {
            [weakSelf appendLog:@"BLE" message:@"启动扫描请求成功"];
        }
    }];
}

- (void)stopScanning {
    [self appendLog:@"BLE" message:@"请求停止扫描"];
    __weak typeof(self) weakSelf = self;
    [self.bleApi stopBleDeviceDiscorvery:^(NSError *error) {
        if (error) {
            [weakSelf appendError:error category:@"BLE" context:@"停止扫描失败"];
        }
    }];
}

- (void)connectButtonTapped:(UIButton *)sender {
    QNBleDevice *device = self.selectedDevice;
    if (!device || !self.sdkInitialized) {
        [self appendLog:@"BLE" message:@"不能连接：未选择设备或 SDK 未初始化"];
        return;
    }
    [self stopScanning];

    __weak typeof(self) weakSelf = self;
    QNUser *user = [self.bleApi buildUser:QNTestUserId
                                   height:(int)QNTestHeight
                                   gender:QNTestGender
                                 birthday:self.birthdayPicker.date
                                 callback:^(NSError *error) {
        if (error) {
            [weakSelf appendError:error category:@"SDK" context:@"buildUser 失败"];
        }
    }];
    if (!user) {
        [self appendLog:@"SDK" message:@"buildUser 返回 nil，连接停止"];
        return;
    }
    user.hmac = @"";
    self.currentUser = user;

    NSString *birthday = [self isoDateStringFromDate:user.birthday includeTime:NO];
    [self appendLog:@"BLE" message:[NSString stringWithFormat:@"连接开始 bluetoothName=%@ name=%@ mac=%@ modeId=%@ deviceType=%@ birthday=%@",
                                      device.bluetoothName ?: @"<nil>",
                                      device.name ?: @"<nil>",
                                      device.mac ?: @"<nil>",
                                      device.modeId ?: @"<nil>",
                                      [self stringForDeviceType:device.deviceType],
                                      birthday]];
    self.measurementStatusLabel.text = @"测量状态：正在连接";

    QNResultCallback callback = ^(NSError *error) {
        if (error) {
            [weakSelf appendError:error category:@"BLE" context:@"连接请求失败"];
        } else {
            [weakSelf appendLog:@"BLE" message:@"连接请求已被 SDK 接受，等待连接状态回调"];
        }
    };

    if (device.deviceType == QNDeviceTypeUserScale || device.deviceType == QNDeviceTypeSlimScale) {
        QNUserScaleConfig *config = [[QNUserScaleConfig alloc] init];
        config.curUser = user;
        config.curUser.hmac = @"";
        config.isVisitor = YES;
        config.isCloseMeasureFat = NO;
        [self appendLog:@"BLE" message:@"使用 connectUserScaleDevice，游客模式，不伪造 index/secret"];
        [self.bleApi connectUserScaleDevice:device config:config callback:callback];
    } else if (device.deviceType == QNDeviceTypeHeightScale) {
        QNHeightDeviceConfig *config = [[QNHeightDeviceConfig alloc] init];
        config.curUser = user;
        config.weightUnit = QNUnitKG;
        config.heightUnit = QNHeightUnitCM;
        config.voiceLanguage = QNLanguageZH;
        [self appendLog:@"BLE" message:@"使用 connectHeightScaleDevice"];
        [self.bleApi connectHeightScaleDevice:device config:config callback:callback];
    } else {
        [self appendLog:@"BLE" message:@"使用 connectDevice:user:"];
        [self.bleApi connectDevice:device user:user callback:callback];
    }
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.devices.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"QNDeviceCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    QNBleDevice *device = self.devices[indexPath.row];
    BOOL targetName = device.bluetoothName.length > 0 && [device.bluetoothName caseInsensitiveCompare:QNTargetBluetoothName] == NSOrderedSame;
    BOOL targetModel = device.modeId.length > 0 && [device.modeId caseInsensitiveCompare:QNExpectedModeId] == NSOrderedSame;
    NSString *marker = targetName || targetModel ? @"★ " : @"";
    cell.textLabel.text = [NSString stringWithFormat:@"%@%@ / %@", marker, device.bluetoothName ?: @"<无蓝牙名>", device.name ?: @"<无设备名>"];
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"ID:%@  modeId:%@  type:%@  eight:%@",
                                 device.mac ?: @"<nil>",
                                 device.modeId ?: @"<nil>",
                                 [self stringForDeviceType:device.deviceType],
                                 device.isSupportEightElectrodes ? @"YES" : @"NO"];
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = device == self.selectedDevice ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.selectedDevice = self.devices[indexPath.row];
    self.connectButton.enabled = YES;
    NSString *name = self.selectedDevice.bluetoothName ?: self.selectedDevice.name ?: @"设备";
    [self.connectButton setTitle:[NSString stringWithFormat:@"连接 %@", name] forState:UIControlStateNormal];
    [self.deviceTableView reloadData];
    [self appendLog:@"BLE" message:[NSString stringWithFormat:@"已选择设备 bluetoothName=%@ mac=%@ modeId=%@",
                                      self.selectedDevice.bluetoothName ?: @"<nil>",
                                      self.selectedDevice.mac ?: @"<nil>",
                                      self.selectedDevice.modeId ?: @"<nil>"]];
}

#pragma mark - Discovery and Bluetooth state

- (void)onBleSystemState:(QNBLEState)state {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.bluetoothState = state;
        [self updateBluetoothState:state];
        [self startInitialScanIfReady];
    });
}

- (void)updateBluetoothState:(QNBLEState)state {
    NSString *stateText = [self stringForBluetoothState:state];
    self.bleStatusLabel.text = [NSString stringWithFormat:@"蓝牙状态：%@", stateText];
    [self appendLog:@"BLE" message:[NSString stringWithFormat:@"系统蓝牙状态变化：%@ (%lu)", stateText, (unsigned long)state]];
}

- (void)onStartScan {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.scanning = YES;
        [self.scanButton setTitle:@"停止扫描" forState:UIControlStateNormal];
        [self appendLog:@"BLE" message:@"扫描已开始"];
    });
}

- (void)onStopScan {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.scanning = NO;
        [self.scanButton setTitle:@"重新扫描" forState:UIControlStateNormal];
        [self appendLog:@"BLE" message:@"扫描已停止"];
    });
}

- (void)onDeviceDiscover:(QNBleDevice *)device {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *key = device.mac.length > 0 ? device.mac : [NSString stringWithFormat:@"%@|%@", device.bluetoothName ?: @"", device.modeId ?: @""];
        NSNumber *existingIndex = self.deviceIndexes[key];
        if (existingIndex) {
            NSUInteger index = existingIndex.unsignedIntegerValue;
            if (index < self.devices.count) {
                self.devices[index] = device;
                if ([self.selectedDevice.mac isEqualToString:device.mac]) {
                    self.selectedDevice = device;
                }
                [self.deviceTableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
            }
            return;
        }

        NSUInteger index = self.devices.count;
        self.deviceIndexes[key] = @(index);
        [self.devices addObject:device];
        [self.deviceTableView reloadData];
        BOOL targetName = device.bluetoothName.length > 0 && [device.bluetoothName caseInsensitiveCompare:QNTargetBluetoothName] == NSOrderedSame;
        BOOL targetModel = device.modeId.length > 0 && [device.modeId caseInsensitiveCompare:QNExpectedModeId] == NSOrderedSame;
        [self appendLog:@"BLE" message:[NSString stringWithFormat:@"发现设备 bluetoothName=%@ name=%@ SDK标识(mac)=%@ modeId=%@ deviceType=%@ eight=%@ targetName=%@ targetModel=%@；SDK 未公开 peripheral UUID",
                                          device.bluetoothName ?: @"<nil>",
                                          device.name ?: @"<nil>",
                                          device.mac ?: @"<nil>",
                                          device.modeId ?: @"<nil>",
                                          [self stringForDeviceType:device.deviceType],
                                          device.isSupportEightElectrodes ? @"YES" : @"NO",
                                          targetName ? @"YES" : @"NO",
                                          targetModel ? @"YES" : @"NO"]];
    });
}

- (void)onBroadcastDeviceDiscover:(QNBleBroadcastDevice *)device {
    [self appendLog:@"BLE" message:[NSString stringWithFormat:@"发现广播秤 name=%@ mac=%@（本阶段不生成算法数据）", device.name ?: @"<nil>", device.mac ?: @"<nil>"]];
}

- (void)onKitchenDeviceDiscover:(QNBleKitchenDevice *)device {
    [self appendLog:@"BLE" message:[NSString stringWithFormat:@"发现厨房秤 name=%@ mac=%@（不在本阶段范围）", device.name ?: @"<nil>", device.mac ?: @"<nil>"]];
}

#pragma mark - Connection callbacks

- (void)onConnecting:(QNBleDevice *)device {
    [self connectionLog:@"正在连接" device:device];
}

- (void)onConnected:(QNBleDevice *)device {
    [self connectionLog:@"连接成功" device:device];
}

- (void)onServiceSearchComplete:(QNBleDevice *)device {
    [self connectionLog:@"服务搜索完成" device:device];
}

- (void)onDisconnecting:(QNBleDevice *)device {
    [self connectionLog:@"正在断开" device:device];
}

- (void)onDisconnected:(QNBleDevice *)device {
    [self connectionLog:@"已断开" device:device];
}

- (void)onConnectError:(QNBleDevice *)device error:(NSError *)error {
    [self appendError:error category:@"BLE" context:[NSString stringWithFormat:@"连接错误 device=%@", device.mac ?: @"<nil>"]];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.measurementStatusLabel.text = [NSString stringWithFormat:@"测量状态：连接失败（%ld）", (long)error.code];
    });
}

- (void)onStartInteracting:(QNBleDevice *)device {
    [self connectionLog:@"设备开始交互" device:device];
}

- (void)connectionLog:(NSString *)status device:(QNBleDevice *)device {
    [self appendLog:@"BLE" message:[NSString stringWithFormat:@"%@ mac=%@ modeId=%@", status, device.mac ?: @"<nil>", device.modeId ?: @"<nil>"]];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.measurementStatusLabel.text = [NSString stringWithFormat:@"测量状态：%@", status];
    });
}

#pragma mark - Measurement callbacks

- (void)onGetUnsteadyWeight:(QNBleDevice *)device weight:(double)weight {
    double kilograms = [self.bleApi convertWeightWithTargetUnit:weight unit:QNUnitKG];
    [self appendLog:@"MEASURE" message:[NSString stringWithFormat:@"实时重量 %.2f kg mac=%@", kilograms, device.mac ?: @"<nil>"]];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.weightLabel.text = [NSString stringWithFormat:@"实时重量：%.2f kg", kilograms];
    });
}

- (void)onGetScaleData:(QNBleDevice *)device data:(QNScaleData *)scaleData {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self onGetScaleData:device data:scaleData];
        });
        return;
    }

    [self appendLog:@"MEASURE" message:@"收到最终 onGetScaleData"];
    [self appendLog:@"DATA" message:[NSString stringWithFormat:@"measureTime=%@ hmac=%@ height=%.2f heightMode=%lu weight=%.2f resistance50=%ld resistance500=%ld barCode=%@ newEightModel=%ld eightIsAbnormal=%ld eightReasonMask=%ld",
                                       [self isoDateStringFromDate:scaleData.measureTime includeTime:YES],
                                       scaleData.hmac ?: @"<nil>",
                                       scaleData.height,
                                       (unsigned long)scaleData.heightMode,
                                       scaleData.weight,
                                       (long)scaleData.resistance50,
                                       (long)scaleData.resistance500,
                                       scaleData.barCode ?: @"<nil>",
                                       (long)scaleData.newEightModel,
                                       (long)scaleData.eightIsAbnormal,
                                       (long)scaleData.eightReasonMask]];

    NSArray<QNScaleItemData *> *items = [scaleData getAllItem] ?: @[];
    [items enumerateObjectsUsingBlock:^(QNScaleItemData *item, NSUInteger index, BOOL *stop) {
        [self appendLog:@"DATA" message:[NSString stringWithFormat:@"item[%lu] type=%ld value=%.10g valueType=%lu name=%@ unit=<SDK未提供> description=<SDK未提供>",
                                           (unsigned long)index,
                                           (long)item.type,
                                           item.value,
                                           (unsigned long)item.valueType,
                                           item.name ?: @"<nil>"]];
    }];

    self.latestMeasurementJSON = [self measurementDictionaryForDevice:device scaleData:scaleData items:items];
    self.exportJSONButton.enabled = YES;
    self.weightLabel.text = [NSString stringWithFormat:@"最终重量：%.2f kg", scaleData.weight];
    self.measurementStatusLabel.text = [NSString stringWithFormat:@"测量状态：完成，收到 %lu 项指标", (unsigned long)items.count];
}

- (void)onGetStoredScale:(QNBleDevice *)device data:(NSArray<QNScaleStoreData *> *)storedDataList {
    [self appendLog:@"DATA" message:[NSString stringWithFormat:@"收到存储数据 %lu 条 mac=%@", (unsigned long)storedDataList.count, device.mac ?: @"<nil>"]];
}

- (void)onGetElectric:(NSUInteger)electric device:(QNBleDevice *)device {
    [self appendLog:@"MEASURE" message:[NSString stringWithFormat:@"设备电量=%lu mac=%@", (unsigned long)electric, device.mac ?: @"<nil>"]];
}

- (void)onScaleStateChange:(QNBleDevice *)device scaleState:(QNScaleState)state {
    NSString *stateText = [self stringForScaleState:state];
    [self appendLog:@"MEASURE" message:[NSString stringWithFormat:@"测量状态变化 %@ (%ld) mac=%@", stateText, (long)state, device.mac ?: @"<nil>"]];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.measurementStatusLabel.text = [NSString stringWithFormat:@"测量状态：%@", stateText];
    });
}

- (void)onScaleEventChange:(QNBleDevice *)device scaleEvent:(QNScaleEvent)scaleEvent {
    [self appendLog:@"MEASURE" message:[NSString stringWithFormat:@"秤事件=%ld mac=%@", (long)scaleEvent, device.mac ?: @"<nil>"]];
}

- (void)registerUserComplete:(QNBleDevice *)device user:(QNUser *)user {
    [self appendLog:@"MEASURE" message:[NSString stringWithFormat:@"秤端注册用户完成 index=%d secret=%d mac=%@", user.index, user.secret, device.mac ?: @"<nil>"]];
}

#pragma mark - JSON and sharing

- (NSDictionary *)measurementDictionaryForDevice:(QNBleDevice *)device
                                         scaleData:(QNScaleData *)scaleData
                                             items:(NSArray<QNScaleItemData *> *)items {
    NSMutableArray *itemJSON = [NSMutableArray arrayWithCapacity:items.count];
    for (QNScaleItemData *item in items) {
        [itemJSON addObject:@{
            @"type": @(item.type),
            @"value": [self jsonValueForDouble:item.value],
            @"valueType": @(item.valueType),
            @"valueTypeName": item.valueType == QNValueTypeInt ? @"int" : @"double",
            @"name": item.name ?: NSNull.null,
            @"unit": NSNull.null,
            @"description": NSNull.null,
        }];
    }

    QNUser *user = scaleData.user ?: self.currentUser;
    NSDictionary *userJSON = @{
        @"userId": user.userId ?: NSNull.null,
        @"height": @(user.height),
        @"gender": user.gender ?: NSNull.null,
        @"birthday": user.birthday ? [self isoDateStringFromDate:user.birthday includeTime:NO] : NSNull.null,
        @"athleteType": @(user.athleteType),
        @"shapeType": @(user.shapeType),
        @"goalType": @(user.goalType),
        @"index": @(user.index),
        @"secret": @(user.secret),
        @"hmac": user.hmac ?: NSNull.null,
        @"measureNum": @(user.measureNum),
    };

    NSDictionary *deviceJSON = @{
        @"bluetoothName": device.bluetoothName ?: NSNull.null,
        @"name": device.name ?: NSNull.null,
        @"sdkIdentifierMac": device.mac ?: NSNull.null,
        @"peripheralUUID": NSNull.null,
        @"modeId": device.modeId ?: NSNull.null,
        @"deviceType": @(device.deviceType),
        @"deviceTypeName": [self stringForDeviceType:device.deviceType],
        @"rssi": device.RSSI ?: NSNull.null,
        @"isSupportEightElectrodes": @(device.isSupportEightElectrodes),
        @"supportWifi": @(device.supportWifi),
    };

    NSDictionary *scaleJSON = @{
        @"measureTime": scaleData.measureTime ? [self isoDateStringFromDate:scaleData.measureTime includeTime:YES] : NSNull.null,
        @"hmac": scaleData.hmac ?: NSNull.null,
        @"height": [self jsonValueForDouble:scaleData.height],
        @"heightMode": @(scaleData.heightMode),
        @"weight": [self jsonValueForDouble:scaleData.weight],
        @"resistance50": @(scaleData.resistance50),
        @"resistance500": @(scaleData.resistance500),
        @"barCode": scaleData.barCode ?: NSNull.null,
        @"newEightModel": @(scaleData.newEightModel),
        @"eightIsAbnormal": @(scaleData.eightIsAbnormal),
        @"eightReasonMask": @(scaleData.eightReasonMask),
    };

    return @{
        @"metadata": @{
            @"exportedAt": [self isoDateStringFromDate:NSDate.date includeTime:YES],
            @"sdkVersion": QNBleApi.sdkVersion ?: NSNull.null,
            @"appId": QNTestAppId,
            @"bundleIdentifier": NSBundle.mainBundle.bundleIdentifier ?: NSNull.null,
            @"expectedBluetoothName": QNTargetBluetoothName,
            @"expectedModeId": QNExpectedModeId,
            @"authorizationDeviceList": self.authorizedDeviceList.description ?: NSNull.null,
            @"note": @"unit 和 description 为 null，因为 QNScaleItemData 2.37.1 未公开这两个属性。",
        },
        @"device": deviceJSON,
        @"user": userJSON,
        @"scaleData": scaleJSON,
        @"items": itemJSON,
    };
}

- (void)copyLogTapped:(UIButton *)sender {
    [self appendLog:@"SDK" message:@"复制完整日志到剪贴板"];
    UIPasteboard.generalPasteboard.string = [self.logEntries componentsJoinedByString:@"\n"];
}

- (void)shareLogTapped:(UIButton *)sender {
    NSString *text = [self.logEntries componentsJoinedByString:@"\n"];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"QNScaleDebugLog.txt"]];
    NSError *error = nil;
    if (![text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [self appendError:error category:@"SDK" context:@"写入日志文件失败"];
        return;
    }
    [self presentShareItems:@[url] sourceView:sender];
}

- (void)exportJSONTapped:(UIButton *)sender {
    if (!self.latestMeasurementJSON) {
        [self appendLog:@"DATA" message:@"尚无最终测量数据，无法导出 JSON"];
        return;
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.latestMeasurementJSON options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    if (!data) {
        [self appendError:error category:@"DATA" context:@"序列化测量 JSON 失败"];
        return;
    }
    NSString *fileName = [NSString stringWithFormat:@"QNScaleMeasurement-%@.json", [self fileTimestamp]];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
    if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
        [self appendError:error category:@"DATA" context:@"写入测量 JSON 失败"];
        return;
    }
    [self appendLog:@"DATA" message:[NSString stringWithFormat:@"测量 JSON 已生成：%@", url.path]];
    [self presentShareItems:@[url] sourceView:sender];
}

- (void)presentShareItems:(NSArray *)items sourceView:(UIView *)sourceView {
    UIActivityViewController *controller = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    controller.popoverPresentationController.sourceView = sourceView;
    controller.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:controller animated:YES completion:nil];
}

#pragma mark - SDK log

- (void)onLog:(NSString *)log {
    [self appendLog:@"SDK" message:[NSString stringWithFormat:@"QNSDK: %@", log ?: @"<nil>"]];
}

- (void)appendError:(NSError *)error category:(NSString *)category context:(NSString *)context {
    if (!error) {
        [self appendLog:category message:[NSString stringWithFormat:@"%@ error=<nil>", context]];
        return;
    }
    [self appendLog:category message:[NSString stringWithFormat:@"%@ domain=%@ code=%ld description=%@ userInfo=%@",
                                       context,
                                       error.domain ?: @"<nil>",
                                       (long)error.code,
                                       error.localizedDescription ?: @"<nil>",
                                       error.userInfo ?: @{}]];
}

- (void)appendLog:(NSString *)category message:(NSString *)message {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendLog:category message:message];
        });
        return;
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"[%@][%@] %@", [formatter stringFromDate:NSDate.date], category, message];
    NSLog(@"%@", line);
    [self.logEntries addObject:line];
    self.logTextView.text = [self.logEntries componentsJoinedByString:@"\n"];
    if (self.logTextView.text.length > 0) {
        NSRange bottom = NSMakeRange(self.logTextView.text.length - 1, 1);
        [self.logTextView scrollRangeToVisible:bottom];
    }
}

#pragma mark - Formatting helpers

- (NSDate *)dateFromISODateString:(NSString *)string {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd";
    return [formatter dateFromString:string];
}

- (NSString *)isoDateStringFromDate:(NSDate *)date includeTime:(BOOL)includeTime {
    if (!date) { return @"<nil>"; }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = NSTimeZone.localTimeZone;
    formatter.dateFormat = includeTime ? @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ" : @"yyyy-MM-dd";
    return [formatter stringFromDate:date];
}

- (NSString *)fileTimestamp {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    return [formatter stringFromDate:NSDate.date];
}

- (id)jsonValueForDouble:(double)value {
    if (isfinite(value)) {
        return @(value);
    }
    if (isnan(value)) {
        return @"NaN";
    }
    return value > 0 ? @"Infinity" : @"-Infinity";
}

- (NSString *)stringForBluetoothState:(QNBLEState)state {
    switch (state) {
        case QNBLEStateUnknown: return @"未知";
        case QNBLEStateResetting: return @"重置中";
        case QNBLEStateUnsupported: return @"不支持";
        case QNBLEStateUnauthorized: return @"未授权";
        case QNBLEStatePoweredOff: return @"关闭";
        case QNBLEStatePoweredOn: return @"开启";
    }
    return [NSString stringWithFormat:@"未知(%lu)", (unsigned long)state];
}

- (NSString *)stringForDeviceType:(QNDeviceType)type {
    switch (type) {
        case QNDeviceTypeScaleBleDefault: return @"ScaleBleDefault(100)";
        case QNDeviceTypeScaleBroadcast: return @"ScaleBroadcast(120)";
        case QNDeviceTypeScaleKitchen: return @"ScaleKitchen(130)";
        case QNDeviceTypeUserScale: return @"UserScale(140)";
        case QNDeviceTypeHeightScale: return @"HeightScale(160)";
        case QNDeviceTypeSlimScale: return @"SlimScale(180)";
    }
    return [NSString stringWithFormat:@"Unknown(%lu)", (unsigned long)type];
}

- (NSString *)stringForScaleState:(QNScaleState)state {
    switch (state) {
        case QNScaleStateDisconnected: return @"未连接";
        case QNScaleStateLinkLoss: return @"连接丢失";
        case QNScaleStateConnected: return @"已连接";
        case QNScaleStateConnecting: return @"正在连接";
        case QNScaleStateDisconnecting: return @"正在断开";
        case QNScaleStateStartMeasure: return @"开始测量";
        case QNScaleStateRealTime: return @"实时体重";
        case QNScaleStateBodyFat: return @"测量生物阻抗";
        case QNScaleStateHeartRate: return @"测量心率";
        case QNScaleStateMeasureCompleted: return @"测量完成";
        case QNScaleStateWiFiBleStartNetwork: return @"开始配网";
        case QNScaleStateWiFiBleNetworkSuccess: return @"配网成功";
        case QNScaleStateWiFiBleNetworkFail: return @"配网失败";
        case QNScaleStateBleKitchenPeeled: return @"厨房秤去皮";
        case QNScaleStateHeightScaleMeasureFail: return @"身高秤测量失败";
        case QNScaleStateNeedOta: return @"需要 OTA";
    }
    return [NSString stringWithFormat:@"未知(%ld)", (long)state];
}

@end
