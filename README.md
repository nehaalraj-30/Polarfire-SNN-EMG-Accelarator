# PolarFire SoC EMG SNN Accelerator

A hardware-validated **INT8 spiking neural network (SNN) accelerator** for EMG-based emergency-braking inference on the **Microchip PolarFire SoC Icicle Kit**.

**Current state (28 October 2026):** 390-byte feature frames are processed correctly on the physical FPGA. The implementation passed **100/100 uninterrupted, back-to-back UART frames** with bit-exact scores and decisions against the software reference. PAC-based power measurements and end-to-end latency profiling are the next milestones.

## Key results

| Measurement | Hardware observation |
|---|---|
| Network | 390 → 128 → 64 → 1; 8 timesteps |
| FPGA | PolarFire SoC MPFS250TC-FCVG484E |
| Clock | 50 MHz |
| Input | 390 unsigned 8-bit features/frame |
| UART | 115200 baud, 8-N-1 |
| Compute cycles/frame | **839** |
| Compute-only latency | **16.78 µs** |
| Response-synchronized frames | **100/100 PASS** |
| Uninterrupted back-to-back frames | **100/100 PASS** |
| Uninterrupted TX duration | **3.434 s / 39,000 bytes** |
| Observed host TX throughput | **29.12 frames/s** |
| Packet loss/invalid headers in 100-frame run | **0 observed** |
| Mixed brake/non-brake streaming | **PASS** |

> **Scope:** These are measurements for the tested data and board configuration. `16.78 µs` refers to hardware inference cycles only—not feature acquisition, UART transfer or host/USB latency. The streaming throughput is derived from host write/flush duration, not independent timestamping of completed inference responses.

## Architecture

```text
Host PC (quantized 390 × UINT8 input features)
     │  UART 115200 baud / 8-N-1
     ▼
CoreUART ↔ uart_emg_bridge / UART_INPUT_ROUTER
     ▼
emgBuffer + ADAS_BUFFER + INPUT_READY + INPUT_COMBINER
     ▼
snnController (8 timesteps)
     ├── Layer I    390 → 128 LIF, INT8 weights
     ├── Layer II   128 → 64 LIF, INT8 weights
     └── Layer III  64 → 1 signed accumulated readout
     ▼
Score threshold θ = 3145 → brake / non-brake
     ├── Latched output pins
     └── inference_perf_counter + SNN_UART_REPORTER → CoreUART TX
```

The accelerator consumes **preprocessed and quantized** input vectors. An on-FPGA EMG preprocessing/feature extraction/quantization pipeline is **planned**, not part of the validated baseline.

### UART interface

- **Input:** exactly 390 raw bytes per frame (no input header).
- **Output:** 12 bytes: magic `A5 5A`, signed 32-bit little-endian score, unsigned 32-bit little-endian cycle count, one brake byte, one XOR checksum byte.
- **Validated Linux interface:** CP2108 USB-UART `if02`, `/dev/ttyUSB2` for the lab run. Port numbers may change; inspect `/dev/serial/by-id/`.
- **Test vector archive:** `verification/vectors/test_vectors.npz.zip` contains inputs and reference `R` and `alarm` arrays.

## Toolchain

- Libero SoC **2026.1** / Synplify Pro **Y-2026.03M**.
- FPGA clock **50 MHz**; board programming via embedded FlashPro/JTAG and SPI Flash initialization.
- Python **3** with `numpy` and `pyserial` for hardware validation.

## Repository layout

```text
SNN_EMG.prjx                          Libero project
hdl/                                  LIF layers, controller, buffers, UART logic
component/                            SmartDesign and IP descriptions/configuration
constraint/                           Pin assignments, timing/physical constraints
synthesis/layer*.mem                  Trained INT8 weights and biases
layer1_weights_390x1024_LSB_first_corrected.hex
verification/scripts/                  Hardware validation code
verification/vectors/                  Test archive
verification/results/                  Captured CSV results
docs/                                  Hardware notes / GitHub issue
```

**Note:** `component/work/SNN/SNN.sdb` and other SmartDesign configuration files must be tracked for a reproducible Libero project. Generated synthesis and place-and-route outputs are intentionally not kept in regular Git history. The exact programmed images may need separate archival.

## SPI Flash weight byte-order correction

The FPGA initially produced numerically incorrect scores, despite valid UART packets and the correct 839-cycle inference count:

| Test | Reference | Old FPGA result | FPGA with corrected HEX |
|---|---:|---:|---:|
| Archive vector 0 | −3664 | −840 | **−3664** |
| Archive vector 123 | 3425 | Not logged | **3425** |
| Original `input_390.mem` | 2880 | 1261 | Not separately logged after fix |

Layer I stores one 1024-bit packed weight word per input feature (128 neurons × 8 bits). The RTL extracts neuron `i` using `weight_row_reg[i*8 +: 8]`: neuron 0 is in the **least significant byte**. The original Intel HEX emitted each packed word **MSB first**. Software evaluation under the swapped byte interpretation reproduced the hardware errors. The corrected HEX reverses the **128 bytes within each of the 390 words**, preserving feature and neuron identities.

The corrected HEX is loaded as **Fabric RAM content from file**, with initialization storage **SPI Flash**. Changing storage settings in Libero can reset content to zero-filled: confirm the file is selected before generating initialization data. The SPI Flash image and FPGA bitstream are generated/programmed separately, followed by a board power-cycle.

## Reproduce the UART hardware validation

Install dependencies:

```bash
python3 -m pip install numpy pyserial
```

From the directory containing the scripts and `test_vectors.npz.zip` (or pass `--vectors` explicitly):

**One frame / synchronized testing:**

```bash
python3 hardware_uart_test.py --port /dev/ttyUSB2 --baud 115200 \
  --indices 0,123 --timeout 15 --strict-score \
  --log multi_frame_test.csv
```

**Back-to-back streaming (no response wait):**

```bash
python3 uart_uninterrupted_stream_test.py --port /dev/ttyUSB2 \
  --baud 115200 --indices "$(seq -s, 0 99)" \
  --drain-seconds 3 --log uninterrupted_100_frames.csv
```

The streaming test writes one **39,000-byte** contiguous payload and receives replies concurrently on a separate thread. It checks every packet's checksum, signed score, brake bit and cycle count. **100/100 passed**: 1,200 response bytes, 100 valid packets, no observed invalid-header candidates, 839 cycles each. The mixed-class uninterrupted test also passed.

### Validation evidence (CSV)

- `verification/results/hardware_results.csv`
- `verification/results/multi_frame_test.csv`
- `verification/results/continuous_10_frames.csv`
- `verification/results/continuous_100_frames.csv`
- `verification/results/uninterrupted_10_frames.csv`
- `verification/results/uninterrupted_100_frames.csv` **(ensure this CSV is committed; it was not shown in the earlier Git staged-files listing)**
- `verification/results/mixed_class_streaming.csv`

The CSVs are the authoritative result logs. This README summarizes the user-reported console outputs and does not substitute for raw measurements.

## Performance interpretation

At 115200 baud, 8-N-1:

- **390-byte input wire time:** `390 × 10 / 115200 ≈ 33.85 ms`.
- **12-byte response wire time:** `12 × 10 / 115200 ≈ 1.04 ms`.
- **Compute-only time:** `839 / 50 MHz = 16.78 µs`.
- **Max nominal UART input rate:** `115200 / (390 × 10) ≈ 29.54 frames/s`.
- **Observed host TX throughput:** `100 / 3.434 ≈ 29.12 frames/s` (about **98.6%** of nominal limit).

End-to-end latency has **not** yet been independently measured. Software timestamps will provide a host-observed measurement, with additional instrumentation needed for accurate FPGA-edge timing.

## Roadmap

- [x] Synthesize, place-and-route, program FPGA and SPI Flash initialization.
- [x] Identify and fix packed Layer I HEX byte-order mismatch.
- [x] Bit-exact hardware scores for braking and non-braking examples.
- [x] 100 response-synchronized frames and 100 uninterrupted UART frames.
- [x] Mixed-class uninterrupted UART streaming.
- [ ] Read the Icicle Kit PAC power-monitor rails and produce idle/active logs.
- [ ] Estimate total board energy and **incremental energy per inference**; document sensor sample-rate limits and which rails are included.
- [ ] Measure host-observed end-to-end latency distributions and, if needed, hardware-level edge timing.
- [ ] Build and validate FPGA-side EMG signal processing, feature extraction and quantization.

## Reproducing the project and backup policy

The repository tracks **source RTL, Libero project/SmartDesign, constraints, weights, corrected HEX, test scripts and CSV evidence**. Tool-generated synthesis/place-and-route outputs are excluded to keep Git storage small. To regenerate the bitstream and external SPI Flash image, use the specified Libero version, verify available IP dependencies/constraints, and regenerate both programming artifacts. **Do not assume the FPGA bitstream alone contains the externally initialized Layer I weights.**

For detailed investigation and measurement tasks, see `docs/HARDWARE_VALIDATION.md` and the corresponding GitHub issue.

## Safety and intended use

This is a research prototype for exploring EMG-driven braking inference, **not a safety-certified vehicle braking controller**. Hardware scores and decisions have been validated on selected test vectors; real-vehicle use would require additional safety engineering, sensor-chain validation and system-level testing.
