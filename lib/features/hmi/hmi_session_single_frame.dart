import 'dart:typed_data';

import '../../core/protocol/crc_algorithm.dart';
import '../../core/protocol/hmi_frame.dart';
import 'hmi_session_frame.dart';

const int hmiSessionSingleFrameFunction = 0x7E;
const int hmiSessionSingleFramePayloadSize = 10;

class HmiSessionSingleFrameCodec {
  const HmiSessionSingleFrameCodec({this.crcAlgorithm = CrcAlgorithm.modbus});

  final CrcAlgorithm crcAlgorithm;

  bool canEncode(HmiSessionFrame frame) {
    return frame.payload.length <= hmiSessionSingleFramePayloadSize;
  }

  HmiFrame encode({required int address, required HmiSessionFrame frame}) {
    if (!canEncode(frame)) {
      throw ArgumentError.value(
        frame.payload.length,
        'frame.payload.length',
        'must be <= $hmiSessionSingleFramePayloadSize',
      );
    }

    final data = List<int>.filled(16, 0);
    data[0] = frame.type.value;
    data[1] = frame.sequence & 0xFF;
    data[2] = (frame.sequence >> 8) & 0xFF;
    data[3] = frame.command.value;
    data[4] = frame.flags & 0xFF;
    data[5] = frame.payload.length & 0xFF;
    data.setRange(6, 6 + frame.payload.length, frame.payload);

    return HmiFrame(
      address: address & 0xFF,
      function: hmiSessionSingleFrameFunction,
      data: data,
      crcAlgorithm: crcAlgorithm,
    );
  }

  HmiSessionFrame? decode(HmiFrame frame) {
    if (frame.function != hmiSessionSingleFrameFunction) {
      return null;
    }

    final length = frame.data[5];
    if (length > hmiSessionSingleFramePayloadSize) {
      return null;
    }
    final type = HmiSessionFrameType.tryParse(frame.data[0]);
    final command = HmiSessionCommand.tryParse(frame.data[3]);
    if (type == null || command == null) {
      return null;
    }

    return HmiSessionFrame(
      type: type,
      sequence: frame.data[1] | (frame.data[2] << 8),
      command: command,
      flags: frame.data[4],
      payload: Uint8List.fromList(frame.data.sublist(6, 6 + length)),
    );
  }
}
