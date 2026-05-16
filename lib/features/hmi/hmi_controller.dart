import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../core/protocol/hmi_frame.dart';
import '../../core/serial/serial_transport.dart';
import 'hmi_protocol.dart';

class HmiLogEntry {
  HmiLogEntry({
    required this.direction,
    required this.frame,
    required this.timestamp,
    required this.decoded,
    this.note,
    this.attempt,
  });

  final String direction;
  final HmiFrame frame;
  final DateTime timestamp;
  final HmiDecodedFrame decoded;
  final String? note;
  final int? attempt;

  String get pretty {
    final base =
        '${DateFormat('HH:mm:ss.SSS').format(timestamp)} [$direction] '
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

class HmiController extends ChangeNotifier {
  /// HMI 控制器：
  /// - 管理串口连接
  /// - 管理命令发送与自动重发
  /// - 处理字节流拆包与响应匹配
  HmiController(this._transport) {
    _subscription = _transport.incomingBytes.listen(_onIncomingBytes);
  }

  final SerialTransport _transport;
  final List<int> _rxBuffer = <int>[];
  final List<HmiLogEntry> _logs = <HmiLogEntry>[];
  final List<_FrameWaiter> _waiters = <_FrameWaiter>[];

  StreamSubscription<Uint8List>? _subscription;
  Future<void> _txChain = Future<void>.value();

  String? _selectedPort;
  int _baudRate = 115200;
  String? _statusMessage;
  HmiRetryPolicy _retryPolicy = const HmiRetryPolicy();

  List<String> ports = <String>[];

  bool get isConnected => _transport.isConnected;
  int get baudRate => _baudRate;
  String? get selectedPort => _selectedPort;
  String? get statusMessage => _statusMessage;
  HmiRetryPolicy get retryPolicy => _retryPolicy;
  List<HmiLogEntry> get logs => List<HmiLogEntry>.unmodifiable(_logs);

  void setPort(String? value) {
    _selectedPort = value;
    notifyListeners();
  }

  void setBaudRate(int value) {
    _baudRate = value;
    notifyListeners();
  }

  void updateRetryPolicy(HmiRetryPolicy policy) {
    _retryPolicy = policy;
    _statusMessage =
        '策略更新: 超时${policy.timeoutMs}ms, 重试${policy.maxRetries}次, 间隔${policy.retryIntervalMs}ms';
    notifyListeners();
  }

  Future<void> refreshPorts() async {
    try {
      ports = await _transport.availablePorts();
      if (ports.isNotEmpty &&
          (selectedPort == null || !ports.contains(selectedPort))) {
        _selectedPort = ports.first;
      }
      _statusMessage = ports.isEmpty ? '未发现串口设备' : '已刷新串口列表';
    } catch (error) {
      _statusMessage = '串口扫描失败: $error';
    }
    notifyListeners();
  }

  Future<void> connectOrDisconnect() async {
    if (_transport.isConnected) {
      await _transport.disconnect();
      _statusMessage = '串口已断开';
      notifyListeners();
      return;
    }

    final port = _selectedPort;
    if (port == null || port.isEmpty) {
      _statusMessage = '请先选择串口';
      notifyListeners();
      return;
    }

    try {
      await _transport.connect(portName: port, baudRate: _baudRate);
      _statusMessage = '已连接: $port @ $_baudRate';
      notifyListeners();
    } catch (error) {
      _statusMessage = '连接失败: $error';
      notifyListeners();
    }
  }

  Future<CommandExecutionResult> runCommand(
    HmiCommandRequest request, {
    HmiRetryPolicy? policy,
  }) async {
    if (!_transport.isConnected) {
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

    await _txChain;
    _txChain = () async {
      for (var attempt = 1; attempt <= totalAttempts; attempt++) {
        final waiter = _createWaiter(request.expectedFunctions);
        try {
          await _transport.write(request.frame.encode());
          _appendLog('TX', request.frame, note: request.note, attempt: attempt);
        } catch (error) {
          _removeWaiter(waiter);
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
          finalResult = CommandExecutionResult(
            success: true,
            message: '${request.label}成功',
            response: response,
            elapsed: elapsed,
            attempts: attempt,
          );
          break;
        } on TimeoutException {
          _removeWaiter(waiter);
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
          _removeWaiter(waiter);
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

  Future<CommandExecutionResult> sendOrder({
    required int orderId,
    required int quantity,
    required int cabinetAddress,
    required int layer,
    required int lane,
  }) {
    return runCommand(
      HmiCommandRequest(
        command: HmiCommandCode.orderSend,
        frame: HmiFrame(
          address: HmiFrame.appRequestAddress,
          function: HmiCommandCode.orderSend.code,
          data: <int>[
            orderId & 0xFF,
            quantity & 0xFF,
            cabinetAddress & 0xFF,
            layer & 0xFF,
            lane & 0xFF,
          ],
        ),
        expectedFunctions:
            kRequestToExpectedResponseFunctions[HmiCommandCode
                .orderSend
                .code] ??
            <int>{0x01},
        note: '订单下发',
      ),
    );
  }

  Future<CommandExecutionResult> sendPackSeal({
    required int orderId,
    int sealAction = 0x01,
  }) {
    return runCommand(
      HmiCommandRequest(
        command: HmiCommandCode.packSeal,
        frame: HmiFrame(
          address: HmiFrame.appRequestAddress,
          function: HmiCommandCode.packSeal.code,
          data: <int>[orderId & 0xFF, sealAction & 0xFF],
        ),
        expectedFunctions:
            kRequestToExpectedResponseFunctions[HmiCommandCode.packSeal.code] ??
            <int>{0x03},
        note: '打包封口',
      ),
    );
  }

  Future<CommandExecutionResult> sendStore({
    required int packageId,
    required int cabinetNo,
  }) {
    return runCommand(
      HmiCommandRequest(
        command: HmiCommandCode.store,
        frame: HmiFrame(
          address: HmiFrame.appRequestAddress,
          function: HmiCommandCode.store.code,
          data: <int>[packageId & 0xFF, cabinetNo & 0xFF],
        ),
        expectedFunctions:
            kRequestToExpectedResponseFunctions[HmiCommandCode.store.code] ??
            <int>{0x05},
        note: '储物格存放',
      ),
    );
  }

  Future<CommandExecutionResult> sendPickupUnlock({
    required int orderId,
    required int cabinetNo,
  }) {
    return runCommand(
      HmiCommandRequest(
        command: HmiCommandCode.pickupUnlock,
        frame: HmiFrame(
          address: HmiFrame.appRequestAddress,
          function: HmiCommandCode.pickupUnlock.code,
          data: <int>[orderId & 0xFF, cabinetNo & 0xFF],
        ),
        expectedFunctions:
            kRequestToExpectedResponseFunctions[HmiCommandCode
                .pickupUnlock
                .code] ??
            <int>{0x07},
        note: '取货开锁',
      ),
    );
  }

  Future<CommandExecutionResult> sendStatusQuery({int queryType = 0x01}) {
    return runCommand(
      HmiCommandRequest(
        command: HmiCommandCode.statusQuery,
        frame: HmiFrame(
          address: HmiFrame.appRequestAddress,
          function: HmiCommandCode.statusQuery.code,
          data: <int>[queryType & 0xFF],
        ),
        expectedFunctions:
            kRequestToExpectedResponseFunctions[HmiCommandCode
                .statusQuery
                .code] ??
            <int>{0x09},
        note: '状态查询',
      ),
    );
  }

  Future<CommandExecutionResult> sendDeviceTest({
    required int testType,
    required int targetId,
    required int action,
  }) {
    return runCommand(
      HmiCommandRequest(
        command: HmiCommandCode.deviceTest,
        frame: HmiFrame(
          address: HmiFrame.appRequestAddress,
          function: HmiCommandCode.deviceTest.code,
          data: <int>[
            testType & 0xFF,
            targetId & 0xFF,
            (targetId >> 8) & 0xFF,
            action & 0xFF,
          ],
        ),
        expectedFunctions:
            kRequestToExpectedResponseFunctions[HmiCommandCode
                .deviceTest
                .code] ??
            <int>{0x0B},
        note: '设备测试',
      ),
    );
  }

  Future<CommandExecutionResult> sendReturnGoods({
    required int orderId,
    required int cabinetNo,
  }) {
    return runCommand(
      HmiCommandRequest(
        command: HmiCommandCode.returnGoods,
        frame: HmiFrame(
          address: HmiFrame.appRequestAddress,
          function: HmiCommandCode.returnGoods.code,
          data: <int>[orderId & 0xFF, cabinetNo & 0xFF],
        ),
        expectedFunctions:
            kRequestToExpectedResponseFunctions[HmiCommandCode
                .returnGoods
                .code] ??
            <int>{0x0C},
        note: '退货',
      ),
    );
  }

  Future<CommandExecutionResult> sendInitQuery() {
    return runCommand(
      HmiCommandRequest(
        command: HmiCommandCode.initQuery,
        frame: HmiFrame(
          address: HmiFrame.appRequestAddress,
          function: HmiCommandCode.initQuery.code,
          data: const <int>[0x01],
        ),
        expectedFunctions:
            kRequestToExpectedResponseFunctions[HmiCommandCode
                .initQuery
                .code] ??
            <int>{0x10},
        note: '初始化查询',
      ),
    );
  }

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

  Future<CommandExecutionResult> sendPackerAvoid({
    required int nodeAddress,
    required int action,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.avoidCtrl,
      nodeAddress: nodeAddress,
      payload: <int>[action & 0xFF, 0x00],
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

  Future<CommandExecutionResult> sendPackerHeartbeat({
    required int nodeAddress,
    int hostState = 0,
  }) {
    return _runPackerCommand(
      HmiPackerFunction.heartbeat,
      nodeAddress: nodeAddress,
      payload: <int>[hostState & 0xFF],
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
  ///
  /// 返回响应的 Z4~Z7 合成 uint32 值; 失败返回 null。
  Future<int?> sendParamRead({
    required int nodeAddress,
    required int paramId,
  }) async {
    final result = await _runPackerCommand(
      HmiPackerFunction.paramRead,
      nodeAddress: nodeAddress,
      payload: <int>[paramId & 0xFF],
    );
    if (!result.success || result.response == null) return null;
    final d = result.response!.data;
    if (d[0] != 0x00) return null; // 结果码非 OK
    return d[3] | (d[4] << 8) | (d[5] << 16) | (d[6] << 24);
  }

  /// 写入单个运行时参数 (仅 RAM, 不自动保存)。
  ///
  /// 返回回读值; 失败返回 null。
  Future<int?> sendParamWrite({
    required int nodeAddress,
    required int paramId,
    required int value,
  }) async {
    final result = await _runPackerCommand(
      HmiPackerFunction.paramWrite,
      nodeAddress: nodeAddress,
      payload: <int>[
        paramId & 0xFF,       // Y1 = 参数ID
        4,                     // Y2 = 数据类型(uint32)
        value & 0xFF,          // Y3 = L0
        (value >> 8) & 0xFF,   // Y4 = L1
        (value >> 16) & 0xFF,  // Y5 = L2
        (value >> 24) & 0xFF,  // Y6 = L3
      ],
    );
    if (!result.success || result.response == null) return null;
    final d = result.response!.data;
    if (d[0] != 0x00) return null;
    return d[2] | (d[3] << 8) | (d[4] << 16) | (d[5] << 24);
  }

  /// 保存当前运行时参数到 EEPROM。
  Future<bool> sendParamSave({required int nodeAddress}) async {
    final result = await _runPackerCommand(
      HmiPackerFunction.paramSave,
      nodeAddress: nodeAddress,
    );
    return result.success &&
        result.response != null &&
        result.response!.data[0] == 0x00;
  }

  /// 加载/恢复运行时参数。
  ///
  /// [action]: 0=从EEPROM加载, 1=恢复默认值。
  Future<bool> sendParamLoad({
    required int nodeAddress,
    required int action,
  }) async {
    final result = await _runPackerCommand(
      HmiPackerFunction.paramLoad,
      nodeAddress: nodeAddress,
      payload: <int>[action & 0xFF],
    );
    return result.success &&
        result.response != null &&
        result.response!.data[0] == 0x00;
  }

  Future<CommandExecutionResult> _runPackerCommand(
    HmiPackerFunction function, {
    required int nodeAddress,
    List<int> payload = const <int>[],
  }) {
    return runCommand(
      HmiCommandRequest(
        command: HmiCommandCode.deviceTest,
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
    );
  }

  Future<CommandExecutionResult> sendCustomFrame({
    required int address,
    required int functionCode,
    required List<int> payload,
    Set<int>? expectedFunctions,
    String? note,
  }) {
    return runCommand(
      HmiCommandRequest(
        command: HmiCommandCode.deviceTest,
        frame: HmiFrame(
          address: address,
          function: functionCode,
          data: payload,
        ),
        expectedFunctions:
            expectedFunctions ??
            kRequestToExpectedResponseFunctions[functionCode] ??
            <int>{functionCode, 0x0A},
        note: note ?? '自定义帧',
      ),
    );
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  void _onIncomingBytes(Uint8List bytes) {
    _rxBuffer.addAll(bytes);
    _consumeFrames();
  }

  void _consumeFrames() {
    // 从缓存中持续提取完整20字节协议帧，容忍粘包与脏数据。
    while (_rxBuffer.length >= HmiFrame.frameLength) {
      final start = _rxBuffer.indexWhere(
        (v) =>
            v == HmiFrame.appRequestAddress ||
            v == HmiFrame.appResponseAddress ||
            v == 0x00 ||
            v == 0x20 ||
            v == 0xFF,
      );
      if (start < 0) {
        _rxBuffer.clear();
        return;
      }
      if (start > 0) {
        _rxBuffer.removeRange(0, start);
      }
      if (_rxBuffer.length < HmiFrame.frameLength) {
        return;
      }
      final packet = _rxBuffer.sublist(0, HmiFrame.frameLength);
      final decodedFrame = HmiFrame.tryDecode(packet);
      if (decodedFrame == null) {
        _rxBuffer.removeAt(0);
        continue;
      }
      _appendLog('RX', decodedFrame);
      _dispatchWaiters(decodedFrame);
      _statusMessage = '收到响应: ${decodeHmiFrame(decodedFrame).summary}';
      _rxBuffer.removeRange(0, HmiFrame.frameLength);
      notifyListeners();
    }
  }

  _FrameWaiter _createWaiter(Set<int> expectedFunctions) {
    final waiter = _FrameWaiter(expectedFunctions);
    _waiters.add(waiter);
    return waiter;
  }

  void _dispatchWaiters(HmiFrame frame) {
    final matched = _waiters
        .where((w) => w.expectedFunctions.contains(frame.function))
        .toList();
    for (final waiter in matched) {
      if (!waiter.completer.isCompleted) {
        waiter.completer.complete(frame);
      }
      _waiters.remove(waiter);
    }
  }

  void _removeWaiter(_FrameWaiter waiter) {
    _waiters.remove(waiter);
  }

  void _appendLog(
    String direction,
    HmiFrame frame, {
    String? note,
    int? attempt,
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
      ),
    );
    if (_logs.length > 800) {
      _logs.removeLast();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _transport.disconnect();
    super.dispose();
  }
}
