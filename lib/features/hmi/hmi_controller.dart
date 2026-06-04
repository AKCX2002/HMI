import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../core/protocol/crc_algorithm.dart';
import '../../core/protocol/hmi_frame.dart';
import '../../core/serial/serial_transport.dart';
import '../../util/log_exporter.dart';
import 'hmi_hmis_bam.dart';
import 'hmi_port_config.dart';
import 'hmi_protocol.dart';
import 'hmi_session_catalog.dart';
import 'hmi_session_frame.dart';
import 'stack_stats.dart';

class HmiLogEntry {
  HmiLogEntry({
    required this.direction,
    required this.frame,
    required this.timestamp,
    required this.decoded,
    this.note,
    this.attempt,
    this.portLabel = '',
    this.rawLineOverride,
  });

  final String direction;
  final HmiFrame frame;
  final DateTime timestamp;
  final HmiDecodedFrame decoded;
  final String? note;
  final int? attempt;
  final String portLabel;
  final String? rawLineOverride;

  String get pretty {
    final port = portLabel.isNotEmpty ? ' [$portLabel]' : '';
    final timeTag = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(timestamp);
    final base = '[$timeTag]$port [$direction]';
    final payloadLine =
        rawLineOverride ??
        'ADDR=0x${toHex2(frame.address)} FUNC=0x${toHex2(frame.function)} DATA=${payloadToHex(frame.data)}';
    final decodePart = '${decoded.title} ${decoded.summary}';
    final attemptPart = attempt == null ? '' : ' (尝试#$attempt)';
    final notePart = note == null ? '' : ' [$note]';
    return '$base\n$payloadLine\n$decodePart$attemptPart$notePart';
  }
}

class CommandExecutionResult {
  const CommandExecutionResult({
    required this.success,
    required this.message,
    this.response,
    this.elapsed,
    this.attempts,
  });

  final bool success;
  final String message;
  final HmiFrame? response;
  final Duration? elapsed;
  final int? attempts;
}

class StackLevelSample {
  const StackLevelSample({required this.timestamp, required this.level});

  final DateTime timestamp;
  final int level;
}

class HmiLogBundleManifest {
  const HmiLogBundleManifest({
    required this.rollingLogPath,
    required this.rollingStackLogPath,
  });

  final String? rollingLogPath;
  final String? rollingStackLogPath;
}

enum HmiSessionClientState {
  disconnected,
  hello,
  deviceInfo,
  directoryReady,
  valuesReady,
  subscribed,
  degraded,
}

class HmiSessionEventEntry {
  const HmiSessionEventEntry({
    required this.timestamp,
    required this.code,
    required this.value0,
    required this.value1,
    required this.summary,
  });

  final DateTime timestamp;
  final int code;
  final int value0;
  final int value1;
  final String summary;
}

const int hmiStreamMaskEvents = 0x01;
const int hmiStreamMaskLogs = 0x02;
const int hmiStreamMaskStack = 0x04;

class _DgusFrame {
  _DgusFrame({required this.command, required this.data});
  final int command;
  final Uint8List data;

  List<int> encode() => <int>[0x5A, 0xA5, data.length + 1, command, ...data];
}

class _DgusWaiter {
  _DgusWaiter(this.matcher);
  final bool Function(_DgusFrame frame) matcher;
  final Completer<_DgusFrame?> completer = Completer<_DgusFrame?>();
}

class _SessionWaiter {
  _SessionWaiter(this.matcher);
  final bool Function(HmiSessionFrame frame) matcher;
  final Completer<HmiSessionFrame?> completer = Completer<HmiSessionFrame?>();
}

class _BamControlWaiter {
  _BamControlWaiter(this.matcher);
  final bool Function(HmisBamReceivedControl control) matcher;
  final Completer<HmisBamReceivedControl?> completer =
      Completer<HmisBamReceivedControl?>();
}

/// 单个串口通道的状态与处理逻辑。
class _PortChannel {
  _PortChannel(
    this.transport,
    this.configRef, {
    required this.acceptsPackerFrames,
    required this.acceptsDgusFrames,
    required this.acceptsSessionFrames,
  });

  final SerialTransport transport;
  final List<int> rxBuffer = <int>[];
  final List<int> dgusRxBuffer = <int>[];
  final HmisBamDecoder hmisBamDecoder = HmisBamDecoder();
  final HmisBamFrameBuilder hmisBamBuilder = HmisBamFrameBuilder();
  final HmiSessionFrameDecoder sessionDecoder = HmiSessionFrameDecoder();
  final List<_DgusWaiter> dgusWaiters = <_DgusWaiter>[];
  final List<_SessionWaiter> sessionWaiters = <_SessionWaiter>[];
  final List<_BamControlWaiter> bamControlWaiters = <_BamControlWaiter>[];
  StreamSubscription<Uint8List>? subscription;
  final bool acceptsPackerFrames;
  final bool acceptsDgusFrames;
  final bool acceptsSessionFrames;

  /// 指向外部可变的 HmiPortConfig 引用，以便读取最新配置。
  final HmiPortConfig Function() configRef;

  HmiPortConfig get config => configRef();

  void resetBuffers() {
    rxBuffer.clear();
    dgusRxBuffer.clear();
    hmisBamDecoder.reset();
    sessionDecoder.reset();
  }

  void dispose() {
    subscription?.cancel();
    subscription = null;
    try {
      transport.disconnect();
    } catch (e) {
      debugPrint('通道 $this 断开异常: $e');
    }
    // 完成所有未完成的 DGUS 等待者，防止内存泄漏
    for (final w in dgusWaiters) {
      if (!w.completer.isCompleted) {
        w.completer.complete(null);
      }
    }
    for (final w in sessionWaiters) {
      if (!w.completer.isCompleted) {
        w.completer.complete(null);
      }
    }
    for (final w in bamControlWaiters) {
      if (!w.completer.isCompleted) {
        w.completer.complete(null);
      }
    }
    resetBuffers();
    dgusWaiters.clear();
    sessionWaiters.clear();
    bamControlWaiters.clear();
  }
}

class HmiController extends ChangeNotifier {
  /// HMI 控制器：
  /// - 管理双串口通道（端口 A / 端口 B）
  /// - 每个通道独立连接、独立 CRC 算法配置
  /// - 管理命令发送与自动重发
  /// - 处理字节流拆包与响应匹配
  HmiController(this._transportA, {SerialTransport? transportB})
    : _transportB = transportB ?? SerialTransportDummy(),
      _portAConfig = HmiPortConfig(baudRate: 9600, label: '端口 A（主控协议）'),
      _portBConfig = HmiPortConfig(
        baudRate: 9600,
        crcAlgorithm: CrcAlgorithm.modbus,
        label: '端口 B（USART1会话）',
      ) {
    _channelA = _PortChannel(
      _transportA,
      () => _portAConfig,
      acceptsPackerFrames: true,
      acceptsDgusFrames: false,
      acceptsSessionFrames: false,
    );
    _channelB = _PortChannel(
      _transportB,
      () => _portBConfig,
      acceptsPackerFrames: false,
      acceptsDgusFrames: false,
      acceptsSessionFrames: true,
    );
    _subscriptionA = _transportA.incomingBytes.listen(
      (bytes) => _onIncomingBytes(bytes, _channelA),
    );
    _connectionSubscriptionA = _transportA.connectionStates.listen(
      (state) => _onTransportStateChanged(_channelA, state),
    );
    _subscriptionB = _transportB.incomingBytes.listen(
      (bytes) => _onIncomingBytes(bytes, _channelB),
    );
    _connectionSubscriptionB = _transportB.connectionStates.listen(
      (state) => _onTransportStateChanged(_channelB, state),
    );

    // 周期性检查 BAM 接收超时（分片丢失等情况），避免解码器永久卡在活跃状态。
    _bamTimeoutTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _onBamTimeoutCheck(),
    );
  }

  final SerialTransport _transportA;
  final SerialTransport _transportB;
  late final _PortChannel _channelA;
  late final _PortChannel _channelB;

  StreamSubscription<Uint8List>? _subscriptionA;
  StreamSubscription<Uint8List>? _subscriptionB;
  StreamSubscription<SerialConnectionState>? _connectionSubscriptionA;
  StreamSubscription<SerialConnectionState>? _connectionSubscriptionB;
  Timer? _bamTimeoutTimer;

  static const int _diskFlushBatchSize = 40;
  static const int _maxInMemoryLogs = 5000;
  static const int _maxStackLevelSamples = 1200;
  static const int _maxStackSnapshots = 240;
  final List<HmiLogEntry> _logs = <HmiLogEntry>[];
  final List<StackLevelSample> _stackLevelSamples = <StackLevelSample>[];
  final List<StackSnapshot> _stackSnapshots = <StackSnapshot>[];
  final StackStatsCollector _stackStatsCollector = StackStatsCollector();
  final StringBuffer _diskLogBuffer = StringBuffer();
  final StringBuffer _stackDiskBuffer = StringBuffer();
  int _pendingDiskLogLines = 0;
  int _pendingStackDiskLines = 0;
  bool _diskFlushInProgress = false;
  bool _stackDiskFlushInProgress = false;
  String? _rollingLogPath;
  String? _rollingStackLogPath;
  Map<String, StackTaskStats> _stackTaskStats = <String, StackTaskStats>{};
  StackSnapshot? _latestStackSnapshot;

  Future<void> _txChain = Future<void>.value();

  HmiPortConfig _portAConfig;
  HmiPortConfig _portBConfig;
  String? _statusMessage;
  HmiRetryPolicy _retryPolicy = const HmiRetryPolicy();
  int _sessionNodeAddress = 0xFA;

  List<String> _portsA = <String>[];
  List<String> _portsB = <String>[];
  int _sessionEpoch = 0;
  int _sessionInboundFrameCount = 0;
  String _deviceName = '打包机';
  HmiSessionClientState _sessionState = HmiSessionClientState.disconnected;
  bool _sessionHandshakeReady = false;
  bool _sessionSyncInProgress = false;
  int _sessionSubscriptionMask = 0;
  final List<HmiSessionGroupDef> _sessionGroups = <HmiSessionGroupDef>[];
  final List<HmiSessionParamDef> _sessionParams = <HmiSessionParamDef>[];
  final Map<int, int> _sessionParamValues = <int, int>{};
  final List<HmiSessionEventEntry> _sessionEvents = <HmiSessionEventEntry>[];

  // ────────────── 端口访问器 ──────────────

  bool get isConnectedA => _transportA.isConnected;
  bool get isConnectedB => _transportB.isConnected;
  bool get isConnected => isConnectedA || isConnectedB;

  HmiPortConfig get portAConfig => _portAConfig;
  HmiPortConfig get portBConfig => _portBConfig;
  List<String> get portsA => _portsA;
  List<String> get portsB => _portsB;

  /// 向后兼容：返回端口 A 的波特率。
  int get baudRate => _portAConfig.baudRate;

  /// 向后兼容：返回端口 A 的串口名称。
  String? get selectedPort => _portAConfig.portName;

  String? get statusMessage => _statusMessage;
  String get deviceName => _deviceName;
  HmiRetryPolicy get retryPolicy => _retryPolicy;
  int get sessionNodeAddress => _sessionNodeAddress;
  HmiSessionClientState get sessionState => _sessionState;
  bool get sessionHandshakeReady => _sessionHandshakeReady;
  bool get sessionQuickControlReady => isConnectedB && _sessionHandshakeReady;
  bool get sessionSyncInProgress => _sessionSyncInProgress;
  int get sessionSubscriptionMask => _sessionSubscriptionMask;
  List<HmiSessionGroupDef> get sessionGroups =>
      List<HmiSessionGroupDef>.unmodifiable(_sessionGroups);
  List<HmiSessionParamDef> get sessionParams =>
      List<HmiSessionParamDef>.unmodifiable(_sessionParams);
  Map<int, int> get sessionParamValues =>
      Map<int, int>.unmodifiable(_sessionParamValues);
  List<HmiSessionEventEntry> get sessionEvents =>
      List<HmiSessionEventEntry>.unmodifiable(_sessionEvents);
  List<HmiLogEntry> get logs => List<HmiLogEntry>.unmodifiable(_logs);
  List<StackLevelSample> get stackLevelSamples =>
      List<StackLevelSample>.unmodifiable(_stackLevelSamples);
  List<StackSnapshot> get stackSnapshots =>
      List<StackSnapshot>.unmodifiable(_stackSnapshots);
  String? get rollingLogPath => _rollingLogPath;
  String? get rollingStackLogPath => _rollingStackLogPath;
  Map<String, StackTaskStats> get stackTaskStats =>
      Map<String, StackTaskStats>.unmodifiable(_stackTaskStats);
  StackSnapshot? get latestStackSnapshot => _latestStackSnapshot;

  Map<HmiSessionGroupDef, List<HmiSessionParamDef>> get sessionCatalogByGroup {
    final groupsById = <int, HmiSessionGroupDef>{
      for (final group in _sessionGroups) group.groupId: group,
    };
    final Map<HmiSessionGroupDef, List<HmiSessionParamDef>> ordered =
        <HmiSessionGroupDef, List<HmiSessionParamDef>>{};
    final groups = List<HmiSessionGroupDef>.from(_sessionGroups)
      ..sort((a, b) => a.order.compareTo(b.order));
    for (final group in groups) {
      ordered[group] = <HmiSessionParamDef>[];
    }
    for (final param in _sessionParams) {
      final group = groupsById[param.groupId];
      if (group == null) {
        continue;
      }
      ordered.putIfAbsent(group, () => <HmiSessionParamDef>[]).add(param);
    }
    for (final item in ordered.values) {
      item.sort((a, b) => a.paramId.compareTo(b.paramId));
    }
    return ordered;
  }

  // ────────────── 端口 A 配置 ──────────────

  void setPortA(String? value) {
    _portAConfig = _portAConfig.copyWith(portName: value);
    notifyListeners();
  }

  void setBaudRateA(int value) {
    _portAConfig = _portAConfig.copyWith(baudRate: value);
    notifyListeners();
  }

  void setCrcAlgorithmA(CrcAlgorithm algo) {
    _portAConfig = _portAConfig.copyWith(crcAlgorithm: algo);
    _statusMessage = '端口 A CRC 算法: ${algo.displayName}';
    notifyListeners();
  }

  void setDataBitsA(HmiDataBits value) {
    _portAConfig = _portAConfig.copyWith(dataBits: value);
    notifyListeners();
  }

  void setStopBitsA(HmiStopBits value) {
    _portAConfig = _portAConfig.copyWith(stopBits: value);
    notifyListeners();
  }

  void setParityA(HmiParity value) {
    _portAConfig = _portAConfig.copyWith(parity: value);
    notifyListeners();
  }

  void setFlowControlA(HmiFlowControl value) {
    _portAConfig = _portAConfig.copyWith(flowControl: value);
    notifyListeners();
  }

  // ────────────── 端口 B 配置 ──────────────

  void setPortB(String? value) {
    _portBConfig = _portBConfig.copyWith(portName: value);
    notifyListeners();
  }

  void setBaudRateB(int value) {
    _portBConfig = _portBConfig.copyWith(baudRate: value);
    notifyListeners();
  }

  void setCrcAlgorithmB(CrcAlgorithm algo) {
    _portBConfig = _portBConfig.copyWith(crcAlgorithm: algo);
    _statusMessage = '端口 B CRC 算法: ${algo.displayName}';
    notifyListeners();
  }

  void setDataBitsB(HmiDataBits value) {
    _portBConfig = _portBConfig.copyWith(dataBits: value);
    notifyListeners();
  }

  void setStopBitsB(HmiStopBits value) {
    _portBConfig = _portBConfig.copyWith(stopBits: value);
    notifyListeners();
  }

  void setParityB(HmiParity value) {
    _portBConfig = _portBConfig.copyWith(parity: value);
    notifyListeners();
  }

  void setFlowControlB(HmiFlowControl value) {
    _portBConfig = _portBConfig.copyWith(flowControl: value);
    notifyListeners();
  }

  // ────────────── 通用 ──────────────

  void updateRetryPolicy(HmiRetryPolicy policy) {
    _retryPolicy = policy;
    _statusMessage =
        '策略更新: 超时${policy.timeoutMs}ms, 重试${policy.maxRetries}次, 间隔${policy.retryIntervalMs}ms';
    notifyListeners();
  }

  void setSessionNodeAddress(int value) {
    final next = value & 0xFF;
    if (_sessionNodeAddress == next) {
      return;
    }
    _sessionNodeAddress = next;
    _statusMessage = 'USART1 HMIS-BAM 节点地址: 0x${toHex2(next)}';
    notifyListeners();
  }

  // ────────────── 端口 A 连接管理 ──────────────

  Future<void> refreshPortsA() async {
    try {
      _portsA = await _transportA.availablePorts();
      // 不再自动选中第一个端口。仅当之前选中的端口已不存在时清空选择。
      if (_portAConfig.portName != null &&
          !_portsA.contains(_portAConfig.portName)) {
        _portAConfig = _portAConfig.copyWith(portName: null);
      }
      _statusMessage = _portsA.isEmpty ? '端口 A: 未发现串口设备' : '已刷新串口 A 列表';
    } catch (error) {
      _statusMessage = '端口 A 扫描失败: $error';
    }
    notifyListeners();
  }

  Future<void> refreshPortsB() async {
    try {
      _portsB = await _transportB.availablePorts();
      // 不再自动选中第一个端口。仅当之前选中的端口已不存在时清空选择。
      if (_portBConfig.portName != null &&
          !_portsB.contains(_portBConfig.portName)) {
        _portBConfig = _portBConfig.copyWith(portName: null);
      }
      _statusMessage = _portsB.isEmpty ? '端口 B: 未发现串口设备' : '已刷新串口 B 列表';
    } catch (error) {
      _statusMessage = '端口 B 扫描失败: $error';
    }
    notifyListeners();
  }

  Future<void> refreshPorts() async {
    // 串行扫描，避免 libserialport 并发冲突（errno 11 EAGAIN）
    await refreshPortsA();
    await refreshPortsB();
  }

  Future<void> connectPortA() async {
    final port = _portAConfig.portName;
    if (port == null || port.isEmpty) {
      _statusMessage = '端口 A: 请先选择串口';
      notifyListeners();
      return;
    }
    try {
      _clearChannelState(_channelA);
      await _transportA.connect(
        portName: port,
        baudRate: _portAConfig.baudRate,
        dataBits: _portAConfig.dataBits.value,
        stopBits: _portAConfig.stopBits.value,
        parity: _portAConfig.parity.value,
        flowControl: _portAConfig.flowControl.value,
      );
      _statusMessage =
          '端口 A 已连接: $port @ ${_portAConfig.baudRate}'
          ' ${_portAConfig.dataBits.label}${_portAConfig.parity.shortLabel}${_portAConfig.stopBits.label}';
      notifyListeners();
    } catch (error) {
      _statusMessage = '端口 A 连接失败: $error';
      notifyListeners();
    }
  }

  Future<void> connectPortB() async {
    if (_transportB is SerialTransportDummy) {
      _statusMessage = '端口 B: 未提供第二个串口实例';
      notifyListeners();
      return;
    }
    final port = _portBConfig.portName;
    if (port == null || port.isEmpty) {
      _statusMessage = '端口 B: 请先选择串口';
      notifyListeners();
      return;
    }
    try {
      _clearChannelState(_channelB);
      await _transportB.connect(
        portName: port,
        baudRate: _portBConfig.baudRate,
        dataBits: _portBConfig.dataBits.value,
        stopBits: _portBConfig.stopBits.value,
        parity: _portBConfig.parity.value,
        flowControl: _portBConfig.flowControl.value,
      );
      _statusMessage =
          '端口 B 已连接: $port @ ${_portBConfig.baudRate}'
          ' ${_portBConfig.dataBits.label}${_portBConfig.parity.shortLabel}${_portBConfig.stopBits.label}';
      _sessionEpoch++;
      notifyListeners();
      unawaited(syncSessionCatalog());
    } catch (error) {
      _statusMessage = '端口 B 连接失败: $error';
      notifyListeners();
    }
  }

  Future<void> disconnectPortA() async {
    try {
      await _transportA.disconnect();
    } catch (e) {
      debugPrint('端口 A 断开异常: $e');
    }
    _clearChannelState(_channelA);
    _statusMessage = '端口 A 已断开';
    notifyListeners();
  }

  Future<void> disconnectPortB() async {
    try {
      await _transportB.disconnect();
    } catch (e) {
      debugPrint('端口 B 断开异常: $e');
    }
    _sessionEpoch++;
    _clearChannelState(_channelB);
    _resetSessionCache();
    _statusMessage = '端口 B 已断开';
    notifyListeners();
  }

  /// 清理通道中所有未完成的 DGUS 等待者，防止断开后内存泄漏。
  void _clearChannelState(_PortChannel channel) {
    for (final w in channel.dgusWaiters) {
      if (!w.completer.isCompleted) {
        w.completer.complete(null);
      }
    }
    channel.dgusWaiters.clear();
    for (final w in channel.sessionWaiters) {
      if (!w.completer.isCompleted) {
        w.completer.complete(null);
      }
    }
    channel.sessionWaiters.clear();
    channel.resetBuffers();
  }

  /// 向后兼容：连接/断开端口 A。
  Future<void> connectOrDisconnect() async {
    if (_transportA.isConnected) {
      await disconnectPortA();
    } else {
      await connectPortA();
    }
  }

  Future<void> _writeSerial(SerialTransport transport, Uint8List bytes) {
    final previous = _txChain;
    final done = Completer<void>();
    _txChain = done.future;

    return () async {
      try {
        await previous;
      } catch (_) {}

      try {
        await transport.write(bytes);
        done.complete();
      } catch (error) {
        done.complete();
        rethrow;
      }
    }();
  }

  // ────────────── 命令执行 ──────────────

  /// 发送命令帧，不等待响应。
  ///
  /// 响应由流监听实时解析并记入日志。
  /// [usePortB] 为 true 时使用端口 B，否则使用端口 A（默认）。
  Future<CommandExecutionResult> runCommand(
    HmiCommandRequest request, {
    bool usePortB = false,
  }) async {
    if (usePortB) {
      final result = const CommandExecutionResult(
        success: false,
        message: '端口 B 仅支持 HMIS-BAM 会话协议',
      );
      _statusMessage = result.message;
      notifyListeners();
      return result;
    }

    final channel = usePortB ? _channelB : _channelA;
    final transport = channel.transport;
    final config = channel.config;
    final portLabel = config.label;

    if (!transport.isConnected) {
      final result = const CommandExecutionResult(
        success: false,
        message: '串口未连接',
      );
      _statusMessage = result.message;
      notifyListeners();
      return result;
    }

    final frameWithCrc = HmiFrame(
      address: request.frame.address,
      function: request.frame.function,
      data: request.frame.data.toList(),
      crcAlgorithm: request.frame.crcAlgorithm,
    );

    try {
      await _writeSerial(transport, frameWithCrc.encode());
      _appendLog('TX', frameWithCrc, note: request.note, portLabel: portLabel);
      _statusMessage = '${request.label}已发送';
      notifyListeners();
      return CommandExecutionResult(
        success: true,
        message: '${request.label}已发送',
      );
    } catch (error) {
      _statusMessage = '${request.label}发送失败: $error';
      notifyListeners();
      return CommandExecutionResult(success: false, message: '发送失败: $error');
    }
  }

  /// 向后兼容：使用端口 A 发送命令。
  Future<CommandExecutionResult> runCommandPortA(
    HmiCommandRequest request, {
    HmiRetryPolicy? policy,
  }) {
    return runCommand(request, usePortB: false);
  }

  /// 使用端口 B 发送命令。
  Future<CommandExecutionResult> runCommandPortB(
    HmiCommandRequest request, {
    HmiRetryPolicy? policy,
  }) {
    return runCommand(request, usePortB: true);
  }

  // ────────────── 打包机命令（usePortB=null 时走自动路由，非 null 时强制指定端口） ──────────────

  Future<CommandExecutionResult> sendPackerControl({
    required int nodeAddress,
    required int action,
    bool? usePortB,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.control,
      nodeAddress: nodeAddress,
      payload: <int>[action & 0xFF],
      usePortB: usePortB,
    );
  }

  Future<CommandExecutionResult> sendPackerStatus({
    required int nodeAddress,
    bool? usePortB,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.status,
      nodeAddress: nodeAddress,
      usePortB: usePortB,
    );
  }

  /// [action] 0=查询, 1=启动, 2=完成查询
  /// [clearFlag] 0=清除完成标志, 1=保留完成标志
  Future<CommandExecutionResult> sendPackerTriggerBag({
    required int nodeAddress,
    int action = 1,
    int clearFlag = 0,
    bool? usePortB,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.triggerBag,
      nodeAddress: nodeAddress,
      payload: <int>[action & 0xFF, clearFlag & 0xFF],
      usePortB: usePortB,
    );
  }

  Future<CommandExecutionResult> sendPackerTriggerSeal({
    required int nodeAddress,
    int action = 1,
    int clearFlag = 0,
    bool? usePortB,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.triggerSeal,
      nodeAddress: nodeAddress,
      payload: <int>[action & 0xFF, clearFlag & 0xFF],
      usePortB: usePortB,
    );
  }

  Future<CommandExecutionResult> sendPackerTriggerDeliver({
    required int nodeAddress,
    int action = 1,
    int clearFlag = 0,
    bool? usePortB,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.triggerDeliver,
      nodeAddress: nodeAddress,
      payload: <int>[action & 0xFF, clearFlag & 0xFF],
      usePortB: usePortB,
    );
  }

  Future<CommandExecutionResult> sendPackerClearFlag({
    required int nodeAddress,
    required int flagId,
    bool? usePortB,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.clearFlag,
      nodeAddress: nodeAddress,
      payload: <int>[flagId & 0xFF],
      usePortB: usePortB,
    );
  }

  Future<CommandExecutionResult> sendPackerAlarmQuery({
    required int nodeAddress,
    bool? usePortB,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.alarmQuery,
      nodeAddress: nodeAddress,
      usePortB: usePortB,
    );
  }

  Future<CommandExecutionResult> sendPackerPrinterForward({
    required int nodeAddress,
    int printerCmd = 0x81,
    bool? usePortB,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.printerForward,
      nodeAddress: nodeAddress,
      payload: <int>[printerCmd & 0xFF],
      usePortB: usePortB,
    );
  }

  Future<CommandExecutionResult> sendPackerVersion({
    required int nodeAddress,
    bool? usePortB,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.version,
      nodeAddress: nodeAddress,
      usePortB: usePortB,
    );
  }

  Future<CommandExecutionResult> sendPackerResetFault({
    required int nodeAddress,
    required int scope,
    bool? usePortB,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.resetFault,
      nodeAddress: nodeAddress,
      payload: <int>[scope & 0xFF],
      usePortB: usePortB,
    );
  }

  Future<CommandExecutionResult> sendPackerStepperJog({
    required int nodeAddress,
    required int motor,
    required int direction,
    required int pulses,
    bool? usePortB,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.stepperJog,
      nodeAddress: nodeAddress,
      payload: <int>[
        motor & 0xFF,
        direction & 0xFF,
        (pulses >> 8) & 0xFF,
        pulses & 0xFF,
      ],
      usePortB: usePortB,
    );
  }

  Future<CommandExecutionResult> sendPackerDcMotor1Jog({
    required int nodeAddress,
    required int direction,
    required int durationMs,
    bool? usePortB,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.dcMotor1Jog,
      nodeAddress: nodeAddress,
      payload: <int>[
        direction & 0xFF,
        (durationMs >> 8) & 0xFF,
        durationMs & 0xFF,
      ],
      usePortB: usePortB,
    );
  }

  Future<CommandExecutionResult> sendPackerDcMotor2Jog({
    required int nodeAddress,
    required int direction,
    required int durationMs,
    bool? usePortB,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.dcMotor2Jog,
      nodeAddress: nodeAddress,
      payload: <int>[
        direction & 0xFF,
        (durationMs >> 8) & 0xFF,
        durationMs & 0xFF,
      ],
      usePortB: usePortB,
    );
  }

  /// 读取单个运行时参数。
  Future<int?> sendParamRead({
    required int nodeAddress,
    required int paramId,
    bool? usePortB,
  }) async {
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.getParamValuesBatch,
      payload: <int>[1, paramId & 0xFF],
      label: '参数读取',
    );
    if (resp == null) return null;
    if (resp.payload.length < 7 || resp.payload[0] == 0) return null;
    final value =
        resp.payload[3] |
        (resp.payload[4] << 8) |
        (resp.payload[5] << 16) |
        (resp.payload[6] << 24);
    _sessionParamValues[paramId] = value;
    return value;
  }

  /// 写入单个运行时参数 (仅 RAM, 不自动保存)。
  Future<int?> sendParamWrite({
    required int nodeAddress,
    required int paramId,
    required int value,
    bool? usePortB,
  }) async {
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.setParamValuesBatch,
      payload: <int>[
        1,
        paramId & 0xFF,
        0,
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
      ],
      label: '参数写入',
    );
    if (resp == null || resp.payload.isEmpty || resp.payload.last != 0) {
      return null;
    }
    _sessionParamValues[paramId] = value;
    return value;
  }

  /// 保存当前运行时参数到 EEPROM。
  Future<bool> sendParamSave({required int nodeAddress, bool? usePortB}) async {
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.saveParams,
      label: '参数保存',
    );
    return resp != null && resp.payload.isNotEmpty && resp.payload[0] == 0;
  }

  Future<bool> sendParamLoad({
    required int nodeAddress,
    required int action,
    bool? usePortB,
  }) async {
    final resp = await _runSessionCommand(
      command: (action == 0)
          ? HmiSessionCommand.loadParams
          : HmiSessionCommand.loadDefaults,
      label: (action == 0) ? '加载EEPROM' : '恢复默认',
    );
    return resp != null && resp.payload.isNotEmpty && resp.payload[0] == 0;
  }

  // ────────────── USART1 Session 控制命令 (0x30~0x37) ──────────────

  Future<bool> _ensureSessionQuickControlReady() async {
    if (!_transportB.isConnected) {
      _resetSessionCache();
      _statusMessage = '快捷控制失败: USART1未连接';
      notifyListeners();
      return false;
    }
    if (_sessionHandshakeReady) {
      return true;
    }

    final hello = await _runSessionCommand(
      command: HmiSessionCommand.hello,
      label: 'Session重握手',
    );
    if (hello == null || hello.payload.length < 2 || hello.payload[0] != 0) {
      _sessionHandshakeReady = false;
      return false;
    }

    _sessionHandshakeReady = true;
    notifyListeners();
    return true;
  }

  /// 启停控制。action: 0=停机, 1=启动。
  Future<bool> sessionControlRunState(int action) async {
    if (!await _ensureSessionQuickControlReady()) {
      return false;
    }
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.controlRunState,
      payload: <int>[action & 0xFF],
      label: 'Session启停',
    );
    return resp != null && resp.payload.isNotEmpty && resp.payload[0] == 0;
  }

  /// 出袋命令。action: 0=查询, 1=启动, 2=完成查询。
  /// clearDone: true=先清 done 标志再查询。
  Future<bool> sessionTriggerBag({
    int action = 1,
    bool clearDone = true,
  }) async {
    if (!await _ensureSessionQuickControlReady()) {
      return false;
    }
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.triggerBag,
      payload: <int>[action & 0xFF, clearDone ? 0 : 1],
      label: 'Session出袋',
    );
    return resp != null && resp.payload.isNotEmpty && resp.payload[0] == 0;
  }

  /// 封口命令。
  Future<bool> sessionTriggerSeal({
    int action = 1,
    bool clearDone = true,
  }) async {
    if (!await _ensureSessionQuickControlReady()) {
      return false;
    }
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.triggerSeal,
      payload: <int>[action & 0xFF, clearDone ? 0 : 1],
      label: 'Session封口',
    );
    return resp != null && resp.payload.isNotEmpty && resp.payload[0] == 0;
  }

  /// 投料命令。
  Future<bool> sessionTriggerDeliver({
    int action = 1,
    bool clearDone = true,
  }) async {
    if (!await _ensureSessionQuickControlReady()) {
      return false;
    }
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.triggerDeliver,
      payload: <int>[action & 0xFF, clearDone ? 0 : 1],
      label: 'Session投料',
    );
    return resp != null && resp.payload.isNotEmpty && resp.payload[0] == 0;
  }

  /// 清除完成标志。flagType: 1=出袋, 2=封口, 3=投料。
  Future<bool> sessionClearFlag(int flagType) async {
    if (!await _ensureSessionQuickControlReady()) {
      return false;
    }
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.clearFlag,
      payload: <int>[flagType & 0xFF],
      label: 'Session清标志',
    );
    return resp != null && resp.payload.isNotEmpty && resp.payload[0] == 0;
  }

  /// 故障复位。scope: 0=清报警码, 1=清锁存, 2=全部复位+停机。
  Future<bool> sessionResetFault(int scope) async {
    if (!await _ensureSessionQuickControlReady()) {
      return false;
    }
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.resetFault,
      payload: <int>[scope & 0xFF],
      label: 'Session复位',
    );
    return resp != null && resp.payload.isNotEmpty && resp.payload[0] == 0;
  }

  /// 步进电机点动。motorId: 电机编号, direction: 0=正 1=反, pulses: 脉冲数。
  Future<bool> sessionStepperJog(int motorId, int direction, int pulses) async {
    if (!await _ensureSessionQuickControlReady()) {
      return false;
    }
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.stepperJog,
      payload: <int>[
        motorId & 0xFF,
        direction & 0xFF,
        pulses & 0xFF,
        (pulses >> 8) & 0xFF,
      ],
      label: 'Session步进点动',
    );
    return resp != null && resp.payload.isNotEmpty && resp.payload[0] == 0;
  }

  /// 直流电机点动。motorId: 1 或 2, direction: 0=正 1=反, durationMs: 时长。
  Future<bool> sessionDcMotorJog(
    int motorId,
    int direction,
    int durationMs,
  ) async {
    if (!await _ensureSessionQuickControlReady()) {
      return false;
    }
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.dcMotorJog,
      payload: <int>[
        motorId & 0xFF,
        direction & 0xFF,
        durationMs & 0xFF,
        (durationMs >> 8) & 0xFF,
      ],
      label: 'Session直流点动',
    );
    return resp != null && resp.payload.isNotEmpty && resp.payload[0] == 0;
  }

  /// 读取 USART1 Session 聚合系统信息。
  Future<List<int>?> sendDgusSystemInfo({
    required int nodeAddress,
    bool? usePortB,
  }) async {
    if (!await _ensureSessionQuickControlReady()) {
      return null;
    }
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.getDeviceStatus,
      label: 'Session系统信息',
    );
    if (resp == null || resp.payload.length < 12) return null;
    return <int>[
      resp.payload[1],
      resp.payload[2],
      resp.payload[8] == 0 ? 1 : 0,
      resp.payload[10],
    ];
  }

  // ignore: unused_element
  Future<_DgusFrame?> _runDgusCommand({
    required List<int> tx,
    required bool Function(_DgusFrame frame) matcher,
    required String label,
    bool? usePortB,
  }) async {
    final preferB = usePortB ?? true;
    final channel = preferB ? _channelB : _channelA;
    final transport = channel.transport;
    if (!transport.isConnected) {
      _statusMessage = '$label失败: 串口未连接';
      notifyListeners();
      return null;
    }

    final waiter = _DgusWaiter(matcher);
    channel.dgusWaiters.add(waiter);

    try {
      await transport.write(Uint8List.fromList(tx));
      final txHex = tx.map((e) => toHex2(e)).join(' ');
      _appendDgusLog('DGUS TX $txHex', channel.config.label);

      final frame = await waiter.completer.future.timeout(
        Duration(milliseconds: _retryPolicy.timeoutMs),
        onTimeout: () => null,
      );
      channel.dgusWaiters.remove(waiter);
      if (frame == null) {
        _appendDgusLog('DGUS TIMEOUT $txHex', channel.config.label);
        _statusMessage = '$label超时（${_retryPolicy.timeoutMs}ms）';
        notifyListeners();
        return null;
      }
      _statusMessage = '$label成功';
      notifyListeners();
      return frame;
    } catch (e) {
      channel.dgusWaiters.remove(waiter);
      _statusMessage = '$label失败';
      notifyListeners();
      return null;
    }
  }

  Future<HmiSessionFrame?> _runSessionCommand({
    required HmiSessionCommand command,
    List<int> payload = const <int>[],
    required String label,
  }) async {
    final channel = _channelB;
    final transport = channel.transport;
    if (!transport.isConnected) {
      _statusMessage = '$label失败: USART1未连接';
      notifyListeners();
      return null;
    }

    final maxAttempts = _retryPolicy.maxRetries <= 0
        ? 1
        : _retryPolicy.maxRetries;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final transactionId = channel.hmisBamBuilder.allocateTransactionId();
      final seq = transactionId & 0xFFFF;
      final inboundFrameCountBeforeTx = _sessionInboundFrameCount;

      final frame = HmiSessionFrame(
        type: HmiSessionFrameType.request,
        sequence: seq,
        command: command,
        flags: HmiSessionFlags.ackRequired,
        payload: Uint8List.fromList(payload),
      );
      final waiter = _SessionWaiter(
        (f) =>
            f.sequence == seq &&
            f.command == command &&
            f.type == HmiSessionFrameType.response,
      );
      channel.sessionWaiters.add(waiter);

      try {
        final encoded = frame.encode();
        final bamFrames = channel.hmisBamBuilder.encodePayload(
          address: _sessionNodeAddress,
          transactionId: transactionId,
          payload: encoded,
        );
        if (bamFrames.isEmpty) {
          throw StateError('HMIS-BAM帧生成失败');
        }
        await _writeBamFrames(
          channel,
          address: _sessionNodeAddress,
          bamFrames: bamFrames,
        );
        _appendSessionTx(frame, channel.config.label);
        final response = await waiter.completer.future.timeout(
          Duration(milliseconds: _retryPolicy.timeoutMs),
          onTimeout: () => null,
        );
        channel.sessionWaiters.remove(waiter);
        final effectiveResponse =
            response ??
            _fallbackHelloLivenessAck(
              command: command,
              sequence: seq,
              inboundFrameCountBeforeTx: inboundFrameCountBeforeTx,
            );
        if (effectiveResponse != null) {
          _statusMessage = attempt > 1 ? '$label成功（重试#$attempt）' : '$label成功';
          notifyListeners();
          return effectiveResponse;
        }
        if (attempt < maxAttempts) {
          _statusMessage = '$label超时，准备重试（$attempt/$maxAttempts）';
          notifyListeners();
          if (_retryPolicy.retryIntervalMs > 0) {
            await Future<void>.delayed(
              Duration(milliseconds: _retryPolicy.retryIntervalMs),
            );
          }
          continue;
        }
        _sessionHandshakeReady = false;
        if (_transportB.isConnected &&
            _sessionState != HmiSessionClientState.disconnected) {
          _sessionState = HmiSessionClientState.degraded;
        }
        _statusMessage = '$label超时（${_retryPolicy.timeoutMs}ms）';
        notifyListeners();
        return null;
      } catch (_) {
        channel.sessionWaiters.remove(waiter);
        if (attempt < maxAttempts) {
          _statusMessage = '$label失败，准备重试（$attempt/$maxAttempts）';
          notifyListeners();
          if (_retryPolicy.retryIntervalMs > 0) {
            await Future<void>.delayed(
              Duration(milliseconds: _retryPolicy.retryIntervalMs),
            );
          }
          continue;
        }
        _sessionHandshakeReady = false;
        if (_transportB.isConnected &&
            _sessionState != HmiSessionClientState.disconnected) {
          _sessionState = HmiSessionClientState.degraded;
        }
        _statusMessage = '$label失败';
        notifyListeners();
        return null;
      }
    }
    return null;
  }

  HmiSessionFrame? _fallbackHelloLivenessAck({
    required HmiSessionCommand command,
    required int sequence,
    required int inboundFrameCountBeforeTx,
  }) {
    if (command != HmiSessionCommand.hello) {
      return null;
    }
    if (!_transportB.isConnected) {
      return null;
    }
    if (_sessionInboundFrameCount <= inboundFrameCountBeforeTx) {
      return null;
    }
    return HmiSessionFrame(
      type: HmiSessionFrameType.response,
      sequence: sequence,
      command: HmiSessionCommand.hello,
      payload: Uint8List.fromList(const <int>[0x00, 0x01]),
    );
  }

  Future<CommandExecutionResult> _runPackerCommand(
    HmiPackerFunction function, {
    required int nodeAddress,
    List<int> payload = const <int>[],
    bool? usePortB,
  }) {
    // 默认固定走端口 A（USART3 / 20B），只有显式指定时才允许改口。
    final effectivePortB = usePortB ?? false;
    return runCommand(
      HmiCommandRequest(
        command: HmiCommandCode.packer,
        frame: HmiFrame(
          address: nodeAddress & 0xFF,
          function: function.code,
          data: payload,
        ),
        expectedFunctions:
            kRequestToExpectedResponseFunctions[function.code] ??
            <int>{function.code},
        note: '打包机节点0x${toHex2(nodeAddress)}',
        label: function.label,
      ),
      usePortB: effectivePortB,
    );
  }

  Future<CommandExecutionResult> sendCustomFrame({
    required int address,
    required int functionCode,
    required List<int> payload,
    Set<int>? expectedFunctions,
    String? note,
    bool usePortB = false,
    CrcAlgorithm? crcAlgorithm,
  }) {
    return runCommand(
      HmiCommandRequest(
        command: HmiCommandCode.custom,
        frame: HmiFrame(
          address: address,
          function: functionCode,
          data: payload,
          crcAlgorithm: crcAlgorithm ?? CrcAlgorithm.modbus,
        ),
        expectedFunctions:
            expectedFunctions ??
            kRequestToExpectedResponseFunctions[functionCode] ??
            <int>{functionCode},
        note: note ?? '自定义帧',
      ),
      usePortB: usePortB,
    );
  }

  void clearLogs() {
    _logs.clear();
    _diskLogBuffer.clear();
    _pendingDiskLogLines = 0;
    notifyListeners();
  }

  void clearStackLevelSamples() {
    _stackLevelSamples.clear();
    _stackSnapshots.clear();
    _stackTaskStats = <String, StackTaskStats>{};
    _latestStackSnapshot = null;
    _stackStatsCollector.reset();
    notifyListeners();
  }

  void _resetSessionCache() {
    _sessionState = HmiSessionClientState.disconnected;
    _sessionHandshakeReady = false;
    _sessionSyncInProgress = false;
    _sessionSubscriptionMask = 0;
    _sessionGroups.clear();
    _sessionParams.clear();
    _sessionParamValues.clear();
    _sessionEvents.clear();
    _deviceName = '打包机';
  }

  void _onTransportStateChanged(
    _PortChannel channel,
    SerialConnectionState state,
  ) {
    if (state != SerialConnectionState.disconnected) {
      return;
    }
    _clearChannelState(channel);
    if (identical(channel, _channelB)) {
      _sessionEpoch++;
      _resetSessionCache();
    }
    _statusMessage = '${channel.config.label}连接已断开';
    notifyListeners();
  }

  void _onBamTimeoutCheck() {
    var changed = false;
    for (final channel in <_PortChannel>[_channelA, _channelB]) {
      final result = channel.hmisBamDecoder.checkTimeout();
      if (result != null) {
        changed = true;
        final control = result.controlToSend;
        if (control != null) {
          unawaited(_writeSerial(channel.transport, control.encode()));
        }
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  bool _isSessionEpochCurrent(int epoch) {
    return epoch == _sessionEpoch && _transportB.isConnected;
  }

  Future<void> syncSessionCatalog() async {
    if (_sessionSyncInProgress) {
      return;
    }
    if (!_transportB.isConnected) {
      _resetSessionCache();
      _statusMessage = 'USART1未连接';
      notifyListeners();
      return;
    }

    final epoch = _sessionEpoch;
    _sessionSyncInProgress = true;
    _sessionState = HmiSessionClientState.hello;
    notifyListeners();

    try {
      final hello = await _runSessionCommand(
        command: HmiSessionCommand.hello,
        label: 'Session握手',
      );
      if (hello == null || hello.payload.length < 2 || hello.payload[0] != 0) {
        _sessionHandshakeReady = false;
        _sessionState = HmiSessionClientState.degraded;
        return;
      }
      if (!_isSessionEpochCurrent(epoch)) {
        return;
      }
      _sessionHandshakeReady = true;

      _sessionState = HmiSessionClientState.deviceInfo;
      notifyListeners();
      final info = await _runSessionCommand(
        command: HmiSessionCommand.deviceInfo,
        label: '设备信息',
      );
      if (info == null || info.payload.length < 4 || info.payload[0] != 0) {
        _sessionState = HmiSessionClientState.degraded;
        return;
      }
      if (!_isSessionEpochCurrent(epoch)) {
        return;
      }

      if (info.payload.length > 5) {
        _deviceName = utf8.decode(info.payload.sublist(5));
      }

      final groups = await _fetchGroupCatalog();
      final params = await _fetchParamCatalog();
      if (!_isSessionEpochCurrent(epoch)) {
        return;
      }
      if (groups.isEmpty || params.isEmpty) {
        _sessionState = HmiSessionClientState.degraded;
        return;
      }
      _sessionGroups
        ..clear()
        ..addAll(groups);
      _sessionParams
        ..clear()
        ..addAll(params);
      _sessionState = HmiSessionClientState.directoryReady;
      notifyListeners();

      final valueCount = await readAllSessionParams();
      if (!_isSessionEpochCurrent(epoch)) {
        return;
      }
      _sessionState = HmiSessionClientState.valuesReady;
      _statusMessage =
          '参数目录已同步: 分组 ${_sessionGroups.length} / 参数 ${_sessionParams.length} / 已读值 $valueCount';
      notifyListeners();

      final subscribed = await sendSessionSubscribe(
        hmiStreamMaskEvents | hmiStreamMaskLogs | hmiStreamMaskStack,
      );
      if (!_isSessionEpochCurrent(epoch)) {
        return;
      }
      _sessionSubscriptionMask = subscribed;
      _sessionState = subscribed == 0
          ? HmiSessionClientState.degraded
          : HmiSessionClientState.subscribed;
    } finally {
      _sessionSyncInProgress = false;
      notifyListeners();
    }
  }

  Future<List<HmiSessionGroupDef>> _fetchGroupCatalog() async {
    final groups = <HmiSessionGroupDef>[];
    var offset = 0;

    while (true) {
      final resp = await _runSessionCommand(
        command: HmiSessionCommand.getGroupList,
        payload: <int>[offset & 0xFF, 0x08],
        label: '读取参数分组',
      );
      if (resp == null) {
        return groups;
      }
      HmiSessionGroupCatalogPage page;
      try {
        page = parseGroupCatalogPage(resp.payload);
      } on FormatException catch (error) {
        _statusMessage = '读取参数分组失败: $error';
        return groups;
      }
      groups.addAll(page.groups);
      if (page.nextOffset == 0 || page.nextOffset == offset) {
        break;
      }
      offset = page.nextOffset;
    }
    return groups;
  }

  Future<List<HmiSessionParamDef>> _fetchParamCatalog() async {
    final params = <HmiSessionParamDef>[];
    var offset = 0;

    while (true) {
      final resp = await _runSessionCommand(
        command: HmiSessionCommand.getParamList,
        payload: <int>[offset & 0xFF, 0x04],
        label: '读取参数目录',
      );
      if (resp == null) {
        return params;
      }
      HmiSessionParamCatalogPage page;
      try {
        page = parseParamCatalogPage(resp.payload);
      } on FormatException catch (error) {
        _statusMessage = '读取参数目录失败: $error';
        return params;
      }
      params.addAll(page.params);
      if (page.nextOffset == 0 || page.nextOffset == offset) {
        break;
      }
      offset = page.nextOffset;
    }
    return params;
  }

  Future<int> sendSessionSubscribe(int mask) async {
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.subscribeStreams,
      payload: <int>[mask & 0xFF],
      label: '订阅推送',
    );
    if (resp == null || resp.payload.length < 2 || resp.payload[0] != 0) {
      return 0;
    }
    return resp.payload[1];
  }

  Future<int> sendSessionUnsubscribe(int mask) async {
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.unsubscribeStreams,
      payload: <int>[mask & 0xFF],
      label: '取消订阅',
    );
    if (resp == null || resp.payload.length < 2 || resp.payload[0] != 0) {
      return _sessionSubscriptionMask;
    }
    return resp.payload[1];
  }

  Future<int> readAllSessionParams() async {
    final ordered = _sessionParams.map((e) => e.paramId).toList()..sort();
    final chunk = <int>[];
    _sessionParamValues.clear();
    var totalRead = 0;

    for (final paramId in ordered) {
      chunk.add(paramId);
      if (chunk.length >= 8) {
        totalRead += await _readParamChunk(chunk);
        chunk.clear();
      }
    }
    if (chunk.isNotEmpty) {
      totalRead += await _readParamChunk(chunk);
    }
    return totalRead;
  }

  Future<int> _readParamChunk(List<int> paramIds) async {
    final resp = await _runSessionCommand(
      command: HmiSessionCommand.getParamValuesBatch,
      payload: <int>[paramIds.length & 0xFF, ...paramIds],
      label: '批量读取参数',
    );
    if (resp == null || resp.payload.isEmpty) {
      return 0;
    }
    if ((resp.flags & HmiSessionFlags.error) != 0) {
      final code = resp.payload.first;
      _statusMessage =
          '批量读取参数被拒绝: code=$code ids=${paramIds.map(toHex2).join(",")}';
      return 0;
    }
    final count = resp.payload[0];
    var cursor = 1;
    var readCount = 0;
    for (var i = 0; i < count; i++) {
      if (cursor + 6 > resp.payload.length) {
        break;
      }
      final paramId = resp.payload[cursor] | (resp.payload[cursor + 1] << 8);
      final value =
          resp.payload[cursor + 2] |
          (resp.payload[cursor + 3] << 8) |
          (resp.payload[cursor + 4] << 16) |
          (resp.payload[cursor + 5] << 24);
      _sessionParamValues[paramId] = value;
      readCount++;
      cursor += 6;
    }
    return readCount;
  }

  // ────────────── 内部处理 ──────────────

  void _onIncomingBytes(Uint8List bytes, _PortChannel channel) {
    var hasFrameUpdate = false;
    var hasDgusLogUpdate = false;
    var hasSessionUpdate = false;

    if (channel.acceptsPackerFrames) {
      channel.rxBuffer.addAll(bytes);
      hasFrameUpdate = _consumeFrames(channel);
    }

    if (channel.acceptsDgusFrames) {
      hasDgusLogUpdate = _consumeDgusFrames(bytes, channel);
    }

    if (channel.acceptsSessionFrames) {
      hasSessionUpdate = _consumeSessionFrames(bytes, channel);
    }

    if (hasFrameUpdate || hasDgusLogUpdate || hasSessionUpdate) {
      notifyListeners();
    }
  }

  bool _consumeSessionFrames(Uint8List bytes, _PortChannel channel) {
    var changed = false;
    final results = channel.hmisBamDecoder.pushBytes(bytes);
    for (final result in results) {
      final receivedControl = result.receivedControl;
      if (receivedControl != null) {
        for (final waiter in List<_BamControlWaiter>.from(
          channel.bamControlWaiters,
        )) {
          if (!waiter.completer.isCompleted &&
              waiter.matcher(receivedControl)) {
            waiter.completer.complete(receivedControl);
            channel.bamControlWaiters.remove(waiter);
          }
        }
      }
      final control = result.controlToSend;
      if (control != null) {
        unawaited(_writeSerial(channel.transport, control.encode()));
      }
      final completed = result.completed;
      if (completed == null) {
        continue;
      }
      final frames = channel.sessionDecoder.pushBytes(completed.payload);
      for (final frame in frames) {
        changed = true;
        _appendSessionFrame(frame, channel.config.label);
      }
    }
    return changed;
  }

  Future<void> _writeBamFrames(
    _PortChannel channel, {
    required int address,
    required List<HmiFrame> bamFrames,
  }) async {
    final transport = channel.transport;
    for (final bamFrame in bamFrames) {
      final transactionId = HmisBamFrameBuilder.readTransactionId(
        bamFrame.data,
      );
      final fragmentIndex = HmisBamFrameBuilder.fragmentIndexOf(bamFrame);
      final waiter = _BamControlWaiter(
        (control) =>
            control.address == (address & 0xFF) &&
            control.transactionId == transactionId &&
            control.fragmentIndex == fragmentIndex &&
            (control.isAck || control.isNack),
      );
      channel.bamControlWaiters.add(waiter);
      await _writeSerial(transport, bamFrame.encode());
      final control = await waiter.completer.future.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () => null,
      );
      channel.bamControlWaiters.remove(waiter);
      if (control == null) {
        throw StateError('HMIS-BAM ACK超时');
      }
      if (control.isNack) {
        throw StateError('HMIS-BAM NACK ${control.status.name}');
      }
      if (control.status != HmisBamControlStatus.accepted &&
          control.status != HmisBamControlStatus.ok) {
        throw StateError('HMIS-BAM ACK状态异常 ${control.status.name}');
      }
    }
  }

  bool _consumeDgusFrames(Uint8List bytes, _PortChannel channel) {
    final buf = channel.dgusRxBuffer;
    buf.addAll(bytes);
    var changed = false;

    // 缓冲区溢出保护：噪声/错波特率时限制最大缓冲，防止 OOM
    const maxDgusBuffer = 4096;
    if (buf.length > maxDgusBuffer) {
      buf.removeRange(0, buf.length - maxDgusBuffer);
    }

    while (buf.length >= 4) {
      final start = buf.indexWhere((v) => v == 0x5A);
      if (start < 0) {
        buf.clear();
        return changed;
      }
      if (start > 0) {
        buf.removeRange(0, start);
      }
      if (buf.length < 4) return changed;
      if (buf[1] != 0xA5) {
        buf.removeAt(0);
        continue;
      }
      final payloadLen = buf[2] & 0xFF;
      final frameLen = payloadLen + 3;
      if (payloadLen <= 0 || frameLen > 260) {
        buf.removeAt(0);
        continue;
      }
      if (buf.length < frameLen) return changed;
      final frame = _DgusFrame(
        command: buf[3] & 0xFF,
        data: Uint8List.fromList(buf.sublist(4, frameLen)),
      );
      final rxHex = frame.encode().map((e) => toHex2(e)).join(' ');
      _appendDgusLog('DGUS RX $rxHex', channel.config.label);
      changed = true;
      _dispatchDgusWaiters(channel, frame);
      final decoded = _decodeDgusLogLine(frame);
      if (decoded != null && decoded.isNotEmpty) {
        _appendDgusLog(decoded, channel.config.label);
      }
      buf.removeRange(0, frameLen);
    }
    return changed;
  }

  bool _consumeFrames(_PortChannel channel) {
    // 缓冲区溢出保护：噪声/错波特率时限制最大缓冲，防止 OOM
    const maxBuffer = 4096;
    if (channel.rxBuffer.length > maxBuffer) {
      channel.rxBuffer.removeRange(0, channel.rxBuffer.length - maxBuffer);
    }

    final crcAlgo = channel.config.crcAlgorithm;
    var changed = false;
    while (channel.rxBuffer.length >= HmiFrame.frameLength) {
      final start = channel.rxBuffer.indexWhere(
        (v) =>
            v == HmiFrame.appRequestAddress ||
            v == HmiFrame.appResponseAddress ||
            v == 0x00 ||
            v == 0x20 ||
            v == 0xFA ||
            v == 0xFF,
      );
      if (start < 0) {
        channel.rxBuffer.clear();
        return changed;
      }
      if (start > 0) {
        channel.rxBuffer.removeRange(0, start);
      }
      if (channel.rxBuffer.length < HmiFrame.frameLength) {
        return changed;
      }
      final packet = channel.rxBuffer.sublist(0, HmiFrame.frameLength);
      final decodedFrame = HmiFrame.tryDecode(packet, crcAlgorithm: crcAlgo);
      if (decodedFrame == null) {
        channel.rxBuffer.removeAt(0);
        continue;
      }
      _appendLog('RX', decodedFrame, portLabel: channel.config.label);
      _statusMessage =
          '收到响应（${channel.config.label}）: ${decodeHmiFrame(decodedFrame).summary}';
      channel.rxBuffer.removeRange(0, HmiFrame.frameLength);
      changed = true;
    }
    return changed;
  }

  void _dispatchDgusWaiters(_PortChannel channel, _DgusFrame frame) {
    final index = channel.dgusWaiters.indexWhere((w) => w.matcher(frame));
    if (index < 0) return;
    final waiter = channel.dgusWaiters.removeAt(index);
    if (!waiter.completer.isCompleted) {
      waiter.completer.complete(frame);
    }
  }

  void _appendSessionFrame(HmiSessionFrame frame, String portLabel) {
    _sessionInboundFrameCount++;
    final raw = frame.rawHex;
    final textPayload = String.fromCharCodes(
      frame.payload.where((byte) => byte >= 0x20 && byte <= 0x7E),
    );

    if (frame.type == HmiSessionFrameType.log) {
      final logText = frame.payload.isNotEmpty
          ? String.fromCharCodes(frame.payload.skip(1))
          : textPayload;
      _appendDgusLog(logText.isEmpty ? raw : logText, portLabel);
      return;
    }

    _dispatchSessionWaiters(_channelB, frame);

    if (frame.type == HmiSessionFrameType.event &&
        frame.command == HmiSessionCommand.eventPush &&
        frame.payload.length >= 3) {
      final event = _parseSessionEvent(frame.payload);
      _sessionEvents.insert(0, event);
      if (_sessionEvents.length > 200) {
        _sessionEvents.removeRange(200, _sessionEvents.length);
      }
    }

    if (frame.type == HmiSessionFrameType.event &&
        frame.command == HmiSessionCommand.stackSnapshotPush) {
      try {
        final snapshot = parseStackSnapshotPush(frame.payload);
        _latestStackSnapshot = snapshot;
        _stackSnapshots.insert(0, snapshot);
        if (_stackSnapshots.length > _maxStackSnapshots) {
          _stackSnapshots.removeRange(
            _maxStackSnapshots,
            _stackSnapshots.length,
          );
        }
        _stackTaskStats = mergeStackTaskStats(_stackTaskStats, snapshot);
        _enqueueStackSnapshotForDisk(snapshot);
      } on FormatException {
        // 保持日志可见即可，不因单帧异常影响会话。
      }
    }

    final decoded = _decodeSessionFrame(frame, raw, textPayload);
    final placeholder = HmiFrame(
      address: HmiSessionFrame.sof0,
      function: frame.command.value,
      data: <int>[
        frame.type.value,
        frame.sequence & 0xFF,
        (frame.sequence >> 8) & 0xFF,
        frame.flags,
        ...frame.payload.take(12),
      ],
    );
    final entry = HmiLogEntry(
      direction: frame.type == HmiSessionFrameType.response ? 'RX' : 'EVENT',
      frame: placeholder,
      timestamp: DateTime.now(),
      decoded: decoded,
      portLabel: portLabel,
      rawLineOverride: 'SESSION=${frame.rawHex}',
    );
    _logs.insert(0, entry);
    _trimInMemoryLogsIfNeeded();
    _enqueueLogLineForDisk(_toJsonLine(entry));
  }

  HmiDecodedFrame _decodeSessionFrame(
    HmiSessionFrame frame,
    String raw,
    String textPayload,
  ) {
    final title =
        'USART1会话 ${frame.type == HmiSessionFrameType.response ? "CMD" : frame.type.name.toUpperCase()}=0x${toHex2(frame.command.value)}';
    final payload = frame.payload;

    String fallbackSummary() => textPayload.isEmpty ? raw : textPayload;

    switch (frame.command) {
      case HmiSessionCommand.hello:
        if (payload.length >= 2) {
          return HmiDecodedFrame(
            title: title,
            summary: 'HELLO result=${payload[0]} ver=${payload[1]}',
            rawDataHex: raw,
            errorCode: (frame.flags & HmiSessionFlags.error) != 0
                ? payload[0]
                : null,
          );
        }
      case HmiSessionCommand.deviceInfo:
        if (payload.length >= 5) {
          final name = payload.length > 5
              ? utf8.decode(payload.sublist(5))
              : '';
          final caps = payload[3] | (payload[4] << 8);
          return HmiDecodedFrame(
            title: title,
            summary:
                'DEVICE_INFO result=${payload[0]} ver=${payload[1]}.${payload[2]} caps=0x${caps.toRadixString(16).padLeft(4, '0').toUpperCase()}'
                '${name.isEmpty ? "" : " name=$name"}',
            rawDataHex: raw,
            errorCode: (frame.flags & HmiSessionFlags.error) != 0
                ? payload[0]
                : null,
          );
        }
      case HmiSessionCommand.getGroupList:
        try {
          final page = parseGroupCatalogPage(payload);
          return HmiDecodedFrame(
            title: title,
            summary:
                'GROUP_LIST count=${page.groups.length}/${page.totalCount} next=${page.nextOffset}'
                '${page.groups.isEmpty ? "" : " first=${page.groups.first.groupKey}/${page.groups.first.groupName}"}',
            rawDataHex: raw,
          );
        } on FormatException {
          break;
        }
      case HmiSessionCommand.getParamList:
        try {
          final page = parseParamCatalogPage(payload);
          return HmiDecodedFrame(
            title: title,
            summary:
                'PARAM_LIST count=${page.params.length}/${page.totalCount} next=${page.nextOffset}'
                '${page.params.isEmpty ? "" : " first=${page.params.first.paramKey}/${page.params.first.paramName}"}',
            rawDataHex: raw,
          );
        } on FormatException {
          break;
        }
      case HmiSessionCommand.getParamValuesBatch:
        if (payload.isNotEmpty) {
          return HmiDecodedFrame(
            title: title,
            summary: 'PARAM_VALUES count=${payload[0]}',
            rawDataHex: raw,
            errorCode: (frame.flags & HmiSessionFlags.error) != 0
                ? payload[0]
                : null,
          );
        }
      case HmiSessionCommand.subscribeStreams:
      case HmiSessionCommand.unsubscribeStreams:
        if (payload.length >= 2) {
          return HmiDecodedFrame(
            title: title,
            summary:
                '${frame.command == HmiSessionCommand.subscribeStreams ? "SUBSCRIBE" : "UNSUBSCRIBE"} result=${payload[0]} mask=0x${toHex2(payload[1])}',
            rawDataHex: raw,
            errorCode: (frame.flags & HmiSessionFlags.error) != 0
                ? payload[0]
                : null,
          );
        }
      case HmiSessionCommand.getDeviceStatus:
        if (payload.length >= 12) {
          return HmiDecodedFrame(
            title: title,
            summary:
                'STATUS result=${payload[0]} run=${payload[1]} busy=0x${toHex2(payload[3])} boot=${payload[8]} stop_pending=${payload[9]} alarm=0x${toHex2(payload[10])}',
            rawDataHex: raw,
            errorCode: (frame.flags & HmiSessionFlags.error) != 0
                ? payload[0]
                : null,
          );
        }
      case HmiSessionCommand.getAlarmStatus:
        if (payload.length >= 3) {
          return HmiDecodedFrame(
            title: title,
            summary:
                'ALARM result=${payload[0]} code=0x${toHex2(payload[1])} latched=${payload[2]}',
            rawDataHex: raw,
            errorCode: (frame.flags & HmiSessionFlags.error) != 0
                ? payload[0]
                : null,
          );
        }
      case HmiSessionCommand.eventPush:
        if (payload.length >= 3) {
          final event = _parseSessionEvent(payload);
          return HmiDecodedFrame(
            title: title,
            summary: event.summary,
            rawDataHex: raw,
          );
        }
      case HmiSessionCommand.stackSnapshotPush:
        try {
          final snapshot = parseStackSnapshotPush(payload);
          return HmiDecodedFrame(
            title: title,
            summary:
                'STACK_SNAPSHOT tasks=${snapshot.tasks.length} riskiest=${snapshot.summary.riskiestTaskName} free=${snapshot.summary.totalFreeWords}',
            rawDataHex: raw,
          );
        } on FormatException {
          break;
        }
      default:
        break;
    }

    return HmiDecodedFrame(
      title: title,
      summary: fallbackSummary(),
      rawDataHex: raw,
    );
  }

  HmiSessionEventEntry _parseSessionEvent(Uint8List payload) {
    final code = payload[0];
    final value0 = payload[1];
    final value1 = payload[2];
    final summary = switch (code) {
      0x01 => '状态变化: 0x${toHex2(value0)} -> 0x${toHex2(value1)}',
      0x02 => '运行标志: $value0 -> $value1',
      0x03 => '启动链路: $value0 -> $value1',
      0x04 => '报警码: 0x${toHex2(value0)} -> 0x${toHex2(value1)}',
      0x05 => '报警锁存: $value0 -> $value1',
      _ => '事件 0x${toHex2(code)}: $value0 -> $value1',
    };
    return HmiSessionEventEntry(
      timestamp: DateTime.now(),
      code: code,
      value0: value0,
      value1: value1,
      summary: summary,
    );
  }

  void _appendSessionTx(HmiSessionFrame frame, String portLabel) {
    final entry = HmiLogEntry(
      direction: 'TX',
      frame: HmiFrame(
        address: HmiSessionFrame.sof0,
        function: frame.command.value,
        data: <int>[
          frame.type.value,
          frame.sequence & 0xFF,
          (frame.sequence >> 8) & 0xFF,
          frame.flags,
          ...frame.payload.take(12),
        ],
      ),
      timestamp: DateTime.now(),
      decoded: HmiDecodedFrame(
        title: 'USART1会话 TX CMD=0x${toHex2(frame.command.value)}',
        summary: frame.rawHex,
        rawDataHex: frame.rawHex,
      ),
      portLabel: portLabel,
      rawLineOverride: 'SESSION=${frame.rawHex}',
    );
    _logs.insert(0, entry);
    _trimInMemoryLogsIfNeeded();
    _enqueueLogLineForDisk(_toJsonLine(entry));
  }

  void _dispatchSessionWaiters(_PortChannel channel, HmiSessionFrame frame) {
    final index = channel.sessionWaiters.indexWhere((w) => w.matcher(frame));
    if (index < 0) return;
    final waiter = channel.sessionWaiters.removeAt(index);
    if (!waiter.completer.isCompleted) {
      waiter.completer.complete(frame);
    }
  }

  void _appendLog(
    String direction,
    HmiFrame frame, {
    String? note,
    int? attempt,
    String portLabel = '',
  }) {
    final entry = HmiLogEntry(
      direction: direction,
      frame: frame,
      timestamp: DateTime.now(),
      decoded: decodeHmiFrame(frame, direction: direction),
      note: note,
      attempt: attempt,
      portLabel: portLabel,
    );
    _logs.insert(0, entry);
    _trimInMemoryLogsIfNeeded();
    _enqueueLogLineForDisk(_toJsonLine(entry));
  }

  /// 追加 DGUS 协议日志条目（由变量帧解析而来）。
  void _appendDgusLog(String text, String portLabel) {
    final now = DateTime.now();
    final stackLevel = _parseStackLevelFromLog(text);
    if (stackLevel != null) {
      _stackLevelSamples.insert(
        0,
        StackLevelSample(timestamp: now, level: stackLevel),
      );
      if (_stackLevelSamples.length > _maxStackLevelSamples) {
        _stackLevelSamples.removeLast();
      }
    }
    final snapshot = _stackStatsCollector.addLogLine(text, timestamp: now);
    if (snapshot != null) {
      _latestStackSnapshot = snapshot;
      _stackSnapshots.insert(0, snapshot);
      if (_stackSnapshots.length > _maxStackSnapshots) {
        _stackSnapshots.removeRange(_maxStackSnapshots, _stackSnapshots.length);
      }
      _stackTaskStats = mergeStackTaskStats(_stackTaskStats, snapshot);
      _enqueueStackSnapshotForDisk(snapshot);
    }

    final entry = HmiLogEntry(
      direction: 'LOG',
      frame: _dgusPlaceholder,
      timestamp: now,
      decoded: HmiDecodedFrame(title: 'DGUS日志', summary: text, rawDataHex: ''),
      portLabel: portLabel,
    );
    _logs.insert(0, entry);
    _trimInMemoryLogsIfNeeded();
    _enqueueLogLineForDisk(_toJsonLine(entry));
  }

  void _trimInMemoryLogsIfNeeded() {
    if (_logs.length > _maxInMemoryLogs) {
      _logs.removeRange(_maxInMemoryLogs, _logs.length);
    }
  }

  String _toJsonLine(HmiLogEntry entry) {
    final payloadHex = payloadToHex(entry.frame.data);
    final Map<String, dynamic> obj = <String, dynamic>{
      'ts': entry.timestamp.toIso8601String(),
      'port': entry.portLabel,
      'direction': entry.direction,
      'address': entry.frame.address,
      'function': entry.frame.function,
      'payload_hex': payloadHex,
      'decoded_title': entry.decoded.title,
      'decoded_summary': entry.decoded.summary,
      'decoded_raw_hex': entry.decoded.rawDataHex,
      'attempt': entry.attempt,
      'note': entry.note,
      'pretty': entry.pretty,
    };
    return '${jsonEncode(obj)}\n';
  }

  void _enqueueLogLineForDisk(String line) {
    _diskLogBuffer.write(line);
    _pendingDiskLogLines++;
    if (_pendingDiskLogLines >= _diskFlushBatchSize) {
      unawaited(_flushLogsToDisk());
    }
  }

  void _enqueueStackSnapshotForDisk(StackSnapshot snapshot) {
    _stackDiskBuffer.write('${jsonEncode(snapshot.toJson())}\n');
    _pendingStackDiskLines++;
    if (_pendingStackDiskLines >= _diskFlushBatchSize) {
      unawaited(_flushStackSnapshotsToDisk());
    }
  }

  Future<void> _flushLogsToDisk() async {
    if (_diskFlushInProgress || _pendingDiskLogLines == 0) {
      return;
    }
    _diskFlushInProgress = true;
    final chunk = _diskLogBuffer.toString();
    _diskLogBuffer.clear();
    _pendingDiskLogLines = 0;
    try {
      _rollingLogPath = await appendLogsChunk(
        chunk,
        existingPath: _rollingLogPath,
      );
    } catch (_) {
      // Web/权限受限平台自动忽略，保持主流程稳定。
      // 下次仍可继续尝试写盘。
    } finally {
      _diskFlushInProgress = false;
      if (_pendingDiskLogLines > 0) {
        unawaited(_flushLogsToDisk());
      }
    }
  }

  Future<void> _flushStackSnapshotsToDisk() async {
    if (_stackDiskFlushInProgress || _pendingStackDiskLines == 0) {
      return;
    }
    _stackDiskFlushInProgress = true;
    final chunk = _stackDiskBuffer.toString();
    _stackDiskBuffer.clear();
    _pendingStackDiskLines = 0;
    try {
      _rollingStackLogPath = await appendLogsChunk(
        chunk,
        existingPath: _rollingStackLogPath,
        filePrefix: 'hmi_stack_stats',
      );
    } catch (_) {
      // Web/权限受限平台自动忽略，保持主流程稳定。
    } finally {
      _stackDiskFlushInProgress = false;
      if (_pendingStackDiskLines > 0) {
        unawaited(_flushStackSnapshotsToDisk());
      }
    }
  }

  Future<HmiLogBundleManifest> prepareLogBundleManifest() async {
    await _flushLogsToDisk();
    await _flushStackSnapshotsToDisk();
    return HmiLogBundleManifest(
      rollingLogPath: _rollingLogPath,
      rollingStackLogPath: _rollingStackLogPath,
    );
  }

  static final HmiFrame _dgusPlaceholder = HmiFrame(
    address: 0,
    function: 0,
    data: const <int>[],
  );

  int? _parseStackLevelFromLog(String text) {
    final match = RegExp(
      r'\bSTACK_LEVEL\s*=\s*(0x[0-9a-fA-F]+|\d+)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) {
      return null;
    }

    final raw = (match.group(1) ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    if (raw.startsWith('0x') || raw.startsWith('0X')) {
      return int.tryParse(raw.substring(2), radix: 16);
    }
    return int.tryParse(raw);
  }

  String? _decodeDgusLogLine(_DgusFrame frame) {
    if (frame.command != 0x82 || frame.data.length < 4) {
      return null;
    }
    final addr = (frame.data[0] << 8) | frame.data[1];
    if (addr < 0x3000 || addr > 0x301F) {
      return null;
    }
    final bytes = frame.data.sublist(2);
    final ascii = bytes.where((b) => b >= 0x20 && b <= 0x7E).toList();
    if (ascii.isEmpty) {
      return null;
    }
    return String.fromCharCodes(ascii);
  }

  @override
  void dispose() {
    _bamTimeoutTimer?.cancel();
    _bamTimeoutTimer = null;
    unawaited(_flushLogsToDisk());
    unawaited(_flushStackSnapshotsToDisk());
    try {
      _subscriptionA?.cancel();
    } catch (e) {
      debugPrint('取消订阅 A 异常: $e');
    }
    try {
      _subscriptionB?.cancel();
    } catch (e) {
      debugPrint('取消订阅 B 异常: $e');
    }
    try {
      _connectionSubscriptionA?.cancel();
    } catch (e) {
      debugPrint('取消状态订阅 A 异常: $e');
    }
    try {
      _connectionSubscriptionB?.cancel();
    } catch (e) {
      debugPrint('取消状态订阅 B 异常: $e');
    }
    _channelA.dispose();
    _channelB.dispose();
    super.dispose();
  }
}

/// 空串口实现，用于未提供第二个串口时的占位。
class SerialTransportDummy implements SerialTransport {
  @override
  Future<List<String>> availablePorts() async => <String>[];

  @override
  Future<void> connect({
    required String portName,
    required int baudRate,
    int dataBits = 8,
    int stopBits = 1,
    int parity = 0,
    int flowControl = 0,
  }) async {
    throw StateError('未提供串口 B 实现');
  }

  @override
  Future<void> disconnect() async {}

  @override
  bool get isConnected => false;

  @override
  Stream<SerialConnectionState> get connectionStates =>
      const Stream<SerialConnectionState>.empty();

  @override
  Stream<Uint8List> get incomingBytes => const Stream<Uint8List>.empty();

  @override
  Future<void> write(Uint8List bytes) async {
    throw StateError('未提供串口 B 实现');
  }
}
