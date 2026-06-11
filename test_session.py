#!/usr/bin/env python3
"""旧版 Session-ID BAM 测试脚本，已废弃。

当前固件/HMI 使用 `test_session_v3.py`：
- `FUNC=0x7E` 承载 payload <= 10B 的 Session 单帧
- `FUNC=0x7F` 承载 V3 TID BAM，单片 payload 8B + reserved(0x00)

保留本文件仅用于追溯旧联调记录，不应用于当前设备测试。
"""

import struct
import time
import sys
import serial

# ── 常量 ──
MCU_ADDR = 0xFA
BAM_FUNC = 0x7F
FRAG_PAYLOAD = 8
FRAME_SIZE = 20  # 20B 固定帧

# Session 帧类型
S_REQ = 0x01
S_RESP = 0x02

# Session 命令
CMD_HELLO = 0x01
CMD_DEVICE_INFO = 0x02
CMD_GET_GROUP_LIST = 0x10
CMD_GET_PARAM_LIST = 0x11
CMD_GET_PARAM_VALUES = 0x12
CMD_GET_STATUS = 0x20

CMD_NAMES = {
    0x01: 'hello', 0x02: 'deviceInfo', 0x03: 'heartbeat',
    0x10: 'getGroupList', 0x11: 'getParamList',
    0x12: 'getParamValues', 0x13: 'setParamValues',
    0x14: 'saveParams', 0x15: 'loadParams', 0x16: 'loadDefaults',
    0x20: 'getDeviceStatus', 0x21: 'getAlarmStatus',
    0x22: 'subscribe', 0x23: 'unsubscribe',
    0x30: 'controlRunState', 0x31: 'triggerBag',
    0x32: 'triggerSeal', 0x33: 'triggerDeliver',
    0x34: 'clearFlag', 0x35: 'resetFault',
}


def crc16_modbus(data: bytes) -> int:
    """CRC16-Modbus, 低字节在前。"""
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ 0xA001
            else:
                crc >>= 1
    return crc


def build_20b_frame(addr: int, func: int, data16: bytes) -> bytes:
    """构建 20 字节固定帧: [addr][func][16B data][CRC16_lo][CRC16_hi]"""
    assert len(data16) <= 16
    data16 = data16.ljust(16, b'\x00')
    raw = bytes([addr, func]) + data16
    crc = crc16_modbus(raw)
    return raw + struct.pack('<H', crc)


def parse_20b_frame(raw: bytes):
    """解析 20B 帧, 返回 (addr, func, data16) 或 None。"""
    if len(raw) != FRAME_SIZE:
        return None
    crc_recv = struct.unpack('<H', raw[18:20])[0]
    crc_calc = crc16_modbus(raw[:18])
    if crc_recv != crc_calc:
        return None
    return raw[0], raw[1], raw[2:18]


def build_session_frame(stype: int, seq: int, cmd: int, payload: bytes = b'') -> bytes:
    """构建 Session 帧 (55 AA ...)"""
    ver = 0x01
    flags = 0x01 if stype == S_REQ else 0x00
    header = bytes([0x55, 0xAA, ver, stype,
                    seq & 0xFF, (seq >> 8) & 0xFF,
                    cmd, flags,
                    len(payload) & 0xFF, (len(payload) >> 8) & 0xFF])
    body = header + payload
    crc = crc16_modbus(body)
    return body + struct.pack('<H', crc)


def parse_session_frame(data: bytes):
    """解析 Session 帧, 返回 dict 或 None。"""
    if len(data) < 12:
        return None
    if data[0] != 0x55 or data[1] != 0xAA:
        return None
    ver = data[2]
    stype = data[3]
    seq = data[4] | (data[5] << 8)
    cmd = data[6]
    flags = data[7]
    plen = data[8] | (data[9] << 8)
    if len(data) != 10 + plen + 2:
        return None
    payload = data[10:10+plen]
    crc_recv = struct.unpack('<H', data[10+plen:12+plen])[0]
    crc_calc = crc16_modbus(data[:10+plen])
    if crc_recv != crc_calc:
        return None
    return dict(type=stype, seq=seq, cmd=cmd, flags=flags, payload=payload)


def encode_bam(session_payload: bytes, session_id: int) -> list:
    """将 Session 帧编码为 BAM 分片 (20B 帧列表)。"""
    total = len(session_payload)
    frag_count = (total + FRAG_PAYLOAD - 1) // FRAG_PAYLOAD
    frames = []
    for i in range(frag_count):
        offset = i * FRAG_PAYLOAD
        chunk = session_payload[offset:offset+FRAG_PAYLOAD]
        data16 = bytes([session_id, i, frag_count, len(chunk)]) + chunk
        data16 = data16.ljust(16, b'\x00')
        frames.append(build_20b_frame(MCU_ADDR, BAM_FUNC, data16))
    return frames


class BamDecoder:
    """MCU 侧 BAM 重组解码器。"""
    def __init__(self):
        self.reset()

    def reset(self):
        self.active = False
        self.session_id = 0
        self.frag_count = 0
        self.fragments = {}
        self.total_len = 0

    def feed(self, addr, func, data16) -> bytes | None:
        """喂入一帧 20B data, 返回重组完成的 Session payload 或 None。"""
        if func != BAM_FUNC:
            return None

        sid = data16[0]
        fidx = data16[1]
        fcnt = data16[2]
        flen = data16[3]

        # 控制帧
        if fidx in (0xFE, 0xFF):
            return None

        # 新事务
        if not self.active or self.session_id != sid:
            self.reset()
            self.active = True
            self.session_id = sid
            self.frag_count = fcnt

        if fidx >= fcnt or flen > FRAG_PAYLOAD:
            self.reset()
            return None

        if fidx not in self.fragments:
            self.fragments[fidx] = data16[4:4+flen]
            end = fidx * FRAG_PAYLOAD + flen
            if end > self.total_len:
                self.total_len = end

        if len(self.fragments) >= self.frag_count:
            payload = b''.join(self.fragments[i] for i in range(self.frag_count))
            payload = payload[:self.total_len]
            self.reset()
            return payload

        return None


def send_bam_and_wait(ser, session_payload: bytes, session_id: int,
                      timeout=6.0) -> bytes | None:
    """发送 BAM 分片, 等待并重组响应。"""
    frames = encode_bam(session_payload, session_id)

    # 清空接收缓冲
    ser.reset_input_buffer()

    # 发送所有分片
    for f in frames:
        ser.write(f)
        ser.flush()
        time.sleep(0.002)  # 2ms 片间间隔

    # 等待响应
    decoder = BamDecoder()
    deadline = time.time() + timeout
    buf = b''

    while time.time() < deadline:
        waiting = ser.in_waiting
        if waiting > 0:
            chunk = ser.read(waiting)
            buf += chunk

        # 从 buf 中提取 20B 帧
        while len(buf) >= FRAME_SIZE:
            frame = buf[:FRAME_SIZE]
            buf = buf[FRAME_SIZE:]
            parsed = parse_20b_frame(frame)
            if parsed is None:
                continue
            addr, func, data16 = parsed
            result = decoder.feed(addr, func, data16)
            if result is not None:
                return result

        time.sleep(0.005)

    return None


def test_session_cmd(ser, sid, cmd, payload=b'', label=''):
    """发送一条 Session 命令并打印结果。"""
    frame = build_session_frame(S_REQ, sid, cmd, payload)
    hex_frame = frame.hex(' ').upper()
    print(f"\n── {label or CMD_NAMES.get(cmd, f'0x{cmd:02X}')} ──")
    print(f"  TX ({len(frame)}B): {hex_frame}")

    resp = send_bam_and_wait(ser, frame, sid, timeout=6.0)

    if resp is None:
        print(f"  RX: ❌ 超时 (6s), 无响应")
        return None

    hex_resp = resp.hex(' ').upper()
    print(f"  RX ({len(resp)}B): {hex_resp}")

    parsed = parse_session_frame(resp)
    if parsed is None:
        print(f"  ⚠ Session 帧解析失败 (CRC 或格式错误)")
        return None

    cmd_name = CMD_NAMES.get(parsed['cmd'], f"0x{parsed['cmd']:02X}")
    p = parsed['payload']
    result_code = p[0] if p else -1
    print(f"  解析: type=0x{parsed['type']:02X} seq=0x{parsed['seq']:04X} "
          f"cmd={cmd_name} result={result_code}")

    if cmd == CMD_HELLO and len(p) >= 2:
        print(f"  → protocol_ver={p[1]}")
    elif cmd == CMD_DEVICE_INFO and len(p) >= 5:
        caps = p[3] | (p[4] << 8)
        name = bytes(p[5:]).decode('utf-8', errors='replace') if len(p) > 5 else ''
        print(f"  → ver={p[1]}.{p[2]} caps=0x{caps:04X} name={name}")
    elif cmd == CMD_GET_GROUP_LIST and len(p) >= 4:
        count = p[1]
        total = p[2]
        nxt = p[3]
        print(f"  → count={count} total={total} next_offset={nxt}")
        # 解析分组
        off = 4
        for i in range(count):
            if off + 8 > len(p):
                break
            gid = p[off] | (p[off+1] << 8)
            order = p[off+2] | (p[off+3] << 8)
            flags = p[off+4] | (p[off+5] << 8)
            klen = p[off+6]
            nlen = p[off+7]
            off += 8
            key = bytes(p[off:off+klen]).decode('utf-8', errors='replace')
            off += klen
            name = bytes(p[off:off+nlen]).decode('utf-8', errors='replace')
            off += nlen
            print(f"    [{i}] id={gid} key={key} name={name} order={order} flags=0x{flags:04X}")
    elif cmd == CMD_GET_PARAM_LIST and len(p) >= 4:
        count = p[1]
        total = p[2]
        nxt = p[3]
        print(f"  → count={count} total={total} next_offset={nxt}")
        off = 4
        for i in range(min(count, 5)):  # 最多显示 5 个
            if off + 28 > len(p):
                break
            pid = p[off] | (p[off+1] << 8)
            gid = p[off+2] | (p[off+3] << 8)
            ptype = p[off+4]
            pflags = p[off+5] | (p[off+6] << 8)
            scale = p[off+7] | (p[off+8] << 8)
            klen = p[off+25]
            nlen = p[off+26]
            ulen = p[off+27]
            off += 28
            key = bytes(p[off:off+klen]).decode('utf-8', errors='replace')
            off += klen
            name = bytes(p[off:off+nlen]).decode('utf-8', errors='replace')
            off += nlen
            unit = bytes(p[off:off+ulen]).decode('utf-8', errors='replace')
            off += ulen
            print(f"    [{i}] id={pid} gid={gid} key={key} name={name} unit={unit} type={ptype}")
        if count > 5:
            print(f"    ... 还有 {count-5} 个参数")
    elif cmd == CMD_GET_STATUS and len(p) >= 12:
        print(f"  → run={p[1]} task_status={p[2]} busy=0x{p[3]:02X} "
              f"bag_done={p[4]} seal_done={p[5]} "
              f"boot={p[8]} stop_pending={p[9]} "
              f"alarm=0x{p[10]:02X} latched={p[11]}")

    return parsed


def main():
    raise SystemExit('test_session.py 已废弃，请使用 test_session_v3.py')
    port = '/dev/ttyACM0'
    baud = 9600
    node_addr = 0xFA

    global MCU_ADDR
    MCU_ADDR = node_addr

    print(f"打开串口: {port} @ {baud} 8N1")
    ser = serial.Serial(port, baud, bytesize=8, parity='N', stopbits=1,
                        timeout=0.1)
    time.sleep(0.1)
    ser.reset_input_buffer()
    print(f"已连接, 开始测试...\n")

    sid = 1

    # 1. Hello
    r = test_session_cmd(ser, sid, CMD_HELLO, label='① Hello')
    sid += 1
    if r is None:
        print("\n❌ Hello 无响应, 检查连接和节点地址")
        ser.close()
        return

    # 2. Device Info
    r = test_session_cmd(ser, sid, CMD_DEVICE_INFO, label='② Device Info')
    sid += 1

    # 3. Get Group List
    r = test_session_cmd(ser, sid, CMD_GET_GROUP_LIST,
                         payload=bytes([0, 8]),
                         label='③ Get Group List')
    sid += 1

    # 4. Get Param List
    r = test_session_cmd(ser, sid, CMD_GET_PARAM_LIST,
                         payload=bytes([0, 4]),
                         label='④ Get Param List')
    sid += 1

    # 5. Get Status
    r = test_session_cmd(ser, sid, CMD_GET_STATUS, label='⑤ Get Status')
    sid += 1

    print("\n" + "=" * 60)
    print("测试完成")
    ser.close()


if __name__ == '__main__':
    main()
