set_device -family {PolarFireSoC} -die {MPFS250TC} -speed {STD} -range {EXT}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/ADAS_BUFFER.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/component/work/COREUART_C0/COREUART_C0_0/rtl/vlog/core/Rx_async.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/component/work/COREUART_C0/COREUART_C0_0/rtl/vlog/core/Tx_async.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/component/work/COREUART_C0/COREUART_C0_0/rtl/vlog/core/fifo_256x8_g5.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/component/work/COREUART_C0/COREUART_C0_0/rtl/vlog/core/Clock_gen.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/component/work/COREUART_C0/COREUART_C0_0/rtl/vlog/core/CoreUART.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/component/work/COREUART_C0/COREUART_C0.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/INPUT_COMBINER.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/INPUT_READY.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/Not_gate.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/component/work/PF_CCC_C0/PF_CCC_C0_0/PF_CCC_C0_PF_CCC_C0_0_PF_CCC.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/component/work/PF_CCC_C0/PF_CCC_C0.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/SNN_UART_REPORTER.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/UART_INPUT_ROUTER.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/emgBuffer.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/inference_perf_counter.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/layer_if_neuron_III.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/layer_if_neuron_II.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/layer_if_neuron.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/reset.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/snnController.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/snn_output_latch.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/hdl/uart_emg_bridge.v}
read_verilog -mode system_verilog {/home/nehaal-raj/SOP_4_1/SNN_EMG/component/work/SNN/SNN.v}
set_top_level {SNN}
read_sdc -component {/home/nehaal-raj/SOP_4_1/SNN_EMG/component/work/PF_CCC_C0/PF_CCC_C0_0/PF_CCC_C0_PF_CCC_C0_0_PF_CCC.sdc}
derive_constraints
write_sdc {/home/nehaal-raj/SOP_4_1/SNN_EMG/constraint/SNN_derived_constraints.sdc}
write_ndc {/home/nehaal-raj/SOP_4_1/SNN_EMG/constraint/SNN_derived_constraints.ndc}
write_pdc {/home/nehaal-raj/SOP_4_1/SNN_EMG/constraint/fp/SNN_derived_constraints.pdc}
