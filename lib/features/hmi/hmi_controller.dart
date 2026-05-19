import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../core/protocol/crc_algorithm.dart';
import '../../core/protocol/hmi_frame.dart';
import '../../core/serial/serial_transport.dart';
import 'hmi_port_config.dart';
import 'hmi_protocol.dart';

class HmiLogEntry {
  HmiLogEntry({
    required this.direction,
    required this.frame,
    required this.timestamp,
    required this.decoded,
    this.note,
    this.attempt,
    this.portLabel = '',
  });

  final String direction;
  final HmiFrame frame;
  final DateTime timestamp;
  final HmiDecodedFrame decoded;
  final String? note;
  final int? attempt;
  final String portLabel;

  String get pretty {
    final port = portLabel.isNotEmpty ? ' [$portLabel]' : '';
    final base =
        '${DateFormat('HH:mm:ss.SSS').format(timestamp)}$port [$direction] '
        'ADDR=0x${toHex2(frame.address)} FUNC=0x${toHex2(frame.function)} '
        'DATA=${payloadToHex(frame.data)}';
    final decodePart = ' ${decoded.title} ${decoded.summary}';
    final attemptPart = attempt == null ? '' : ' (尝试#$attempt)';
    final notePart = note == null ? '' : ' [$note]';
    return '$base$decodePart$attemptPart$notePart';
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

class _FrameWaiter {
  _FrameWaiter(this.expectedFunctions);

  final Set<int> expectedFunctions;
  final Completer<HmiFrame> completer = Completer<HmiFrame>();
}

class _DgusFrame {
  _DgusFrame({required this.command, required this.data});
  final int command;
  final Uint8List data;
}

class _DgusWaiter {
  _DgusWaiter(this.matcher);
  final bool Function(_DgusFrame frame) matcher;
  final Completer<_DgusFrame> completer = Completer<_DgusFrame>();
}

/// 单个串口通道的状态与处理逻辑。
class _PortChannel {
  _PortChannel(this.transport, this.configRef);

  final SerialTransport transport;
  final List<int> rxBuffer = <int>[];
  final List<int> dgusRxBuffer = <int>[];
  final List<_FrameWaiter> waiters = <_FrameWaiter>[];
  final List<_DgusWaiter> dgusWaiters = <_DgusWaiter>[];
  StreamSubscription<Uint8List>? subscription;

  /// 指向外部可变的 HmiPortConfig 引用，以便读取最新配置。
  final HmiPortConfig Function() configRef;

  HmiPortConfig get config => configRef();

  void dispose() {
    subscription?.cancel();
    subscription = null;
    transport.disconnect();
    rxBuffer.clear();
    dgusRxBuffer.clear();
    waiters.clear();
    dgusWaiters.clear();
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
      _portBConfig = HmiPortConfig(baudRate: 9600, crcAlgorithm: CrcAlgorithm.dgus, label: '端口 B（打包机直连）') {
    _channelA = _PortChannel(_transportA, () => _portAConfig);
    _channelB = _PortChannel(_transportB, () => _portBConfig);
    _subscriptionA = _transportA.incomingBytes.listen(
      (bytes) => _onIncomingBytes(bytes, _channelA),
    );
    if (transportB != null) {
      _subscriptionB = _transportB.incomingBytes.listen(
        (bytes) => _onIncomingBytes(bytes, _channelB),
      );
    }
  }

  final SerialTransport _transportA;
  final SerialTransport _transportB;
  late final _PortChannel _channelA;
  late final _PortChannel _channelB;

  StreamSubscription<Uint8List>? _subscriptionA;
  StreamSubscription<Uint8List>? _subscriptionB;

  final List<HmiLogEntry> _logs = <HmiLogEntry>[];

  Future<void> _txChain = Future<void>.value();

  HmiPortConfig _portAConfig;
  HmiPortConfig _portBConfig;
  String? _statusMessage;
  HmiRetryPolicy _retryPolicy = const HmiRetryPolicy();

  List<String> _portsA = <String>[];
  List<String> _portsB = <String>[];

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
  HmiRetryPolicy get retryPolicy => _retryPolicy;
  List<HmiLogEntry> get logs => List<HmiLogEntry>.unmodifiable(_logs);

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

  // ────────────── 通用 ──────────────

  void updateRetryPolicy(HmiRetryPolicy policy) {
    _retryPolicy = policy;
    _statusMessage =
        '策略更新: 超时${policy.timeoutMs}ms, 重试${policy.maxRetries}次, 间隔${policy.retryIntervalMs}ms';
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
      await _transportA.connect(
        portName: port,
        baudRate: _portAConfig.baudRate,
      );
      _statusMessage = '端口 A 已连接: $port @ ${_portAConfig.baudRate}';
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
      await _transportB.connect(
        portName: port,
        baudRate: _portBConfig.baudRate,
      );
      _statusMessage = '端口 B 已连接: $port @ ${_portBConfig.baudRate}';
      notifyListeners();
    } catch (error) {
      _statusMessage = '端口 B 连接失败: $error';
      notifyListeners();
    }
  }

  Future<void> disconnectPortA() async {
    await _transportA.disconnect();
    _clearWaiters(_channelA);
    _statusMessage = '端口 A 已断开';
    notifyListeners();
  }

  Future<void> disconnectPortB() async {
    await _transportB.disconnect();
    _clearWaiters(_channelB);
    _statusMessage = '端口 B 已断开';
    notifyListeners();
  }

  /// 清理通道中所有未完成的等待者，防止断开后内存泄漏。
  void _clearWaiters(_PortChannel channel) {
    for (final w in channel.waiters) {
      if (!w.completer.isCompleted) {
        w.completer.completeError(StateError('串口已断开'));
      }
    }
    channel.waiters.clear();
  }

  /// 向后兼容：连接/断开端口 A。
  Future<void> connectOrDisconnect() async {
    if (_transportA.isConnected) {
      await disconnectPortA();
    } else {
      await connectPortA();
    }
  }

  // ────────────── 命令执行 ──────────────

  /// 执行命令，可选择使用哪个端口通道。
  ///
  /// [usePortB] 为 true 时使用端口 B，否则使用端口 A（默认）。
  Future<CommandExecutionResult> runCommand(
    HmiCommandRequest request, {
    HmiRetryPolicy? policy,
    bool usePortB = false,
  }) async {
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

    final p = policy ?? _retryPolicy;
    final start = DateTime.now();
    final totalAttempts = p.maxRetries + 1;
    CommandExecutionResult finalResult = const CommandExecutionResult(
      success: false,
      message: '执行失败',
    );

    // 使用帧自身指定的 CRC 算法构建帧（尊重调用者语义）。
    final frameWithCrc = HmiFrame(
      address: request.frame.address,
      function: request.frame.function,
      data: request.frame.data.toList(),
      crcAlgorithm: request.frame.crcAlgorithm,
    );

    // 等待前一条命令完成（忽略前条错误，避免链断裂死锁）
    try {
      await _txChain;
    } catch (_) {
      // 前一条命令异常，继续执行当前命令
    }
    _txChain = () async {
      for (var attempt = 1; attempt <= totalAttempts; attempt++) {
        final waiter = _createWaiter(channel, request.expectedFunctions);
        try {
          await transport.write(frameWithCrc.encode());
          _appendLog(
            'TX',
            frameWithCrc,
            note: request.note,
            attempt: attempt,
            portLabel: portLabel,
          );
        } catch (error) {
          _removeWaiter(channel, waiter);
          finalResult = CommandExecutionResult(
            success: false,
            message: '发送失败: $error',
          );
          break;
        }

        try {
          final response = await waiter.completer.future.timeout(
            Duration(milliseconds: p.timeoutMs),
          );
          final elapsed = DateTime.now().difference(start);
          final function = request.frame.function & 0xFF;
          final isPackerResponse = function >= 0x40 && function <= 0x53;
          if (isPackerResponse) {
            final resultCode = response.data[0] & 0xFF;
            if (resultCode != 0x00) {
              finalResult = CommandExecutionResult(
                success: false,
                message:
                    '${request.label}失败: ${packerResultName(resultCode)}'
                    '(0x${toHex2(resultCode)})',
                response: response,
                elapsed: elapsed,
                attempts: attempt,
              );
              break;
            }
          }
          finalResult = CommandExecutionResult(
            success: true,
            message: '${request.label}成功',
            response: response,
            elapsed: elapsed,
            attempts: attempt,
          );
          break;
        } on TimeoutException {
          _removeWaiter(channel, waiter);
          if (attempt >= totalAttempts) {
            finalResult = CommandExecutionResult(
              success: false,
              message: '${request.label}超时(${p.timeoutMs}ms)',
              elapsed: DateTime.now().difference(start),
              attempts: attempt,
            );
            break;
          }
          await Future<void>.delayed(Duration(milliseconds: p.retryIntervalMs));
        } catch (error) {
          _removeWaiter(channel, waiter);
          finalResult = CommandExecutionResult(
            success: false,
            message: '${request.label}失败: $error',
          );
          break;
        }
      }

      _statusMessage = finalResult.message;
      notifyListeners();
    }();

    await _txChain;
    return finalResult;
  }

  /// 向后兼容：使用端口 A 发送命令。
  Future<CommandExecutionResult> runCommandPortA(
    HmiCommandRequest request, {
    HmiRetryPolicy? policy,
  }) {
    return runCommand(request, policy: policy, usePortB: false);
  }

  /// 使用端口 B 发送命令。
  Future<CommandExecutionResult> runCommandPortB(
    HmiCommandRequest request, {
    HmiRetryPolicy? policy,
  }) {
    return runCommand(request, policy: policy, usePortB: true);
  }

  // ────────────── 打包机命令（端口 B ─ 若端口 B 未连接则回退到端口 A） ──────────────

  Future<CommandExecutionResult> sendPackerControl({
    required int nodeAddress,
    required int action,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.control,
      nodeAddress: nodeAddress,
      payload: <int>[action & 0xFF],
    );
  }

  Future<CommandExecutionResult> sendPackerStatus({required int nodeAddress}) {
    return _runPackerCommand(
      HmiPackerFunction.status,
      nodeAddress: nodeAddress,
    );
  }

  Future<CommandExecutionResult> sendPackerTriggerBag({
    required int nodeAddress,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.triggerBag,
      nodeAddress: nodeAddress,
      payload: const <int>[0x01, 0x00],
    );
  }

  Future<CommandExecutionResult> sendPackerTriggerSeal({
    required int nodeAddress,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.triggerSeal,
      nodeAddress: nodeAddress,
      payload: const <int>[0x01, 0x00],
    );
  }

  Future<CommandExecutionResult> sendPackerTriggerDeliver({
    required int nodeAddress,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.triggerDeliver,
      nodeAddress: nodeAddress,
      payload: const <int>[0x01, 0x00],
    );
  }

  Future<CommandExecutionResult> sendPackerClearFlag({
    required int nodeAddress,
    required int flagId,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.clearFlag,
      nodeAddress: nodeAddress,
      payload: <int>[flagId & 0xFF],
    );
  }

  Future<CommandExecutionResult> sendPackerAlarmQuery({
    required int nodeAddress,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.alarmQuery,
      nodeAddress: nodeAddress,
    );
  }

  Future<CommandExecutionResult> sendPackerPrinterForward({
    required int nodeAddress,
    int printerCmd = 0x81,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.printerForward,
      nodeAddress: nodeAddress,
      payload: <int>[printerCmd & 0xFF],
    );
  }

  Future<CommandExecutionResult> sendPackerVersion({required int nodeAddress}) {
    return _runPackerCommand(
      HmiPackerFunction.version,
      nodeAddress: nodeAddress,
    );
  }

  Future<CommandExecutionResult> sendPackerResetFault({
    required int nodeAddress,
    required int scope,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.resetFault,
      nodeAddress: nodeAddress,
      payload: <int>[scope & 0xFF],
    );
  }

  /// 读取单个运行时参数。
  Future<int?> sendParamRead({
    required int nodeAddress,
    required int paramId,
  }) async {
    final dgusAddr = 0x2000 + ((paramId - 0x10) * 2);
    final resp = await _runDgusCommand(
      tx: <int>[0x5A, 0xA5, 0x04, 0x83, (dgusAddr >> 8) & 0xFF, dgusAddr & 0xFF, 0x02],
      matcher: (f) =>
          f.command == 0x83 &&
          f.data.length >= 7 &&
          f.data[0] == ((dgusAddr >> 8) & 0xFF) &&
          f.data[1] == (dgusAddr & 0xFF) &&
          f.data[2] == 0x02,
      label: 'DGUS读取',
    );
    if (resp == null) return null;
    return (resp.data[3] << 24) |
        (resp.data[4] << 16) |
        (resp.data[5] << 8) |
        resp.data[6];
  }

  /// 写入单个运行时参数 (仅 RAM, 不自动保存)。
  Future<int?> sendParamWrite({
    required int nodeAddress,
    required int paramId,
    required int value,
  }) async {
    final dgusAddr = 0x2000 + ((paramId - 0x10) * 2);
    final w0 = (value >> 16) & 0xFFFF;
    final w1 = value & 0xFFFF;
    final resp = await _runDgusCommand(
      tx: <int>[
        0x5A,
        0xA5,
        0x07,
        0x82,
        (dgusAddr >> 8) & 0xFF,
        dgusAddr & 0xFF,
        (w0 >> 8) & 0xFF,
        w0 & 0xFF,
        (w1 >> 8) & 0xFF,
        w1 & 0xFF,
      ],
      matcher: (f) =>
          f.command == 0x82 &&
          f.data.length >= 2 &&
          f.data[0] == 0x4F &&
          f.data[1] == 0x4B,
      label: 'DGUS写入',
    );
    if (resp == null) return null;
    return value;
  }

  /// 保存当前运行时参数到 EEPROM。
  Future<bool> sendParamSave({required int nodeAddress}) async {
    final resp = await _runDgusCommand(
      tx: const <int>[0x5A, 0xA5, 0x05, 0x82, 0x40, 0x00, 0x00, 0x01],
      matcher: (f) =>
          f.command == 0x82 &&
          f.data.length >= 2 &&
          f.data[0] == 0x4F &&
          f.data[1] == 0x4B,
      label: 'DGUS保存',
    );
    return resp != null;
  }

  Future<bool> sendParamLoad({
    required int nodeAddress,
    required int action,
  }) async {
    final addr = (action == 0) ? 0x4001 : 0x4002;
    final resp = await _runDgusCommand(
      tx: <int>[
        0x5A,
        0xA5,
        0x05,
        0x82,
        (addr >> 8) & 0xFF,
        addr & 0xFF,
        0x00,
        0x01,
      ],
      matcher: (f) =>
          f.command == 0x82 &&
          f.data.length >= 2 &&
          f.data[0] == 0x4F &&
          f.data[1] == 0x4B,
      label: (action == 0) ? 'DGUS加载EEPROM' : 'DGUS恢复默认',
    );
    return resp != null;
  }

  /// 读取 DGUS 系统信息区 (VP 0x1000~0x1003)。
  ///
  /// 返回 4 个 uint16_t 值: [state, running, bootDone, alarmCode]。
  /// 当门禁锁定（机器运行中）时返回 null。
  Future<List<int>?> sendDgusSystemInfo({required int nodeAddress}) async {
    final resp = await _runDgusCommand(
      tx: const <int>[0x5A, 0xA5, 0x04, 0x83, 0x10, 0x00, 0x04],
      matcher: (f) =>
          f.command == 0x83 &&
          f.data.length >= 11 &&
          f.data[0] == 0x10 &&
          f.data[1] == 0x00 &&
          f.data[2] == 0x04,
      label: 'DGUS系统信息',
    );
    if (resp == null) return null;
    return <int>[
      (resp.data[3] << 8) | resp.data[4],   // 0x1000: state
      (resp.data[5] << 8) | resp.data[6],   // 0x1001: running
      (resp.data[7] << 8) | resp.data[8],   // 0x1002: boot_done
      (resp.data[9] << 8) | resp.data[10],  // 0x1003: alarm
    ];
  }

  Future<_DgusFrame?> _runDgusCommand({
    required List<int> tx,
    required bool Function(_DgusFrame frame) matcher,
    required String label,
  }) async {
    final channel = _transportB.isConnected ? _channelB : _channelA;
    final transport = channel.transport;
    if (!transport.isConnected) {
      _statusMessage = '$label失败: 串口未连接';
      notifyListeners();
      return null;
    }

    final waiter = _DgusWaiter(matcher);
    channel.dgusWaiters.add(waiter);
    await transport.write(Uint8List.fromList(tx));
    final txHex = tx.map((e) => toHex2(e)).join(' ');
    _appendDgusLog('DGUS TX $txHex', channel.config.label);

    try {
      final frame = await waiter.completer.future.timeout(
        Duration(milliseconds: _retryPolicy.timeoutMs),
      );
      _statusMessage = '$label成功';
      notifyListeners();
      return frame;
    } on TimeoutException {
      channel.dgusWaiters.remove(waiter);
      _statusMessage = '$label超时(${_retryPolicy.timeoutMs}ms)';
      notifyListeners();
      return null;
    } catch (_) {
      channel.dgusWaiters.remove(waiter);
      _statusMessage = '$label失败';
      notifyListeners();
      return null;
    }
  }

  Future<CommandExecutionResult> _runPackerCommand(
    HmiPackerFunction function, {
    required int nodeAddress,
    List<int> payload = const <int>[],
  }) {
    // 打包机命令默认走端口 B（若端口 B 未连接则回退到端口 A）
    final usePortB = _transportB.isConnected;
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
      usePortB: usePortB,
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
    notifyListeners();
  }

  // ────────────── 内部处理 ──────────────

  void _onIncomingBytes(Uint8List bytes, _PortChannel channel) {
    if (channel == _channelB) {
      _consumeDgusFrames(bytes, channel);
      return;
    }

    channel.rxBuffer.addAll(bytes);
    _consumeFrames(channel);
  }

  void _consumeDgusFrames(Uint8List bytes, _PortChannel channel) {
    final buf = channel.dgusRxBuffer;
    buf.addAll(bytes);
    while (buf.length >= 4) {
      final start = buf.indexWhere((v) => v == 0x5A);
      if (start < 0) {
        buf.clear();
        return;
      }
      if (start > 0) {
        buf.removeRange(0, start);
      }
      if (buf.length < 4) return;
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
      if (buf.length < frameLen) return;
      final frame = _DgusFrame(
        command: buf[3] & 0xFF,
        data: Uint8List.fromList(buf.sublist(4, frameLen)),
      );
      _dispatchDgusWaiters(channel, frame);
      final decoded = _decodeDgusLogLine(frame);
      if (decoded != null && decoded.isNotEmpty) {
        _appendDgusLog(decoded, channel.config.label);
      }
      buf.removeRange(0, frameLen);
    }
  }

  void _consumeFrames(_PortChannel channel) {
    // 缓冲区溢出保护：噪声/错波特率时限制最大缓冲，防止 OOM
    const maxBuffer = 4096;
    if (channel.rxBuffer.length > maxBuffer) {
      channel.rxBuffer.removeRange(0, channel.rxBuffer.length - maxBuffer);
    }

    final crcAlgo = channel.config.crcAlgorithm;
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
        return;
      }
      if (start > 0) {
        channel.rxBuffer.removeRange(0, start);
      }
      if (channel.rxBuffer.length < HmiFrame.frameLength) {
        return;
      }
      final packet = channel.rxBuffer.sublist(0, HmiFrame.frameLength);
      final decodedFrame = HmiFrame.tryDecode(packet, crcAlgorithm: crcAlgo);
      if (decodedFrame == null) {
        channel.rxBuffer.removeAt(0);
        continue;
      }
      _appendLog('RX', decodedFrame, portLabel: channel.config.label);
      _dispatchWaiters(channel, decodedFrame);
      _statusMessage =
          '收到响应（${channel.config.label}）: ${decodeHmiFrame(decodedFrame).summary}';
      channel.rxBuffer.removeRange(0, HmiFrame.frameLength);
      notifyListeners();
    }
  }

  _FrameWaiter _createWaiter(_PortChannel channel, Set<int> expectedFunctions) {
    final waiter = _FrameWaiter(expectedFunctions);
    channel.waiters.add(waiter);
    return waiter;
  }

  /// 将收到的帧分发给第一个匹配功能码的等待者。
  /// 一帧只分发给一个 waiter，避免并发请求互相吞没。
  void _dispatchWaiters(_PortChannel channel, HmiFrame frame) {
    final index = channel.waiters.indexWhere(
      (w) => w.expectedFunctions.contains(frame.function),
    );
    if (index < 0) return;
    final waiter = channel.waiters.removeAt(index);
    if (!waiter.completer.isCompleted) {
      waiter.completer.complete(frame);
    }
  }

  void _dispatchDgusWaiters(_PortChannel channel, _DgusFrame frame) {
    final index = channel.dgusWaiters.indexWhere((w) => w.matcher(frame));
    if (index < 0) return;
    final waiter = channel.dgusWaiters.removeAt(index);
    if (!waiter.completer.isCompleted) {
      waiter.completer.complete(frame);
    }
  }

  void _removeWaiter(_PortChannel channel, _FrameWaiter waiter) {
    channel.waiters.remove(waiter);
  }

  void _appendLog(
    String direction,
    HmiFrame frame, {
    String? note,
    int? attempt,
    String portLabel = '',
  }) {
    _logs.insert(
      0,
      HmiLogEntry(
        direction: direction,
        frame: frame,
        timestamp: DateTime.now(),
        decoded: decodeHmiFrame(frame),
        note: note,
        attempt: attempt,
        portLabel: portLabel,
      ),
    );
    if (_logs.length > 800) {
      _logs.removeLast();
    }
  }

  /// 追加 DBUS/DGUS 协议日志条目（由变量帧解析而来）。
  void _appendDgusLog(String text, String portLabel) {
    // 构造占位帧以满足 HmiLogEntry 非空约束
    final placeholder = HmiFrame(address: 0, function: 0, data: const <int>[]);
    _logs.insert(
      0,
      HmiLogEntry(
        direction: 'LOG',
        frame: placeholder,
        timestamp: DateTime.now(),
        decoded: HmiDecodedFrame(title: 'DGUS日志', summary: text, rawDataHex: ''),
        portLabel: portLabel,
      ),
    );
    if (_logs.length > 800) {
      _logs.removeLast();
    }
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
    _subscriptionA?.cancel();
    _subscriptionB?.cancel();
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
  Future<void> connect({String? portName, int baudRate = 115200}) async {
    throw StateError('未提供串口 B 实现');
  }

  @override
  Future<void> disconnect() async {}

  @override
  bool get isConnected => false;

  @override
  Stream<Uint8List> get incomingBytes => const Stream<Uint8List>.empty();

  @override
  Future<void> write(Uint8List bytes) async {
    throw StateError('未提供串口 B 实现');
  }
}
