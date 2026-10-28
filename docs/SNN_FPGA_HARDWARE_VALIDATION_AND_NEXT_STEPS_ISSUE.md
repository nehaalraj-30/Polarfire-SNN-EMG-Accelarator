# [Hardware milestone] PolarFire SoC SNN: architecture, SPI-ROM byte-order fix, 100-frame streaming validation, PAC power and end-to-end latency

**Status (2026-10-28):** Working, FPGA-tested baseline. The SPI initialization discrepancy has been corrected, bit-exact inference has been demonstrated, and 100 back-to-back 390-byte frames passed without host-side response synchronization. **Next work:** on-board PAC power acquisition and per-frame/end-to-end latency instrumentation. EMG preprocessing/quantization in FPGA is deferred.

> **Scope of this issue:** Record a reproducible implementation and its validation evidence, protect the working build, and define the next measurement tasks. The original CSVs and final project programming files reside on the lab laptop; link/commit them using the paths below. Do not mistake an issue attachment for a version-controlled source backup.

## 1. Hardware/software architecture — implemented baseline

**Platform:** Microchip PolarFire SoC Icicle Kit, MPFS250TC-FCVG484E; Libero SoC 2026.1; Synplify Pro Y-2026.03M; primary fabric clock **50 MHz**. FPGA-side inference uses **signed INT8 weights**, signed 32-bit state/accumulators/readout, and 8 LIF timesteps per 390-byte frame.

```text
Host PC (Python, prepared UINT8 features from test_vectors.npz.zip)
    | 390 bytes per frame, raw binary, UART 115200, 8-N-1
    v
CP2108 USB/UART bridge (verified laptop interface /dev/ttyUSB2)
    |
CoreUART RX -> uart_emg_bridge / UART_INPUT_ROUTER
    |                  |
    v                  +--> frame routing / INPUT_READY / ADAS_BUFFER /
 EMG input buffer             INPUT_COMBINER (SmartDesign glue)
    | 390 x 8-bit input feature vector
    v
snnController (frame/step handshakes, clear_accum, inference_done)
    |
    +--> Layer 1: 390 -> 128 LIF (INT8 weight ROM; one input current per frame,
    |    then eight LIF steps; VTH=23540, VINIT=11770, leak >>3)
    |      ROM: 390 x 1024-bit packed rows, one 8-bit weight/neuron/feature
    +--> Layer 2: 128 -> 64 LIF (spike input; VTH=96, VINIT=48,
    |    leak >>3; INT8 weights and INT32 biases)
    +--> Layer 3: 64 -> 1 signed, non-spiking readout; registered grouped sum,
         biased input and accumulator; eight-step accumulated score
    |
    v
Threshold compare: score >= 3145 -> brake = 1
    |
    +--> latched brake / non-brake outputs and inference LED
    +--> inference_perf_counter + SNN_UART_REPORTER -> CoreUART TX -> host
```

**Other relevant sources in the SmartDesign:** `emgBuffer`, `ADAS_BUFFER`, `INPUT_COMBINER`, `INPUT_READY`, `UART_INPUT_ROUTER`, `SNN_UART_REPORTER`, `inference_perf_counter`, `snnController`, `layer_if_neuron`, `layer_if_neuron_II`, `layer_if_neuron_III`, and the CoreUART/clock components. Preserve the generated connections; this is a logical overview, **not** a claim that every glue-module internal signal was audited.

**FPGA serial output protocol:** 12 bytes total: `A5 5A` magic (2), signed INT32 score little-endian (4), unsigned UINT32 cycle count little-endian (4), brake decision (1), XOR checksum over the first 11 bytes (1). Frames do **not** have input headers: exactly 390 raw UINT8 bytes per frame.

**Current board I/O constraints (verify against the committed `.pdc`):** `REF_CLK_0=W12`, `rst_n=V19`, `RX=C22`, `TX=B22`, `latched_brake_trigger=V14`, `latched_non_brake_trigger=U13`, `inference_led=T12`. I/O bank standards and physical connector routes must follow the actual PDC/board revision. Board USB CP2108 has four Linux serial devices; `/dev/ttyUSB2` was confirmed operational in the lab; use `/dev/serial/by-id/` to locate it after USB re-enumeration.

**Timing:** `839` cycles per inference at `50 MHz` = **16.78 µs compute-only**, reported for all logged test frames. This is not the end-to-end latency, and it excludes feature production, serial transmission, USB scheduling and result reporting.

**Model artifacts:** `layer1_weights_packed.mem`, `layer1_biases.mem`, `layer2_weights.mem`, `layer2_biases.mem`, `layer3_weights.mem`, `layer3_biases.mem`, matching the trained quantized network; reference test archive `test_vectors.npz.zip` contains 3,600 390-byte examples, expected scores `R`, decisions `alarm` and additional metadata. Layer 1 input is **unsigned UINT8**; its weights are signed INT8. Quantization and signal preprocessing are currently performed upstream, not implemented as a new FPGA EMG front end.

## 2. Root cause and resolution — Layer 1 SPI Flash initialization

### Symptom

Pre-/post-synthesis simulation predicted the correct scores, but the original physical FPGA returned different signed scores while still returning a valid UART packet and `839` cycles:

| Reference input | Software/RTL reference | Hardware with original SPI HEX | Hardware after corrected HEX |
|---|---:|---:|---:|
| `input_390.mem` | `2880` | `1261` | **Not yet independently reported in this issue's hardware transcript** |
| Test archive row `0` | `-3664` | `-840` | **`-3664` (PASS)** |
| Test archive row `123` | `3425` | Not recorded here | **`3425` (PASS)** |

The mismatch was **not** a general UART failure: packet parsing, output selection and cycle counting worked. It was consistent with **reversed byte placement in each 1024-bit Layer 1 ROM row when preparing the manually supplied SPI Flash Intel HEX**.

### Logical packed-ROM layout

Layer 1 RTL declares:

```verilog
(* syn_romstyle = "lsram" *)
reg [1023:0] weight_rom [0:389];
initial $readmemh("layer1_weights_packed.mem", weight_rom);
// For output neuron i:
w_temp = $signed(weight_row_reg[i*8 +: 8]);
```

Each `.mem` line is a **256-character hexadecimal word** (128 bytes): the byte on the **right** is the least-significant byte, read as neuron `0`; neuron `127` is the most-significant byte on the **left**. The original candidate `.hex` emitted each line in its textual left-to-right byte order. Under the observed SPI image interpretation, this effectively reversed the 128 neuron weights within a row.

An offline software simulation of the alternate HEX byte interpretation was previously reported to reproduce both hardware discrepancies exactly: `1261` for `input_390.mem` and `-840` for archive row `0`. **This strongly implicated the import byte ordering**; it was not necessary to modify the LIF RTL, trained matrices, or Layer 2 indexing.

### Fix and hardware confirmation

Generate an Intel HEX stream by reversing the **128 bytes within each of the 390 packed `.mem` rows**, not by reversing the entire file or reordering features. Existing generator:

```bash
python3 make_layer1_hex_fix.py \
  layer1_weights_packed.mem \
  layer1_weights_390x1024_LSB_first_corrected.hex
```

Corrected content: **390 x 128 = 49,920 weight bytes** encoded as Intel HEX records with valid checksums. In Libero, set Layer 1 fabric RAM to **Content from file** using the corrected `.hex` and **SPI Flash** storage; check it does not revert to **Content filled with 0s** when the storage setting changes. Re-run the relevant initialization/image generation steps, program the SPI Flash initialization image, program the FPGA configuration and power-cycle to ensure initialization is loaded. Preserve the original candidate HEX and a record of image checksums for reproducibility.

**Measured confirmation:** after programming, archive row `0` returned `-3664` (839 cycles, brake 0), and row `123` returned `3425` (839 cycles, brake 1), both bit-exact. The 100-frame sustained stream also passed bit-exactly. This validates the **operational** Layer 1 initialization for the tested frames; no physical per-cell memory readback was performed.

**Historical implementation detail:** the earlier Layer 1 synthesis was mapped across hundreds of uSRAM primitives (602 were recorded during prior SPI client investigation); the main failure was an imported logical image ordering mismatch, not proof that the trained `.mem` had incorrect weights. Treat primitive counts as build-specific, and recheck after RTL or tool changes.

## 3. Testing methodology, scripts and evidence

### Reference data and pass criteria

- **Dataset:** `test_vectors.npz.zip` (`x`: 3,600 x 390 UINT8, `R`: signed expected score, `alarm`: expected 0/1 label). Threshold `theta=3145`.
- **UART:** CP2108 `if02` mapped to `/dev/ttyUSB2` during tests; 115200 baud, 8 data bits, no parity, 1 stop bit.
- **Output validity:** find `A5 5A`, parse 12 bytes, verify XOR checksum, compare signed score and brake decision to the reference, and check `cycles==839`.
- **Reset:** single reset before test as needed; **no FPGA reset between consecutive frames** for multi-frame/streaming runs.

### Test A: response-synchronized inference (`hardware_uart_test.py`)

```bash
cd ~/SOP_4_1/SNN_hardware_lab_ready/snn_lab_ready
python3 -m pip install numpy pyserial
python3 hardware_uart_test.py --indices 0,123   # dry run, no hardware traffic

python3 hardware_uart_test.py \
  --port /dev/ttyUSB2 --baud 115200 \
  --indices 0,123 --timeout 15 --gap 1 --strict-score \
  --log multi_frame_test.csv

python3 hardware_uart_test.py \
  --port /dev/ttyUSB2 --baud 115200 \
  --indices 0,123,1,2,3,4,5,6,7,8 \
  --timeout 15 --gap 0 --strict-score \
  --log continuous_10_frames.csv

python3 hardware_uart_test.py \
  --port /dev/ttyUSB2 --baud 115200 \
  --indices "$(seq -s, 0 99)" \
  --timeout 15 --gap 0 --strict-score \
  --log continuous_100_frames.csv
```

**Algorithm:** write 390 raw bytes, flush TX, **wait for that frame's 12-byte FPGA response**, validate it, optionally sleep `--gap` seconds, then send the next frame. `--gap 0` does **not** imply uninterrupted wire traffic, because the host still waits for each response.

**Observed:** single-frame row 0 and 123 PASS; 2-frame and 10-frame tests PASS; 100 response-synchronized frames also reported PASS.

### Test B: uninterrupted input streaming (`uart_uninterrupted_stream_test.py`)

```bash
python3 uart_uninterrupted_stream_test.py \
  --port /dev/ttyUSB2 --baud 115200 \
  --indices 0,123,1,2,3,4,5,6,7,8 \
  --drain-seconds 2 \
  --log uninterrupted_10_frames.csv

python3 uart_uninterrupted_stream_test.py \
  --port /dev/ttyUSB2 --baud 115200 \
  --indices "$(seq -s, 0 99)" \
  --drain-seconds 3 \
  --log uninterrupted_100_frames.csv

# Mixed brake / non-brake continuous stream (also reported PASS):
python3 uart_uninterrupted_stream_test.py \
  --port /dev/ttyUSB2 --baud 115200 \
  --indices 0,123,1,123,2,123,3,123,4,123 \
  --drain-seconds 2 \
  --log mixed_class_streaming.csv
```

**Algorithm (source inspected):** concatenate selected 390-byte frames into one byte buffer; start a separate serial reader thread; issue **one `serial.write(tx)` followed by `serial.flush()`** with no response wait or deliberate inter-frame gap; keep collecting responses for `--drain-seconds`; search 12-byte `A5 5A` packets, check checksum, decode and compare **in order** to reference records; save per-frame CSV. The test verifies *sustained inbound framing* under the recorded duration, but does not by itself timestamp FPGA per-frame completion or prove infinite-duration reliability.

**Measured results:**

| Trial | TX payload | Host write+flush duration | Valid packets | Exact score / decision | Reported cycles | Outcome |
|---|---:|---:|---:|---:|---:|---|
| 10 uninterrupted frames | 3,900 B | 0.345 s | 10 / 10; 120 RX bytes | 10 / 10 | 839 each | PASS |
| 100 uninterrupted frames | 39,000 B | **3.434 s** | **100 / 100; 1,200 RX bytes** | **100 / 100** | **839 each** | **PASS** |
| Mixed-class uninterrupted | 10 alternating non-brake/brake frames | Not recorded here | Reported complete | Reported PASS | Check saved CSV | PASS (reported) |

All 100 uninterrupted outputs were bit-exact, with **zero invalid-header candidates**, no extra host wait, no explicit inter-frame delay and no FPGA reset. The 100-frame stress sequence used archive indices `0..99` (all non-brake); mixed-class test separately checks transitions.

**100-frame host TX rate (not measured response latency):** `100 / 3.434 = 29.12 frames/s`, or `39,000 / 3.434 ≈ 11,357 B/s`. The 115200-baud 8-N-1 theoretical maximum is `115200 / (390*10) = 29.54 frames/s`; measured host send rate is approximately **98.6%** of this ceiling. Theoretical raw 390-byte acquisition/transmission time is **33.854 ms/frame**. FPGA compute-only `839 / 50 MHz = 16.78 µs`. The serialized 12-byte UART return consumes **1.042 ms** of wire time if sent at 115200 baud. These are components; their sum must not be presented as a precisely measured end-to-end latency because overlap, boundaries and host/USB buffering matter.

### CSV/artifact manifest — commit the actual lab files

| Repo destination (proposed) | Local source on lab machine | Content |
|---|---|---|
| `verification/scripts/hardware_uart_test.py` | `SNN_hardware_lab_ready/snn_lab_ready/hardware_uart_test.py` | Response-synchronized test + 12-byte packet parser |
| `verification/scripts/uart_uninterrupted_stream_test.py` | `SNN_hardware_lab_ready/snn_lab_ready/uart_uninterrupted_stream_test.py` | One-write continuous TX + independent RX thread |
| `verification/vectors/test_vectors.npz.zip` | `SNN_hardware_lab_ready/snn_lab_ready/test_vectors.npz.zip` | Reference vectors and expected outputs; review dataset redistribution permissions |
| `verification/results/multi_frame_test.csv` | `SNN_hardware_lab_ready/snn_lab_ready/multi_frame_test.csv` | 2-frame response-synchronized trial |
| `verification/results/continuous_10_frames.csv` | `SNN_hardware_lab_ready/snn_lab_ready/continuous_10_frames.csv` | 10-frame response-synchronized trial |
| `verification/results/continuous_100_frames.csv` | `SNN_hardware_lab_ready/snn_lab_ready/continuous_100_frames.csv` | 100-frame response-synchronized trial |
| `verification/results/uninterrupted_10_frames.csv` | `SNN_hardware_lab_ready/snn_lab_ready/uninterrupted_10_frames.csv` | 10-frame one-write streaming trial |
| `verification/results/uninterrupted_100_frames.csv` | `SNN_hardware_lab_ready/snn_lab_ready/uninterrupted_100_frames.csv` | **Primary streaming evidence**: 100/100 scores, cycles, packet hex |
| `verification/results/mixed_class_streaming.csv` | `SNN_hardware_lab_ready/snn_lab_ready/mixed_class_streaming.csv` | Alternating positive/negative stream; check filename against actual script invocation |
| `verification/vectors/input_390.mem` | Existing first-frame reference file | Single test that historically exposed `2880` vs `1261` |
| `hdl/` + source `.mem` files | Project `hdl/`, `synthesis/` as applicable | Reproducible design, trained data; commit original/corrected HEX as appropriate |
| `docs/make_layer1_hex_fix.py` | HEX byte-reversal generator | Reproducible ROM conversion |
| `docs/layer1_weights_390x1024_LSB_first_corrected.hex` | Verified HEX supplied to Libero | Exact corrected logical initialization payload |

**Do not invent/replace missing CSVs:** some files may have been written under different `--log` names; inspect the actual lab directory and use the real files. If an intermediate CSV was overwritten because a test reused its name, rely on preserved console logs and the final primary `uninterrupted_100_frames.csv` instead. Record Git commit ID and bitstream/SPI image hashes for the final run.

## 4. Next work — PAC power, energy per frame, end-to-end latency

### A. PAC on-board power measurement (not yet implemented)

- [ ] Identify **exact** PAC monitor device(s), rail(s), channel assignments, sensor sense resistor and conversion scale for the **Icicle Kit board revision** from the schematic/manual; avoid assuming all measured rails are FPGA fabric rails.
- [ ] Confirm how to access PAC telemetry (board controller, I²C, vendor GUI/CLI or firmware). Read-only first; do not disturb boot/configuration I²C transactions.
- [ ] Capture **idle power** (configured, no incoming frame), **active power** during repeated streaming, and **total rail power** using consistent rail coverage and sampling intervals; export timestamped `power_samples.csv` with units, rail label and measurement source.
- [ ] If PAC sampling is slower than a 16.78-µs inference, **do not claim a directly measured instantaneous per-frame compute-power trace**. Use sustained-stream and idle measurements to estimate average *incremental* power/energy per frame, and clearly label its methodology and assumptions. For fine-grained inference-only energy, use a board-supported high-bandwidth measurement setup or a suitable hardware trigger.
- [ ] Compute `P_total(t)=sum(P_rail(t))` **only for a documented, non-overlapping collection of rails**, and report baseline/active (and, if useful, incremental) power separately. Distinguish power (W) from energy (J).
- [ ] Measure energy over a streaming interval by timestamp integration, `E_total = ∫ P(t)dt`; estimate average `E_per_frame = (E_active_interval - E_idle_baseline_interval)/N_frames` only when aligned intervals and background power are accounted for. Preserve a separate **total-system energy/frame** value `E_active_interval/N_frames` if desired.
- [ ] Compare cautiously with earlier **SmartPower estimate 324.654 mW total** (`123.063 mW` static, `201.591 mW` dynamic). This is an **EDA estimate**, not a PAC measurement.

### B. End-to-end latency (not yet measured)

- [ ] Define endpoints precisely: `host start of first input byte -> complete valid response packet`, and separately `last input byte received -> brake output/response start`, where instrumentable.
- [ ] Enhance Python sender/reader to timestamp TX start, `flush()` completion, first/last RX packet byte using `time.perf_counter_ns()`/`time.monotonic_ns()`; **label host timestamps as USB/OS-level**, not precise electrical-pin edges.
- [ ] For per-frame attribution during streaming, log frame index, scheduled transmit boundaries, result packet order and capture timestamps in a `frame_latency.csv`. A single write+flush does not furnish precise individual frame TX timestamps; use pacing/instrumented writes if necessary and document any resulting impact on streaming behavior.
- [ ] For hardware-grade frame latency, use logic analyzer/oscilloscope or FPGA timestamp/trigger pins referenced to the 50-MHz clock, measuring first/last UART byte, inference start/done, LED/brake update and reporter TX.
- [ ] Report separate quantities: **UART ingress** (~33.854 ms minimum for 390 bytes @115200 8-N-1); **SNN computation** (16.78 µs measured from 839 cycles); **UART 12-byte egress** (~1.042 ms wire time); **measured end-to-end** including actual buffering/scheduling and processing. Avoid simply adding component times and labeling the sum measured.

### C. Deferred work (separate issues later)

- [ ] Build on-FPGA EMG preprocessing/feature extraction and quantization pipeline; specify source EMG sampling rate, window/frame boundaries, scaling, clipping, and equivalence to current prepared 390-byte inference features.
- [ ] Revisit buffering/throughput for a genuine live EMG source after the measured PAC and latency baseline is established. **Do not alter the now hardware-validated neuron datapath or rearm logic unnecessarily.**

## 5. Acceptance criteria for this issue / next milestone

- [x] Single-frame bit-exact score and brake for positive/negative vectors.
- [x] 100 response-synchronized frames passed without reset.
- [x] 100 uninterrupted 390-byte frames: all 100 packets valid and exact, 839 cycles each.
- [x] Mixed-class uninterrupted frame sequence: reported PASS.
- [x] Corrected Layer 1 SPI HEX deployed and hardware-validated.
- [ ] Commit readable RTL, constraints, *both original and corrected HEX where permitted*, scripts, raw lab CSVs, and documentation to a **private** GitHub repository; store exact build identifier/hashes.
- [ ] PAC rail mapping validated; idle/active power and captured telemetry committed.
- [ ] Per-frame energy and stream-total energy calculated with stated assumptions and test conditions.
- [ ] End-to-end latency methodology implemented, measured and CSV-logged; compute-only latency kept separate.

**Build preservation:** commit source/constraints/parameters/HEX/scripts and small results, but **do not blindly commit** Libero-generated `designer/`, `synthesis/synwork/`, `.vm`, SPI programming images, temporary logs, cached simulations or license files. If recovering an *identical binary bitstream* is required, store its SHA256 and place it in a separate secure artifact store/release after reviewing file size and IP sensitivity. GitHub is a useful source backup, **not** a substitute for storing the exact hardware programming artifact when needed.
