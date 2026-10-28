#!/usr/bin/env python3
"""Icicle SNN UART hardware validator. Dry-run by default; serial requires --port.
Install: python -m pip install numpy pyserial
"""
import argparse, io, zipfile, sys, time, csv, pathlib
import numpy as np

# for UART
HEADER=b"\xA5\x5A"
def load_vectors(path):
    with zipfile.ZipFile(path) as z:
        get=lambda n: np.load(io.BytesIO(z.read(n+'.npy')),allow_pickle=False)
        return {k:get(k) for k in ['x','R','alarm','driver','layer1_spikes','layer2_spikes','theta']}

def receive_packet(ser, timeout):
    deadline=time.monotonic()+timeout
    state=0
    while time.monotonic()<deadline:
        c=ser.read(1)
        if not c: continue
        b=c[0]
        if state==0: state=1 if b==0xA5 else 0
        elif state==1:
            if b==0x5A: break
            state=1 if b==0xA5 else 0
    else: raise TimeoutError('No A5 5A response header')
    payload=ser.read(10)
    if len(payload)!=10: raise TimeoutError(f'Incomplete response: {len(payload)} of 10 payload bytes')
    pkt=HEADER+payload
    checksum=0
    for b in pkt[:11]: checksum^=b
    if checksum!=pkt[11]: raise ValueError('Packet XOR checksum failed')
    score=int.from_bytes(pkt[2:6],'little',signed=True)
    cycles=int.from_bytes(pkt[6:10],'little',signed=False)
    decision=pkt[10]
    if decision not in (0,1): raise ValueError('Invalid brake flag')
    return score, cycles, decision, pkt.hex(' ')

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--vectors',default='test_vectors.npz.zip')
    ap.add_argument('--port',help='UART port e.g. /dev/ttyUSB0. Omit for dry-run')
    ap.add_argument('--baud',type=int,default=115200)
    ap.add_argument('--indices',default='0,123,124,715',help='Comma-separated row indices; use indexes from curated_cases.csv')
    ap.add_argument('--timeout',type=float,default=8.0)
    ap.add_argument('--inter-byte-delay',type=float,default=0.0,help='Optional seconds between UART bytes')
    ap.add_argument('--gap',type=float,default=0.25,help='Pause between completed frames')
    ap.add_argument('--strict-score',action='store_true',help='Require bit-exact 32-bit readout; recommended after first successful capture')
    ap.add_argument('--log',default='hardware_results.csv')
    args=ap.parse_args()
    d=load_vectors(args.vectors); x=d['x']; score_ref=d['R'].reshape(-1); alarm_ref=d['alarm']
    idxs=[int(s.strip()) for s in args.indices.split(',') if s.strip()]
    for idx in idxs:
        if not 0<=idx<len(x): ap.error(f'Invalid frame index: {idx}')
    print(f'Loaded {len(x)} rows, frame width {x.shape[1]}; theta={int(d["theta"])}')
    print('TEST ROWS:', idxs)
    if not args.port:
        print('DRY RUN: no serial port specified; no bytes transmitted')
        for i in idxs:
            print(f'index={i} driver={d["driver"][i]} expected_score={int(score_ref[i])} expected_brake={int(alarm_ref[i])} first8={x[i,:8].tolist()}')
        return 0
    try: import serial
    except ImportError:
        print('Install pyserial: python -m pip install pyserial',file=sys.stderr);return 2
    rows=[]; bad=0
    with serial.Serial(args.port,args.baud,timeout=0.1,write_timeout=5) as ser:
        # Opening some USB serial adapters may toggle control lines; ensure board is reset/rearmed.
        ser.reset_input_buffer(); ser.reset_output_buffer()
        for i in idxs:
            data=x[i].tobytes(); assert len(data)==390
            try:
                if args.inter_byte_delay:
                    for b in data: ser.write(bytes([b]));time.sleep(args.inter_byte_delay)
                else: ser.write(data)
                ser.flush()
                got,cycles,brake,raw=receive_packet(ser,args.timeout)
                decision_ok=int(brake)==int(alarm_ref[i]);score_ok=got==int(score_ref[i]);
                passed=decision_ok and (score_ok or not args.strict_score)
                print(f'index={i:4d} driver={d["driver"][i]:5s} expected={int(score_ref[i]):6d}/{int(alarm_ref[i])} got={got:6d}/{brake} cycles={cycles} duration_us={cycles/50:.3f} decision_ok={decision_ok} score_ok={score_ok} {"PASS" if passed else "FAIL"}')
                rows.append([i,str(d['driver'][i]),int(score_ref[i]),int(alarm_ref[i]),got,brake,cycles,cycles/50,score_ok,decision_ok,passed,raw,''])
                if not passed:bad+=1
            except Exception as exc:
                bad+=1;print(f'index={i} ERROR {exc}')
                rows.append([i,str(d['driver'][i]),int(score_ref[i]),int(alarm_ref[i]),'','','','','','','', '',str(exc)])
                # Cannot safely assume remaining input frame state on timeout/corruption.
                print('STOP: reset hardware and re-check RX/TX/frame_clear before retrying.',file=sys.stderr)
                break
            time.sleep(args.gap)
    with open(args.log,'w',newline='') as f:
        w=csv.writer(f);w.writerow(['index','driver','expected_score','expected_brake','hardware_score','hardware_brake','cycles','latency_us_at_50MHz','score_match','brake_match','passed','packet_hex','error']);w.writerows(rows)
    print(f'Results saved: {args.log}; failed={bad}')
    return 1 if bad else 0
if __name__=='__main__':sys.exit(main())
