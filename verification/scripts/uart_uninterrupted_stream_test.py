#!/usr/bin/env python3
"""Full-duplex UART stress test: writes contiguous 390-byte frames without waiting for replies.
Uses the test_vectors.npz.zip schema from hardware_uart_test.py.
"""
import argparse
import csv
import io
import threading
import time
import zipfile

import numpy as np
import serial


def load_vectors(path):
    with zipfile.ZipFile(path) as z:
        def read(name):
            return np.load(io.BytesIO(z.read(name + '.npy')), allow_pickle=False)
        return read('x'), read('R').reshape(-1), read('alarm').reshape(-1)


def decode_packets(buf):
    results = []
    p = 0
    bad_checksums = 0
    while p + 12 <= len(buf):
        start = buf.find(b'\xa5\x5a', p)
        if start < 0 or start + 12 > len(buf):
            break
        pkt = bytes(buf[start:start+12])
        if (lambda a: __import__('functools').reduce(lambda x, y: x ^ y, a, 0))(pkt[:11]) == pkt[11] and pkt[10] in (0, 1):
            score = int.from_bytes(pkt[2:6], 'little', signed=True)
            cycles = int.from_bytes(pkt[6:10], 'little')
            results.append((score, cycles, pkt[10], pkt.hex(' ')))
            p = start + 12
        else:
            bad_checksums += 1
            p = start + 1
    return results, bad_checksums


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--vectors', default='test_vectors.npz.zip')
    ap.add_argument('--port', default='/dev/ttyUSB2')
    ap.add_argument('--baud', type=int, default=115200)
    ap.add_argument('--indices', default='0,123,1,2,3,4,5,6,7,8')
    ap.add_argument('--drain-seconds', type=float, default=2.0, help='Listen after write completes')
    ap.add_argument('--log', default='uninterrupted_stream_results.csv')
    args = ap.parse_args()

    x, scores, brakes = load_vectors(args.vectors)
    idxs = [int(t.strip()) for t in args.indices.split(',') if t.strip()]
    if not idxs or any(i < 0 or i >= len(x) for i in idxs):
        ap.error('Missing or out-of-range indices')
    if x.shape[1] != 390:
        ap.error('Input frame width is not 390')
    if args.drain_seconds < 0:
        ap.error('--drain-seconds must be nonnegative')
    tx = b''.join(x[i].astype(np.uint8, copy=False).tobytes() for i in idxs)
    print(f'Streaming {len(idxs)} frames, {len(tx)} bytes, {args.baud} baud on {args.port}')
    print('No per-frame wait, no inter-frame delay, no FPGA reset during stream.')
    print('Estimated wire TX time: %.3f s' % (len(tx)*10/args.baud))

    captured = bytearray()
    rx_error = []
    stop = threading.Event()
    with serial.Serial(args.port, args.baud, timeout=0.05, write_timeout=10) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        def read_responses():
            try:
                while not stop.is_set():
                    chunk = ser.read(256)
                    if chunk:
                        captured.extend(chunk)
            except Exception as e:
                rx_error.append(str(e))

        rx = threading.Thread(target=read_responses, daemon=True)
        rx.start()
        start = time.monotonic()
        sent = ser.write(tx)  # Single contiguous write; never waits for a response.
        ser.flush()           # Waits for transmit completion only.
        tx_done = time.monotonic()
        print(f'Sent {sent}/{len(tx)} bytes; write+flush time {tx_done-start:.3f} s')
        time.sleep(args.drain_seconds)
        stop.set()
        rx.join(timeout=1)

    packets, bad_checksums = decode_packets(bytes(captured))
    print(f'RX raw bytes: {len(captured)}, valid packets: {len(packets)}, invalid-header candidates: {bad_checksums}')
    if rx_error:
        print('RX error:', rx_error[0])
    rows = []
    for n, idx in enumerate(idxs):
        if n < len(packets):
            got_score, cycles, got_brake, raw = packets[n]
            passed = got_score == int(scores[idx]) and got_brake == int(brakes[idx]) and cycles == 839
            print(f'{n:3d}: idx={idx:4d} expected={int(scores[idx]):6d}/{int(brakes[idx])} got={got_score:6d}/{got_brake} cycles={cycles} {"PASS" if passed else "FAIL"}')
            rows.append([n,idx,int(scores[idx]),int(brakes[idx]),got_score,got_brake,cycles,passed,raw])
        else:
            print(f'{n:3d}: idx={idx:4d} MISSING RESPONSE')
            rows.append([n,idx,int(scores[idx]),int(brakes[idx]),'','','',False,''])
    with open(args.log,'w',newline='') as f:
        w=csv.writer(f)
        w.writerow(['sequence','index','expected_score','expected_brake','score','brake','cycles','passed','packet_hex'])
        w.writerows(rows)
    ok = len(packets) == len(idxs) and all(r[7] for r in rows) and not rx_error
    print(f'RESULT: {"PASS" if ok else "FAIL"} ({sum(bool(r[7]) for r in rows)}/{len(idxs)} frames); log={args.log}')
    if not ok:
        print('If packets are missing, reset the FPGA before the next trial. Packet indexing assumes ordered responses.')
    return 0 if ok else 1

if __name__ == '__main__':
    raise SystemExit(main())
