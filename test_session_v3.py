#!/usr/bin/env python3
"""HMIS-BAM V3 测试脚本 —— 直接通过串口测试 MCU Session 协议。

V3 格式:
  - TID: 4 bytes LE
  - Fragment payload: 8 bytes
  - Reserved: CRC 前 1 byte 固定 0x00，参与外层 CRC
  - Max payload: 512 bytes
  - Fragment header: TID[4] + FRAG_IDX[1] + FRAG_CNT[1] + FRAG_LEN[1]
  - Control: FRAG_IDX=0xFE(ACK) / 0xFF(NACK), FRAG_CNT=0, FRAG_LEN=3
  - Control payload: [frag_ref, status, next_expected]
  - Short Session: FUNC=0x7E, TYPE+SEQ+CMD+FLAGS+LEN+PAYLOAD(10)
"""

import struct
import time
import sys
import serial

# ── V3 常量 ──
MCU_ADDR = 0xFA
SINGLE_FUNC = 0x7E
BAM_FUNC = 0x7F
SINGLE_PAYLOAD = 10
FRAG_PAYLOAD = 8  # V3: 8 bytes per fragment + 1 reserved byte
FRAME_SIZE = 20

# BAM 控制
ACK = 0xFE
NACK = 0xFF
CTRL_OK = 0x00
CTRL_ACCEPTED = 0x03

# Session 帧
S_REQ = 0x01
S_RESP = 0x02

CMD_HELLO = 0x01
CMD_DEVICE_INFO = 0x02
CMD_GET_GROUP_LIST = 0x10
CMD_GET_PARAM_LIST = 0x11
CMD_GET_STATUS = 0x20

CMD_NAMES = {
    0x01: 'HELLO', 0x02: 'DEVICE_INFO',
    0x10: 'GET_GROUP_LIST', 0x11: 'GET_PARAM_LIST',
    0x20: 'GET_STATUS',
}

_tid_counter = 1


def next_tid():
    global _tid_counter
    tid = _tid_counter
    _tid_counter = (_tid_counter + 1) & 0xFFFFFFFF
    if _tid_counter == 0:
        _tid_counter = 1
    return tid


def crc16_modbus(data: bytes) -> int:
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ 0xA001
            else:
                crc >>= 1
    return crc


def build_20b(addr: int, func: int, data16: bytes) -> bytes:
    assert len(data16) <= 16
    data16 = data16.ljust(16, b'\x00')
    raw = bytes([addr, func]) + data16
    crc = crc16_modbus(raw)
    return raw + struct.pack('<H', crc)


def parse_20b(raw: bytes):
    if len(raw) != FRAME_SIZE:
        return None
    crc_r = struct.unpack('<H', raw[18:20])[0]
    if crc16_modbus(raw[:18]) != crc_r:
        return None
    return raw[0], raw[1], raw[2:18]


def build_session(stype: int, seq: int, cmd: int, payload: bytes = b'',
                  flags: int | None = None) -> bytes:
    """构建 Session 帧，CRC 仅覆盖 SOF 之后的 body 部分。"""
    ver = 0x01
    if flags is None:
        flags = 0x01 if stype == S_REQ else 0x00
    body = bytes([ver, stype,
                  seq & 0xFF, (seq >> 8) & 0xFF,
                  cmd, flags,
                  len(payload) & 0xFF, (len(payload) >> 8) & 0xFF])
    body_with_payload = body + payload
    crc = crc16_modbus(body_with_payload)
    return bytes([0x55, 0xAA]) + body_with_payload + struct.pack('<H', crc)


def parse_session(data: bytes):
    """解析 Session 帧，CRC 仅校验 SOF 之后的部分。"""
    if len(data) < 12:
        return None
    if data[0] != 0x55 or data[1] != 0xAA:
        return None
    stype = data[3]
    seq = data[4] | (data[5] << 8)
    cmd = data[6]
    flags = data[7]
    plen = data[8] | (data[9] << 8)
    if len(data) != 10 + plen + 2:
        return None
    payload = data[10:10 + plen]
    crc_r = struct.unpack('<H', data[10 + plen:12 + plen])[0]
    if crc16_modbus(data[2:10 + plen]) != crc_r:
        return None
    return dict(type=stype, seq=seq, cmd=cmd, flags=flags, payload=payload)


# ═══════════════════ V3 BAM ═══════════════════

def build_single_session_20b(stype: int, seq: int, cmd: int,
                             payload: bytes = b'', flags: int | None = None) -> bytes:
    """构建 FUNC=0x7E Session 单帧。仅承载 Session payload <= 10B 的短帧。"""
    if len(payload) > SINGLE_PAYLOAD:
        raise ValueError(f"single-frame payload too large: {len(payload)}")
    if flags is None:
        flags = 0x01 if stype == S_REQ else 0x00
    data16 = bytes([
        stype & 0xFF,
        seq & 0xFF, (seq >> 8) & 0xFF,
        cmd & 0xFF,
        flags & 0xFF,
        len(payload) & 0xFF,
    ]) + payload
    return build_20b(MCU_ADDR, SINGLE_FUNC, data16)


def parse_single_session_20b(data16: bytes):
    """解析 FUNC=0x7E Session 单帧 data16。"""
    plen = data16[5]
    if plen > SINGLE_PAYLOAD:
        return None
    return dict(
        type=data16[0],
        seq=data16[1] | (data16[2] << 8),
        cmd=data16[3],
        flags=data16[4],
        payload=data16[6:6 + plen],
    )

def bam_encode(payload: bytes, tid: int = None) -> list:
    """将 payload 编码为 V3 BAM 20B 帧列表。"""
    if tid is None:
        tid = next_tid()
    total = len(payload)
    frag_count = (total + FRAG_PAYLOAD - 1) // FRAG_PAYLOAD
    frames = []
    for i in range(frag_count):
        offset = i * FRAG_PAYLOAD
        chunk = payload[offset:offset + FRAG_PAYLOAD]
        # data16: TID[4] + FRAG_IDX[1] + FRAG_CNT[1] + FRAG_LEN[1] + PAYLOAD[8] + RESERVED[1]
        data16 = struct.pack('<I', tid)
        data16 += bytes([i, frag_count, len(chunk)])
        data16 += chunk
        data16 = data16.ljust(16, b'\x00')
        frames.append(build_20b(MCU_ADDR, BAM_FUNC, data16))
    return frames


def bam_parse_fragment(data16: bytes):
    """解析 V3 BAM 片段, 返回 dict 或 None。"""
    tid = struct.unpack('<I', data16[0:4])[0]
    fidx = data16[4]
    fcnt = data16[5]
    flen = data16[6]
    if data16[15] != 0:
        return None
    payload = data16[7:7 + flen] if flen <= FRAG_PAYLOAD else b''
    return dict(tid=tid, fidx=fidx, fcnt=fcnt, flen=flen, payload=payload)


def bam_build_control(tid: int, control: int, frag_ref: int,
                      status: int, next_exp: int = 0xFF) -> bytes:
    """构建 V3 BAM 控制帧 (ACK/NACK)。"""
    data16 = struct.pack('<I', tid)
    data16 += bytes([control, 0, 3])  # FRAG_IDX=ACK/NACK, FRAG_CNT=0, FRAG_LEN=3
    data16 += bytes([frag_ref, status, next_exp])
    data16 = data16.ljust(16, b'\x00')
    return build_20b(MCU_ADDR, BAM_FUNC, data16)


def send_session_and_wait(ser, seq: int, cmd: int, payload: bytes = b'',
                          rx_timeout=3.0, ack_timeout=1.5) -> bytes | None:
    """短 Session 请求优先走 0x7E；payload >10B 时回落 0x7F BAM。"""
    session = build_session(S_REQ, seq, cmd, payload)
    if len(payload) > SINGLE_PAYLOAD:
        return send_bam_stop_and_wait(
            ser, session, rx_timeout=rx_timeout, ack_timeout=ack_timeout)

    ser.reset_input_buffer()
    ser.write(build_single_session_20b(S_REQ, seq, cmd, payload))
    ser.flush()
    return _recv_session_response(ser, timeout=rx_timeout)


def _recv_session_response(ser, timeout: float) -> bytes | None:
    """接收 0x7E 单帧响应或 0x7F BAM 响应，返回逻辑 Session 帧。"""
    deadline = time.time() + timeout
    buf = b''
    rx_tid = None
    rx_frag_count = 0
    rx_fragments = {}
    rx_total_len = 0

    while time.time() < deadline:
        waiting = ser.in_waiting or 0
        if waiting > 0:
            buf += ser.read(waiting)

        while len(buf) >= FRAME_SIZE:
            pkt = buf[:FRAME_SIZE]
            buf = buf[FRAME_SIZE:]
            parsed = parse_20b(pkt)
            if parsed is None:
                continue
            addr, func, data16 = parsed
            if func == SINGLE_FUNC:
                single = parse_single_session_20b(data16)
                if single is None:
                    continue
                return build_session(
                    single['type'], single['seq'], single['cmd'],
                    single['payload'], flags=single['flags'])
            if func != BAM_FUNC:
                continue
            frag = bam_parse_fragment(data16)
            if frag is None:
                continue
            tid = frag['tid']
            fidx = frag['fidx']
            fcnt = frag['fcnt']
            flen = frag['flen']

            if fidx in (ACK, NACK):
                continue

            if rx_tid is None or rx_tid != tid:
                rx_tid = tid
                rx_frag_count = fcnt
                rx_fragments.clear()
                rx_total_len = 0

            if fidx >= fcnt:
                continue
            if fidx not in rx_fragments:
                rx_fragments[fidx] = frag['payload']
                rx_total_len = max(rx_total_len, fidx * FRAG_PAYLOAD + flen)

            status = CTRL_OK if len(rx_fragments) >= fcnt else CTRL_ACCEPTED
            ser.write(bam_build_control(tid, ACK, fidx, status, fidx + 1))
            ser.flush()

            if len(rx_fragments) >= rx_frag_count:
                payload_bam = b''.join(rx_fragments[i] for i in range(rx_frag_count))
                return payload_bam[:rx_total_len]

        time.sleep(0.001)
    return None


# ═══════════════════ BAM 收发 ═══════════════════

def send_bam_stop_and_wait(ser, payload: bytes, tid: int = None,
                           rx_timeout=3.0, ack_timeout=1.5) -> bytes | None:
    """V3 Stop-and-Wait: 发送 BAM 分片, 逐片等待 ACK, 接收重组响应。"""
    if tid is None:
        tid = next_tid()

    frames = bam_encode(payload, tid)
    ser.reset_input_buffer()

    # ── 逐片发送, 等待 ACK ──
    for i, frame in enumerate(frames):
        max_retry = 3
        for attempt in range(max_retry):
            ser.write(frame)
            ser.flush()
            # 等待 ACK
            ack = _wait_for_ack(ser, tid, i, ack_timeout)
            if ack:
                break
            print(f"  [BAM] 片 {i}/{len(frames)} ACK 超时, 重试 {attempt + 1}/{max_retry}")
        else:
            print(f"  [BAM] 片 {i} 发送失败 (无 ACK)")
            return None

    print(f"  [BAM] 请求已发送 (tid=0x{tid:08X}, {len(frames)} 片)")

    # ── 接收 MCU 响应 (新 TID, 可能是多片) ──
    return _recv_bam_response(ser, timeout=rx_timeout)


def _wait_for_ack(ser, expected_tid: int, expected_frag: int, timeout: float) -> bool:
    """等待 MCU 对指定片段的 ACK。"""
    deadline = time.time() + timeout
    buf = b''

    while time.time() < deadline:
        waiting = ser.in_waiting or 0
        if waiting > 0:
            buf += ser.read(waiting)

        while len(buf) >= FRAME_SIZE:
            pkt = buf[:FRAME_SIZE]
            buf = buf[FRAME_SIZE:]
            parsed = parse_20b(pkt)
            if parsed is None:
                continue
            addr, func, data16 = parsed
            if func != BAM_FUNC:
                continue
            frag = bam_parse_fragment(data16)
            if frag is None:
                continue
            fidx = frag['fidx']

            if fidx == ACK or fidx == NACK:
                if frag['tid'] == expected_tid:
                    ctrl_payload = frag['payload']
                    if len(ctrl_payload) >= 3:
                        frag_ref = ctrl_payload[0]
                        status = ctrl_payload[1]
                        if frag_ref == expected_frag:
                            if status in (CTRL_OK, CTRL_ACCEPTED):
                                return True
                            else:
                                print(f"  [BAM] NACK 片{expected_frag}: "
                                      f"status=0x{status:02X}")
                                return False
        time.sleep(0.001)
    return False


def _recv_bam_response(ser, timeout: float) -> bytes | None:
    """接收 MCU 的 BAM 响应 (可能多片), 发送 ACK, 返回重组后的 payload。"""
    deadline = time.time() + timeout
    buf = b''
    rx_tid = None
    rx_frag_count = 0
    rx_fragments = {}
    rx_total_len = 0

    while time.time() < deadline:
        waiting = ser.in_waiting or 0
        if waiting > 0:
            buf += ser.read(waiting)

        while len(buf) >= FRAME_SIZE:
            pkt = buf[:FRAME_SIZE]
            buf = buf[FRAME_SIZE:]
            parsed = parse_20b(pkt)
            if parsed is None:
                continue
            addr, func, data16 = parsed
            if func != BAM_FUNC:
                continue
            frag = bam_parse_fragment(data16)
            if frag is None:
                continue
            tid = frag['tid']
            fidx = frag['fidx']
            fcnt = frag['fcnt']
            flen = frag['flen']

            # ── 控制帧 ──
            if fidx in (ACK, NACK):
                ctrl_payload = frag['payload']
                if len(ctrl_payload) >= 3:
                    frag_ref = ctrl_payload[0]
                    status = ctrl_payload[1]
                    st_name = 'ACK' if fidx == ACK else 'NACK'
                    print(f"  [BAM] RX {st_name} tid=0x{tid:08X} "
                          f"ref={frag_ref} status=0x{status:02X}")
                continue

            # ── 数据帧 ──
            # 新事务
            if rx_tid is None or rx_tid != tid:
                rx_tid = tid
                rx_frag_count = fcnt
                rx_fragments.clear()
                rx_total_len = 0
                print(f"  [BAM] RX 新事务 tid=0x{tid:08X} "
                      f"frags={fcnt}")

            if fidx >= fcnt:
                continue

            if fidx not in rx_fragments:
                rx_fragments[fidx] = frag['payload']
                end = fidx * FRAG_PAYLOAD + flen
                if end > rx_total_len:
                    rx_total_len = end

            # 发送 ACK
            status = CTRL_OK if len(rx_fragments) >= fcnt else CTRL_ACCEPTED
            ack_frame = bam_build_control(tid, ACK, fidx, status, fidx + 1)
            ser.write(ack_frame)
            ser.flush()

            # 检查是否收全
            if len(rx_fragments) >= fcnt:
                payload = b''
                for i in range(fcnt):
                    if i in rx_fragments:
                        payload += rx_fragments[i]
                payload = payload[:rx_total_len]
                print(f"  [BAM] RX 完成: {len(payload)} bytes")
                return payload

        time.sleep(0.001)

    print(f"  [BAM] RX 超时 (已收 {len(rx_fragments)}/{rx_frag_count} 片)")
    return None


# ═══════════════════ 测试用例 ═══════════════════

def test_hello(ser):
    """测试 HELLO (短帧, 1-2 片)。"""
    print("\n── HELLO ──")
    seq = next_tid() & 0xFFFF
    session = build_session(S_REQ, seq, CMD_HELLO)
    print(f"  发送 Session: {session.hex()}")
    resp = send_session_and_wait(ser, seq, CMD_HELLO, rx_timeout=3.0)
    if resp is None:
        print("  ❌ 无响应")
        return False
    print(f"  收到: {resp.hex()}")
    parsed = parse_session(resp)
    if parsed is None:
        print("  ❌ 解析失败")
        return False
    print(f"  ✅ cmd={CMD_NAMES.get(parsed['cmd'], hex(parsed['cmd']))} "
          f"result={parsed['payload'][0] if parsed['payload'] else '?'}")
    return True


def test_device_info(ser):
    """测试 DEVICE_INFO (中等帧, ~31B → 4 片响应)。"""
    print("\n── DEVICE_INFO ──")
    seq = next_tid() & 0xFFFF
    session = build_session(S_REQ, seq, CMD_DEVICE_INFO)
    print(f"  发送 Session: {session.hex()}")
    resp = send_session_and_wait(ser, seq, CMD_DEVICE_INFO, rx_timeout=5.0)
    if resp is None:
        print("  ❌ 无响应 (可能长帧接收问题)")
        return False
    print(f"  收到 {len(resp)} bytes: {resp[:40].hex()}...")
    parsed = parse_session(resp)
    if parsed is None:
        print("  ❌ 解析失败")
        return False
    print(f"  ✅ cmd={CMD_NAMES.get(parsed['cmd'], hex(parsed['cmd']))} "
          f"payload_len={len(parsed['payload'])}")
    return True


def test_group_list(ser):
    """测试 GET_GROUP_LIST (长帧, ~190B → 22 片响应)。"""
    print("\n── GET_GROUP_LIST ──")
    payload = bytes([0x00, 0xFF])  # start=0, max=all
    seq = next_tid() & 0xFFFF
    session = build_session(S_REQ, seq, CMD_GET_GROUP_LIST, payload)
    print(f"  发送 Session: {session.hex()}")
    resp = send_session_and_wait(ser, seq, CMD_GET_GROUP_LIST, payload, rx_timeout=8.0)
    if resp is None:
        print("  ❌ 无响应 (长帧问题!)")
        return False
    print(f"  收到 {len(resp)} bytes")
    parsed = parse_session(resp)
    if parsed is None:
        print("  ❌ 解析失败")
        return False
    p = parsed['payload']
    if len(p) >= 4:
        result, ret_count, total, next_start = p[0], p[1], p[2], p[3]
        print(f"  ✅ result={result} returned={ret_count} total={total} next={next_start}")
    else:
        print(f"  ⚠️  payload 过短: {p.hex()}")
    return True


def test_status(ser):
    """测试 GET_STATUS (短帧)。"""
    print("\n── GET_STATUS ──")
    seq = next_tid() & 0xFFFF
    resp = send_session_and_wait(ser, seq, CMD_GET_STATUS, rx_timeout=3.0)
    if resp is None:
        print("  ❌ 无响应")
        return False
    parsed = parse_session(resp)
    if parsed is None:
        print("  ❌ 解析失败")
        return False
    print(f"  ✅ cmd={CMD_NAMES.get(parsed['cmd'], hex(parsed['cmd']))} "
          f"payload={parsed['payload'].hex()}")
    return True


# ═══════════════════ Main ═══════════════════

def main():
    port = sys.argv[1] if len(sys.argv) > 1 else '/dev/ttyACM0'
    baud = 9600

    print(f"=== HMI Session 0x7E/0x7F 测试 === 端口={port} 波特率={baud}")
    print(f"SINGLE_PAYLOAD={SINGLE_PAYLOAD}B, FRAG_PAYLOAD={FRAG_PAYLOAD}B, MCU_ADDR=0x{MCU_ADDR:02X}")

    ser = serial.Serial(port, baud, timeout=0.05)
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    results = {}

    # 短帧测试
    results['HELLO'] = test_hello(ser)
    if not results['HELLO']:
        print("\n⚠️  HELLO 失败, 检查串口连接和协议版本")
        ser.close()
        return

    results['STATUS'] = test_status(ser)

    # 中帧测试 (关键!)
    results['DEVICE_INFO'] = test_device_info(ser)
    if not results['DEVICE_INFO']:
        print("\n⚠️  DEVICE_INFO 失败 — 这是长帧问题的关键!")
        print("   可能原因: MCU BAM TX 多片发送有问题")

    # 长帧测试
    results['GROUP_LIST'] = test_group_list(ser)
    if not results['GROUP_LIST']:
        print("\n⚠️  GET_GROUP_LIST 失败 — 长帧确实发不出来!")
        print("   固件端 BAM V3 TX 多片路径需要排查")

    ser.close()

    print("\n=== 结果汇总 ===")
    for name, ok in results.items():
        print(f"  {'✅' if ok else '❌'} {name}")


if __name__ == '__main__':
    main()
