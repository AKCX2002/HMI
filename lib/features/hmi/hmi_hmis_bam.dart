import 'dart:typed_data';

import '../../core/protocol/crc_algorithm.dart';
import '../../core/protocol/hmi_frame.dart';

const int hmisBamFunction = 0x7F;
const int hmisBamFragmentPayloadSize = 12;
const int hmisBamMaxPayloadSize = 512;
const int hmisBamMaxFragmentCount = 43;
const int hmisBamFragIndexAck = 0xFE;
const int hmisBamFragIndexNack = 0xFF;

enum HmisBamControlStatus {
  ok(0x00),
  busy(0x01),
  oversize(0x02),
  format(0x03),
  timeout(0x04);

  const HmisBamControlStatus(this.value);
  final int value;
}

class HmisBamCompletedFrame {
  const HmisBamCompletedFrame({
    required this.address,
    required this.sessionId,
    required this.payload,
  });

  final int address;
  final int sessionId;
  final Uint8List payload;
}

class HmisBamDecodeResult {
  const HmisBamDecodeResult({
    this.completed,
    this.controlToSend,
    this.consumed = false,
  });

  final HmisBamCompletedFrame? completed;
  final HmiFrame? controlToSend;
  final bool consumed;
}

class HmisBamFrameBuilder {
  HmisBamFrameBuilder({this.crcAlgorithm = CrcAlgorithm.modbus});

  final CrcAlgorithm crcAlgorithm;
  int _nextSessionId = 1;

  List<HmiFrame> encodePayload({
    required int address,
    required List<int> payload,
  }) {
    if (payload.isEmpty || payload.length > hmisBamMaxPayloadSize) {
      return const <HmiFrame>[];
    }

    final sessionId = _nextSessionId;
    _nextSessionId = (_nextSessionId + 1) & 0xFF;
    if (_nextSessionId == 0) {
      _nextSessionId = 1;
    }

    final fragmentCount =
        (payload.length + hmisBamFragmentPayloadSize - 1) ~/
        hmisBamFragmentPayloadSize;
    if (fragmentCount <= 0 || fragmentCount > hmisBamMaxFragmentCount) {
      return const <HmiFrame>[];
    }

    final frames = <HmiFrame>[];
    for (var index = 0; index < fragmentCount; index++) {
      final offset = index * hmisBamFragmentPayloadSize;
      final remaining = payload.length - offset;
      final fragmentLength = remaining > hmisBamFragmentPayloadSize
          ? hmisBamFragmentPayloadSize
          : remaining;
      final data = List<int>.filled(16, 0);
      data[0] = sessionId;
      data[1] = index;
      data[2] = fragmentCount;
      data[3] = fragmentLength;
      data.setRange(4, 4 + fragmentLength, payload, offset);
      frames.add(
        HmiFrame(
          address: address & 0xFF,
          function: hmisBamFunction,
          data: data,
          crcAlgorithm: crcAlgorithm,
        ),
      );
    }
    return frames;
  }

  HmiFrame buildControl({
    required int address,
    required int sessionId,
    required int controlIndex,
    required HmisBamControlStatus status,
    int detail = 0xFF,
  }) {
    return HmiFrame(
      address: address & 0xFF,
      function: hmisBamFunction,
      data: <int>[
        sessionId & 0xFF,
        controlIndex & 0xFF,
        0,
        status.value,
        detail & 0xFF,
      ],
      crcAlgorithm: crcAlgorithm,
    );
  }
}

class HmisBamDecoder {
  HmisBamDecoder({
    this.crcAlgorithm = CrcAlgorithm.modbus,
    this.rxTimeout = const Duration(milliseconds: 3000),
  });

  final CrcAlgorithm crcAlgorithm;

  /// 接收超时：若活动事务在超过 [rxTimeout] 时长内未收全所有分片，
  /// 解码器将自动重置并丢弃当前事务，为下一个 BAM 事务腾出空间。
  final Duration rxTimeout;

  final List<int> _rxBuffer = <int>[];
  final List<int> _payload = List<int>.filled(hmisBamMaxPayloadSize, 0);
  final Set<int> _receivedFragments = <int>{};
  bool _active = false;
  int _sessionId = 0;
  int _fragmentCount = 0;
  int _totalLength = 0;
  int _address = 0;
  DateTime _activeStartTime = DateTime.now();

  /// 是否正在接收 BAM 分片事务。
  bool get isActive => _active;

  void reset() {
    _rxBuffer.clear();
    _resetTransaction();
  }

  /// 检查当前活动事务是否超时。
  ///
  /// 应在每次收到数据时调用，或由上一层周期性调用。
  /// 若超时则自动重置事务并返回带有超时信息的解码结果。
  ///
  /// [now] 可选，默认为当前时刻。
  HmisBamDecodeResult? checkTimeout({DateTime? now}) {
    if (!_active) {
      return null;
    }
    final effectiveNow = now ?? DateTime.now();
    if (effectiveNow.difference(_activeStartTime) < rxTimeout) {
      return null;
    }
    final timedOutSessionId = _sessionId;
    final timedOutAddress = _address;
    _resetTransaction();
    return HmisBamDecodeResult(
      consumed: true,
      controlToSend: HmisBamFrameBuilder(crcAlgorithm: crcAlgorithm)
          .buildControl(
        address: timedOutAddress,
        sessionId: timedOutSessionId,
        controlIndex: hmisBamFragIndexNack,
        status: HmisBamControlStatus.timeout,
        detail: 0xFF,
      ),
    );
  }

  List<HmisBamDecodeResult> pushBytes(Iterable<int> bytes) {
    _rxBuffer.addAll(bytes.map((byte) => byte & 0xFF));
    if (_rxBuffer.length > 4096) {
      _rxBuffer.removeRange(0, _rxBuffer.length - 4096);
    }

    final results = <HmisBamDecodeResult>[];
    while (_rxBuffer.length >= HmiFrame.frameLength) {
      final packet = _rxBuffer.sublist(0, HmiFrame.frameLength);
      final frame = HmiFrame.tryDecode(packet, crcAlgorithm: crcAlgorithm);
      if (frame == null) {
        _rxBuffer.removeAt(0);
        continue;
      }
      _rxBuffer.removeRange(0, HmiFrame.frameLength);
      if (frame.function != hmisBamFunction) {
        continue;
      }
      results.add(acceptFrame(frame));
    }
    return results;
  }

  HmisBamDecodeResult acceptFrame(HmiFrame frame) {
    if (frame.function != hmisBamFunction) {
      return const HmisBamDecodeResult();
    }

    final sessionId = frame.data[0];
    final fragmentIndex = frame.data[1];
    final fragmentCount = frame.data[2];
    final fragmentLength = frame.data[3];

    if (fragmentIndex == hmisBamFragIndexAck ||
        fragmentIndex == hmisBamFragIndexNack) {
      // ACK/NACK 控制帧：若 session_id 与当前活动事务匹配，则清理事务。
      // 否则仅标记 consumed（可能是设备对旧事务的延迟响应）。
      if (_active && sessionId == _sessionId) {
        _resetTransaction();
      }
      return const HmisBamDecodeResult(consumed: true);
    }

    if (!_isFragmentHeaderValid(fragmentIndex, fragmentCount, fragmentLength)) {
      return HmisBamDecodeResult(
        consumed: true,
        controlToSend: _control(
          frame,
          sessionId,
          hmisBamFragIndexNack,
          HmisBamControlStatus.format,
          fragmentIndex,
        ),
      );
    }

    final offset = fragmentIndex * hmisBamFragmentPayloadSize;
    final end = offset + fragmentLength;
    if (end > hmisBamMaxPayloadSize ||
        fragmentCount * hmisBamFragmentPayloadSize >
            hmisBamMaxPayloadSize + hmisBamFragmentPayloadSize - 1) {
      return HmisBamDecodeResult(
        consumed: true,
        controlToSend: _control(
          frame,
          sessionId,
          hmisBamFragIndexNack,
          HmisBamControlStatus.oversize,
          fragmentIndex,
        ),
      );
    }

    if (_active &&
        (_sessionId != sessionId ||
            _fragmentCount != fragmentCount ||
            _address != frame.address)) {
      return HmisBamDecodeResult(
        consumed: true,
        controlToSend: _control(
          frame,
          sessionId,
          hmisBamFragIndexNack,
          HmisBamControlStatus.busy,
          fragmentIndex,
        ),
      );
    }

    if (!_active) {
      _active = true;
      _activeStartTime = DateTime.now();
      _sessionId = sessionId;
      _fragmentCount = fragmentCount;
      _address = frame.address;
      _totalLength = 0;
      _receivedFragments.clear();
    }

    if (!_receivedFragments.contains(fragmentIndex)) {
      _payload.setRange(offset, end, frame.data, 4);
      _receivedFragments.add(fragmentIndex);
      if (fragmentIndex == fragmentCount - 1) {
        _totalLength = end;
      }
    }

    if (_receivedFragments.length == _fragmentCount && _totalLength > 0) {
      final completed = HmisBamCompletedFrame(
        address: frame.address,
        sessionId: sessionId,
        payload: Uint8List.fromList(_payload.sublist(0, _totalLength)),
      );
      _resetTransaction();
      return HmisBamDecodeResult(
        consumed: true,
        completed: completed,
        controlToSend: _control(
          frame,
          sessionId,
          hmisBamFragIndexAck,
          HmisBamControlStatus.ok,
          0xFF,
        ),
      );
    }

    return const HmisBamDecodeResult(consumed: true);
  }

  bool _isFragmentHeaderValid(
    int fragmentIndex,
    int fragmentCount,
    int fragmentLength,
  ) {
    if (fragmentCount <= 0 ||
        fragmentCount > hmisBamMaxFragmentCount ||
        fragmentIndex >= fragmentCount ||
        fragmentLength <= 0 ||
        fragmentLength > hmisBamFragmentPayloadSize) {
      return false;
    }
    if (fragmentIndex < fragmentCount - 1) {
      return fragmentLength == hmisBamFragmentPayloadSize;
    }
    return true;
  }

  HmiFrame _control(
    HmiFrame frame,
    int sessionId,
    int controlIndex,
    HmisBamControlStatus status,
    int detail,
  ) {
    return HmisBamFrameBuilder(crcAlgorithm: crcAlgorithm).buildControl(
      address: frame.address,
      sessionId: sessionId,
      controlIndex: controlIndex,
      status: status,
      detail: detail,
    );
  }

  void _resetTransaction() {
    _active = false;
    _sessionId = 0;
    _fragmentCount = 0;
    _totalLength = 0;
    _address = 0;
    _receivedFragments.clear();
  }
}
