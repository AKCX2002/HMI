import 'dart:typed_data';

import '../../core/protocol/crc_algorithm.dart';
import '../../core/protocol/hmi_frame.dart';

const int hmisBamFunction = 0x7F;
const int hmisBamTidSize = 4;
const int hmisBamFragmentPayloadSize = 8;
const int hmisBamMaxPayloadSize = 512;
const int hmisBamMaxFragmentCount = 64;
const int hmisBamFragIndexAck = 0xFE;
const int hmisBamFragIndexNack = 0xFF;

const int _tidOffset = 0;
const int _fragIndexOffset = 4;
const int _fragCountOffset = 5;
const int _fragLengthOffset = 6;
const int _payloadOffset = 7;
const int _reservedOffset = 15;
const int _controlPayloadLength = 3;

enum HmisBamControlStatus {
  ok(0x00),
  accepted(0x03),
  crcError(0x06),
  timeout(0x07),
  busy(0x08),
  queueFull(0x09),
  routeFail(0x0A),
  badFragment(0x0B),
  internalError(0x0C),
  tidConflict(0x0D),
  outOfOrder(0x0E);

  const HmisBamControlStatus(this.value);
  final int value;

  static HmisBamControlStatus? tryParse(int value) {
    for (final item in values) {
      if (item.value == value) {
        return item;
      }
    }
    return null;
  }
}

class HmisBamCompletedFrame {
  const HmisBamCompletedFrame({
    required this.address,
    required this.transactionId,
    required this.payload,
  });

  final int address;
  final int transactionId;
  final Uint8List payload;
}

class HmisBamDecodeResult {
  const HmisBamDecodeResult({
    this.frame,
    this.completed,
    this.controlToSend,
    this.receivedControl,
    this.consumed = false,
  });

  final HmiFrame? frame;
  final HmisBamCompletedFrame? completed;
  final HmiFrame? controlToSend;
  final HmisBamReceivedControl? receivedControl;
  final bool consumed;
}

class HmisBamReceivedControl {
  const HmisBamReceivedControl({
    required this.address,
    required this.transactionId,
    required this.controlIndex,
    required this.fragmentIndex,
    required this.status,
    required this.nextExpectedIndex,
  });

  final int address;
  final int transactionId;
  final int controlIndex;
  final int fragmentIndex;
  final HmisBamControlStatus status;
  final int nextExpectedIndex;

  bool get isAck => controlIndex == hmisBamFragIndexAck;
  bool get isNack => controlIndex == hmisBamFragIndexNack;
}

class HmisBamFrameBuilder {
  HmisBamFrameBuilder({this.crcAlgorithm = CrcAlgorithm.modbus});

  final CrcAlgorithm crcAlgorithm;
  int _nextTransactionId = 1;

  int allocateTransactionId() {
    final tid = _nextTransactionId;
    _nextTransactionId = (_nextTransactionId + 1) & 0xFFFFFFFF;
    if (_nextTransactionId == 0) {
      _nextTransactionId = 1;
    }
    return tid;
  }

  List<HmiFrame> encodePayload({
    required int address,
    required List<int> payload,
    int? transactionId,
  }) {
    if (payload.isEmpty || payload.length > hmisBamMaxPayloadSize) {
      return const <HmiFrame>[];
    }

    final tid = transactionId ?? allocateTransactionId();
    if (tid == 0) {
      return const <HmiFrame>[];
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
      writeTransactionId(data, tid);
      data[_fragIndexOffset] = index;
      data[_fragCountOffset] = fragmentCount;
      data[_fragLengthOffset] = fragmentLength;
      data[_reservedOffset] = 0;
      data.setRange(
        _payloadOffset,
        _payloadOffset + fragmentLength,
        payload,
        offset,
      );
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
    required int transactionId,
    required int controlIndex,
    required int fragmentIndex,
    required HmisBamControlStatus status,
    int nextExpectedIndex = 0xFF,
  }) {
    final data = List<int>.filled(16, 0);
    writeTransactionId(data, transactionId);
    data[_fragIndexOffset] = controlIndex & 0xFF;
    data[_fragCountOffset] = 0;
    data[_fragLengthOffset] = _controlPayloadLength;
    data[_payloadOffset] = fragmentIndex & 0xFF;
    data[_payloadOffset + 1] = status.value;
    data[_payloadOffset + 2] = nextExpectedIndex & 0xFF;
    data[_reservedOffset] = 0;
    return HmiFrame(
      address: address & 0xFF,
      function: hmisBamFunction,
      data: data,
      crcAlgorithm: crcAlgorithm,
    );
  }

  static int readTransactionId(List<int> data) {
    return (data[_tidOffset] & 0xFF) |
        ((data[_tidOffset + 1] & 0xFF) << 8) |
        ((data[_tidOffset + 2] & 0xFF) << 16) |
        ((data[_tidOffset + 3] & 0xFF) << 24);
  }

  static void writeTransactionId(List<int> data, int transactionId) {
    data[_tidOffset] = transactionId & 0xFF;
    data[_tidOffset + 1] = (transactionId >> 8) & 0xFF;
    data[_tidOffset + 2] = (transactionId >> 16) & 0xFF;
    data[_tidOffset + 3] = (transactionId >> 24) & 0xFF;
  }

  static int fragmentIndexOf(HmiFrame frame) {
    return frame.data[_fragIndexOffset];
  }

  static int fragmentCountOf(HmiFrame frame) {
    return frame.data[_fragCountOffset];
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
  int _transactionId = 0;
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
  HmisBamDecodeResult? checkTimeout({DateTime? now}) {
    if (!_active) {
      return null;
    }
    final effectiveNow = now ?? DateTime.now();
    if (effectiveNow.difference(_activeStartTime) < rxTimeout) {
      return null;
    }
    final timedOutTransactionId = _transactionId;
    final timedOutAddress = _address;
    _resetTransaction();
    return HmisBamDecodeResult(
      consumed: true,
      controlToSend: HmisBamFrameBuilder(crcAlgorithm: crcAlgorithm)
          .buildControl(
            address: timedOutAddress,
            transactionId: timedOutTransactionId,
            controlIndex: hmisBamFragIndexNack,
            fragmentIndex: 0xFF,
            status: HmisBamControlStatus.timeout,
            nextExpectedIndex: 0xFF,
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

    final transactionId = HmisBamFrameBuilder.readTransactionId(frame.data);
    final fragmentIndex = frame.data[_fragIndexOffset];
    final fragmentCount = frame.data[_fragCountOffset];
    final fragmentLength = frame.data[_fragLengthOffset];

    final isControlFrame =
        fragmentIndex == hmisBamFragIndexAck ||
        fragmentIndex == hmisBamFragIndexNack;
    if (frame.data[_reservedOffset] != 0) {
      if (isControlFrame) {
        return HmisBamDecodeResult(frame: frame, consumed: true);
      }
      return HmisBamDecodeResult(
        frame: frame,
        consumed: true,
        controlToSend: _control(
          frame,
          transactionId,
          hmisBamFragIndexNack,
          fragmentIndex,
          HmisBamControlStatus.badFragment,
          _nextExpectedIndex,
        ),
      );
    }

    if (isControlFrame) {
      final control = _parseControl(frame, transactionId, fragmentIndex);
      if (control == null) {
        return const HmisBamDecodeResult(consumed: true);
      }
      return HmisBamDecodeResult(
        frame: frame,
        consumed: true,
        receivedControl: control,
      );
    }

    if (transactionId == 0 ||
        !_isFragmentHeaderValid(fragmentIndex, fragmentCount, fragmentLength)) {
      return HmisBamDecodeResult(
        frame: frame,
        consumed: true,
        controlToSend: _control(
          frame,
          transactionId,
          hmisBamFragIndexNack,
          fragmentIndex,
          HmisBamControlStatus.badFragment,
          0,
        ),
      );
    }

    final offset = fragmentIndex * hmisBamFragmentPayloadSize;
    final end = offset + fragmentLength;
    if (end > hmisBamMaxPayloadSize ||
        fragmentCount * hmisBamFragmentPayloadSize >
            hmisBamMaxPayloadSize + hmisBamFragmentPayloadSize - 1) {
      return HmisBamDecodeResult(
        frame: frame,
        consumed: true,
        controlToSend: _control(
          frame,
          transactionId,
          hmisBamFragIndexNack,
          fragmentIndex,
          HmisBamControlStatus.queueFull,
          0,
        ),
      );
    }

    if (!_active && fragmentIndex != 0) {
      return HmisBamDecodeResult(
        frame: frame,
        consumed: true,
        controlToSend: _control(
          frame,
          transactionId,
          hmisBamFragIndexNack,
          fragmentIndex,
          HmisBamControlStatus.outOfOrder,
          0,
        ),
      );
    }

    if (!_active) {
      _active = true;
      _activeStartTime = DateTime.now();
      _transactionId = transactionId;
      _fragmentCount = fragmentCount;
      _address = frame.address;
      _totalLength = 0;
      _nextExpectedIndex = 0;
      _receivedFragments.clear();
    } else if (_transactionId != transactionId || _address != frame.address) {
      return HmisBamDecodeResult(
        frame: frame,
        consumed: true,
        controlToSend: _control(
          frame,
          transactionId,
          hmisBamFragIndexNack,
          fragmentIndex,
          HmisBamControlStatus.busy,
          _nextExpectedIndex,
        ),
      );
    } else if (_fragmentCount != fragmentCount) {
      return HmisBamDecodeResult(
        frame: frame,
        consumed: true,
        controlToSend: _control(
          frame,
          transactionId,
          hmisBamFragIndexNack,
          fragmentIndex,
          HmisBamControlStatus.tidConflict,
          _nextExpectedIndex,
        ),
      );
    }

    if (fragmentIndex < _nextExpectedIndex) {
      return HmisBamDecodeResult(
        frame: frame,
        consumed: true,
        controlToSend: _control(
          frame,
          transactionId,
          hmisBamFragIndexAck,
          fragmentIndex,
          HmisBamControlStatus.accepted,
          _nextExpectedIndex,
        ),
      );
    }

    if (fragmentIndex != _nextExpectedIndex) {
      return HmisBamDecodeResult(
        frame: frame,
        consumed: true,
        controlToSend: _control(
          frame,
          transactionId,
          hmisBamFragIndexNack,
          fragmentIndex,
          HmisBamControlStatus.outOfOrder,
          _nextExpectedIndex,
        ),
      );
    }

    if (!_receivedFragments.contains(fragmentIndex)) {
      _payload.setRange(offset, end, frame.data, _payloadOffset);
      _receivedFragments.add(fragmentIndex);
      _nextExpectedIndex = fragmentIndex + 1;
      if (fragmentIndex == fragmentCount - 1) {
        _totalLength = end;
      }
    }

    if (_receivedFragments.length == _fragmentCount && _totalLength > 0) {
      final completed = HmisBamCompletedFrame(
        address: frame.address,
        transactionId: transactionId,
        payload: Uint8List.fromList(_payload.sublist(0, _totalLength)),
      );
      _resetTransaction();
      return HmisBamDecodeResult(
        frame: frame,
        consumed: true,
        completed: completed,
        controlToSend: _control(
          frame,
          transactionId,
          hmisBamFragIndexAck,
          fragmentIndex,
          HmisBamControlStatus.ok,
          _nextExpectedIndex,
        ),
      );
    }

    return HmisBamDecodeResult(
      frame: frame,
      consumed: true,
      controlToSend: _control(
        frame,
        transactionId,
        hmisBamFragIndexAck,
        fragmentIndex,
        HmisBamControlStatus.accepted,
        _nextExpectedIndex,
      ),
    );
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
    int transactionId,
    int controlIndex,
    int fragmentIndex,
    HmisBamControlStatus status,
    int nextExpectedIndex,
  ) {
    return HmisBamFrameBuilder(crcAlgorithm: crcAlgorithm).buildControl(
      address: frame.address,
      transactionId: transactionId,
      controlIndex: controlIndex,
      fragmentIndex: fragmentIndex,
      status: status,
      nextExpectedIndex: nextExpectedIndex,
    );
  }

  HmisBamReceivedControl? _parseControl(
    HmiFrame frame,
    int transactionId,
    int controlIndex,
  ) {
    if (frame.data[_fragLengthOffset] < _controlPayloadLength) {
      return null;
    }
    final status = HmisBamControlStatus.tryParse(
      frame.data[_payloadOffset + 1],
    );
    if (status == null) {
      return null;
    }
    return HmisBamReceivedControl(
      address: frame.address,
      transactionId: transactionId,
      controlIndex: controlIndex,
      fragmentIndex: frame.data[_payloadOffset],
      status: status,
      nextExpectedIndex: frame.data[_payloadOffset + 2],
    );
  }

  void _resetTransaction() {
    _active = false;
    _transactionId = 0;
    _fragmentCount = 0;
    _totalLength = 0;
    _address = 0;
    _nextExpectedIndex = 0;
    _receivedFragments.clear();
  }

  int _nextExpectedIndex = 0;
}
