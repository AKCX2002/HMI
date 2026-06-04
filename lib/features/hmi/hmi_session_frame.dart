import 'dart:typed_data';

import '../../core/protocol/crc_algorithm.dart';

enum HmiSessionFrameType {
  request(0x01),
  response(0x02),
  event(0x03),
  log(0x04),
  heartbeat(0x05);

  const HmiSessionFrameType(this.value);
  final int value;

  static HmiSessionFrameType? tryParse(int value) {
    for (final type in HmiSessionFrameType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

enum HmiSessionCommand {
  hello(0x01),
  deviceInfo(0x02),
  heartbeat(0x03),
  getGroupList(0x10),
  getParamList(0x11),
  getParamValuesBatch(0x12),
  setParamValuesBatch(0x13),
  saveParams(0x14),
  loadParams(0x15),
  loadDefaults(0x16),
  getDeviceStatus(0x20),
  getAlarmStatus(0x21),
  subscribeStreams(0x22),
  unsubscribeStreams(0x23),
  controlRunState(0x30),
  triggerBag(0x31),
  triggerSeal(0x32),
  triggerDeliver(0x33),
  clearFlag(0x34),
  resetFault(0x35),
  stepperJog(0x36),
  dcMotorJog(0x37),
  eventPush(0x40),
  logPush(0x41),
  stackSnapshotPush(0x42);

  const HmiSessionCommand(this.value);
  final int value;

  static HmiSessionCommand? tryParse(int value) {
    for (final command in HmiSessionCommand.values) {
      if (command.value == value) return command;
    }
    return null;
  }
}

class HmiSessionFlags {
  static const int ackRequired = 0x01;
  static const int more = 0x02;
  static const int error = 0x04;
  static const int snapshot = 0x08;
}

class HmiSessionFrame {
  HmiSessionFrame({
    required this.type,
    required this.sequence,
    required this.command,
    this.flags = 0,
    Uint8List? payload,
  }) : payload = payload ?? Uint8List(0);

  static const int sof0 = 0x55;
  static const int sof1 = 0xAA;
  static const int protocolVersion = 0x01;
  static const int headerLength = 10;
  static const int crcLength = 2;
  static const int maxPayloadLength = 1024;

  final HmiSessionFrameType type;
  final int sequence;
  final HmiSessionCommand command;
  final int flags;
  final Uint8List payload;

  Uint8List encode() {
    final len = payload.length;
    final out = Uint8List(headerLength + len + crcLength);
    out[0] = sof0;
    out[1] = sof1;
    out[2] = protocolVersion;
    out[3] = type.value;
    out[4] = sequence & 0xFF;
    out[5] = (sequence >> 8) & 0xFF;
    out[6] = command.value;
    out[7] = flags & 0xFF;
    out[8] = len & 0xFF;
    out[9] = (len >> 8) & 0xFF;
    out.setRange(headerLength, headerLength + len, payload);
    final crc = CrcAlgorithm.modbus.compute(out.sublist(2, headerLength + len));
    out[headerLength + len] = crc & 0xFF;
    out[headerLength + len + 1] = (crc >> 8) & 0xFF;
    return out;
  }

  static HmiSessionFrame? tryDecode(List<int> bytes) {
    if (bytes.length < headerLength + crcLength) return null;
    if (bytes[0] != sof0 || bytes[1] != sof1) return null;
    if (bytes[2] != protocolVersion) return null;

    final payloadLen = bytes[8] | (bytes[9] << 8);
    if (payloadLen > maxPayloadLength) return null;
    final frameLen = headerLength + payloadLen + crcLength;
    if (bytes.length != frameLen) return null;

    final receivedCrc = bytes[frameLen - 2] | (bytes[frameLen - 1] << 8);
    final calcCrc = CrcAlgorithm.modbus.compute(bytes.sublist(2, frameLen - 2));
    if (receivedCrc != calcCrc) return null;

    final type = HmiSessionFrameType.tryParse(bytes[3]);
    final command = HmiSessionCommand.tryParse(bytes[6]);
    if (type == null || command == null) return null;

    return HmiSessionFrame(
      type: type,
      sequence: bytes[4] | (bytes[5] << 8),
      command: command,
      flags: bytes[7],
      payload: Uint8List.fromList(
        bytes.sublist(headerLength, headerLength + payloadLen),
      ),
    );
  }

  String get rawHex => encode()
      .map((e) => e.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
}

class HmiSessionFrameDecoder {
  final List<int> _buffer = <int>[];

  void reset() {
    _buffer.clear();
  }

  List<HmiSessionFrame> pushBytes(Iterable<int> bytes) {
    final frames = <HmiSessionFrame>[];
    for (final byte in bytes) {
      final frame = push(byte);
      if (frame != null) {
        frames.add(frame);
      }
      while (true) {
        final pending = _tryExtractFrame();
        if (pending == null) {
          break;
        }
        frames.add(pending);
      }
    }
    return frames;
  }

  HmiSessionFrame? push(int byte) {
    _buffer.add(byte & 0xFF);
    return _tryExtractFrame();
  }

  HmiSessionFrame? _tryExtractFrame() {
    if (_buffer.length > 4096) {
      _buffer.removeRange(0, _buffer.length - 4096);
    }

    while (_buffer.length >= 2) {
      final start = _buffer.indexWhere((v) => v == HmiSessionFrame.sof0);
      if (start < 0) {
        _buffer.clear();
        return null;
      }
      if (start > 0) {
        _buffer.removeRange(0, start);
      }
      if (_buffer.length < HmiSessionFrame.headerLength) return null;
      if (_buffer[1] != HmiSessionFrame.sof1) {
        _buffer.removeAt(0);
        continue;
      }
      if (_buffer[2] != HmiSessionFrame.protocolVersion) {
        _buffer.removeAt(0);
        continue;
      }
      final payloadLen = _buffer[8] | (_buffer[9] << 8);
      final frameLen =
          HmiSessionFrame.headerLength + payloadLen + HmiSessionFrame.crcLength;
      if (payloadLen > HmiSessionFrame.maxPayloadLength) {
        _buffer.removeAt(0);
        continue;
      }
      if (_buffer.length < frameLen) return null;
      final candidate = List<int>.from(_buffer.sublist(0, frameLen));
      _buffer.removeRange(0, frameLen);
      final frame = HmiSessionFrame.tryDecode(candidate);
      if (frame != null) return frame;
    }
    return null;
  }
}
