//////////////////////////////////////////////////////////////////////
// Created by SmartDesign Tue Oct 27 17:16:36 2026
// Version: 2026.1 2026.1.0.17
//////////////////////////////////////////////////////////////////////

`timescale 1ns / 100ps

// SNN
module SNN(
    // Inputs
    REF_CLK_0,
    RX,
    rst_n,
    // Outputs
    TX,
    inference_led,
    latched_brake_trigger,
    latched_non_brake_trigger
);

//--------------------------------------------------------------------
// Input
//--------------------------------------------------------------------
input  REF_CLK_0;
input  RX;
input  rst_n;
//--------------------------------------------------------------------
// Output
//--------------------------------------------------------------------
output TX;
output inference_led;
output latched_brake_trigger;
output latched_non_brake_trigger;
//--------------------------------------------------------------------
// Nets
//--------------------------------------------------------------------
wire   [719:0]  ADAS_BUFFER_0_context_flat;
wire            ADAS_BUFFER_0_context_full;
wire            CLKINT_0_Y;
wire   [7:0]    COREUART_C0_0_DATA_OUT;
wire            COREUART_C0_0_RXRDY;
wire            COREUART_C0_0_TXRDY;
wire   [2399:0] emgBuffer_0_flat_samples_out_0;
wire            emgBuffer_0_snn_start;
wire            inference_led_net_0;
wire   [31:0]   inference_perf_counter_0_inference_cycles;
wire   [3119:0] INPUT_COMBINER_0_snn_input;
wire            INPUT_READY_0_combined_snn_start;
wire            latched_brake_trigger_net_0;
wire            latched_inference_done;
wire            latched_non_brake_trigger_net_0;
wire   [31:0]   latched_readout_score;
wire            layer_if_neuron_0_current_done;
wire            layer_if_neuron_0_layer_done;
wire   [127:0]  layer_if_neuron_0_spikes_out;
wire            layer_if_neuron_II_0_layer_done;
wire   [63:0]   layer_if_neuron_II_0_spikes_out;
wire            layer_if_neuron_III_0_layer_done;
wire   [31:0]   layer_if_neuron_III_0_readout_score;
wire            PF_CCC_C0_0_OUT0_FABCLK_0;
wire            PF_CCC_C0_0_PLL_LOCK_0;
wire            REF_CLK_0;
wire            reset_0_rst_n_global;
wire            rst_n;
wire            RX;
wire   [7:0]    SNN_UART_REPORTER_0_uart_data_in;
wire            SNN_UART_REPORTER_0_uart_wen_n;
wire            snnController_0_clear_accum;
wire            snnController_0_current_start;
wire            snnController_0_frame_clear_0;
wire            snnController_0_inference_done;
wire            snnController_0_step_tick;
wire            TX_net_0;
wire   [7:0]    uart_emg_bridge_0_sample_data;
wire            uart_emg_bridge_0_sample_valid;
wire            uart_emg_bridge_0_uart_oen_n;
wire   [7:0]    UART_INPUT_ROUTER_0_adas_data;
wire            UART_INPUT_ROUTER_0_adas_valid;
wire   [7:0]    UART_INPUT_ROUTER_0_emg_data;
wire            UART_INPUT_ROUTER_0_emg_valid;
wire            latched_brake_trigger_net_1;
wire            latched_non_brake_trigger_net_1;
wire            inference_led_net_1;
wire            TX_net_1;
//--------------------------------------------------------------------
// TiedOff Nets
//--------------------------------------------------------------------
wire            VCC_net;
wire            GND_net;
wire   [12:0]   BAUD_VAL_const_net_0;
wire   [2:0]    BAUD_VAL_FRACTION_const_net_0;
//--------------------------------------------------------------------
// Constant assignments
//--------------------------------------------------------------------
assign VCC_net                       = 1'b1;
assign GND_net                       = 1'b0;
assign BAUD_VAL_const_net_0          = 13'h001A;
assign BAUD_VAL_FRACTION_const_net_0 = 3'h1;
//--------------------------------------------------------------------
// Top level output port assignments
//--------------------------------------------------------------------
assign latched_brake_trigger_net_1     = latched_brake_trigger_net_0;
assign latched_brake_trigger           = latched_brake_trigger_net_1;
assign latched_non_brake_trigger_net_1 = latched_non_brake_trigger_net_0;
assign latched_non_brake_trigger       = latched_non_brake_trigger_net_1;
assign inference_led_net_1             = inference_led_net_0;
assign inference_led                   = inference_led_net_1;
assign TX_net_1                        = TX_net_0;
assign TX                              = TX_net_1;
//--------------------------------------------------------------------
// Component instances
//--------------------------------------------------------------------
//--------ADAS_BUFFER
ADAS_BUFFER ADAS_BUFFER_0(
        // Inputs
        .clk          ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .rst_n        ( reset_0_rst_n_global ),
        .adas_valid   ( UART_INPUT_ROUTER_0_adas_valid ),
        .frame_clear  ( snnController_0_frame_clear_0 ),
        .adas_data    ( UART_INPUT_ROUTER_0_adas_data ),
        // Outputs
        .context_full ( ADAS_BUFFER_0_context_full ),
        .context_flat ( ADAS_BUFFER_0_context_flat ) 
        );

//--------CLKINT
CLKINT CLKINT_0(
        // Inputs
        .A ( REF_CLK_0 ),
        // Outputs
        .Y ( CLKINT_0_Y ) 
        );

//--------COREUART_C0
COREUART_C0 COREUART_C0_0(
        // Inputs
        .BIT8              ( VCC_net ),
        .CLK               ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .CSN               ( GND_net ),
        .ODD_N_EVEN        ( GND_net ),
        .OEN               ( uart_emg_bridge_0_uart_oen_n ),
        .PARITY_EN         ( GND_net ),
        .RESET_N           ( reset_0_rst_n_global ),
        .RX                ( RX ),
        .WEN               ( SNN_UART_REPORTER_0_uart_wen_n ),
        .BAUD_VAL          ( BAUD_VAL_const_net_0 ),
        .DATA_IN           ( SNN_UART_REPORTER_0_uart_data_in ),
        .BAUD_VAL_FRACTION ( BAUD_VAL_FRACTION_const_net_0 ),
        // Outputs
        .OVERFLOW          (  ),
        .PARITY_ERR        (  ),
        .RXRDY             ( COREUART_C0_0_RXRDY ),
        .TX                ( TX_net_0 ),
        .TXRDY             ( COREUART_C0_0_TXRDY ),
        .FRAMING_ERR       (  ),
        .DATA_OUT          ( COREUART_C0_0_DATA_OUT ) 
        );

//--------emgBuffer
emgBuffer emgBuffer_0(
        // Inputs
        .clk              ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .rst_n            ( reset_0_rst_n_global ),
        .sample_valid     ( UART_INPUT_ROUTER_0_emg_valid ),
        .frame_clear      ( snnController_0_frame_clear_0 ),
        .sample_in        ( UART_INPUT_ROUTER_0_emg_data ),
        // Outputs
        .snn_start        ( emgBuffer_0_snn_start ),
        .flat_samples_out ( emgBuffer_0_flat_samples_out_0 ) 
        );

//--------inference_perf_counter
inference_perf_counter inference_perf_counter_0(
        // Inputs
        .clk               ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .rst_n             ( reset_0_rst_n_global ),
        .inference_start   ( snnController_0_current_start ),
        .inference_done    ( snnController_0_inference_done ),
        // Outputs
        .measurement_valid (  ),
        .counting          (  ),
        .inference_cycles  ( inference_perf_counter_0_inference_cycles ) 
        );

//--------INPUT_COMBINER
INPUT_COMBINER INPUT_COMBINER_0(
        // Inputs
        .emg_flat     ( emgBuffer_0_flat_samples_out_0 ),
        .context_flat ( ADAS_BUFFER_0_context_flat ),
        // Outputs
        .snn_input    ( INPUT_COMBINER_0_snn_input ) 
        );

//--------INPUT_READY
INPUT_READY INPUT_READY_0(
        // Inputs
        .clk                ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .rst_n              ( reset_0_rst_n_global ),
        .emg_snn_start      ( emgBuffer_0_snn_start ),
        .context_full       ( ADAS_BUFFER_0_context_full ),
        .frame_clear        ( snnController_0_frame_clear_0 ),
        // Outputs
        .combined_snn_start ( INPUT_READY_0_combined_snn_start ) 
        );

//--------layer_if_neuron
layer_if_neuron layer_if_neuron_0(
        // Inputs
        .clk           ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .rst_n         ( reset_0_rst_n_global ),
        .current_start ( snnController_0_current_start ),
        .step_tick     ( snnController_0_step_tick ),
        .clear_accum   ( snnController_0_clear_accum ),
        .samples_in    ( INPUT_COMBINER_0_snn_input ),
        // Outputs
        .current_done  ( layer_if_neuron_0_current_done ),
        .layer_done    ( layer_if_neuron_0_layer_done ),
        .spikes_out    ( layer_if_neuron_0_spikes_out ) 
        );

//--------layer_if_neuron_II
layer_if_neuron_II layer_if_neuron_II_0(
        // Inputs
        .clk         ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .rst_n       ( reset_0_rst_n_global ),
        .step_tick   ( layer_if_neuron_0_layer_done ),
        .clear_accum ( snnController_0_clear_accum ),
        .spikes_in   ( layer_if_neuron_0_spikes_out ),
        // Outputs
        .layer_done  ( layer_if_neuron_II_0_layer_done ),
        .spikes_out  ( layer_if_neuron_II_0_spikes_out ) 
        );

//--------layer_if_neuron_III
layer_if_neuron_III layer_if_neuron_III_0(
        // Inputs
        .clk           ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .rst_n         ( reset_0_rst_n_global ),
        .step_tick     ( layer_if_neuron_II_0_layer_done ),
        .clear_accum   ( snnController_0_clear_accum ),
        .spikes_in     ( layer_if_neuron_II_0_spikes_out ),
        // Outputs
        .layer_done    ( layer_if_neuron_III_0_layer_done ),
        .readout_score ( layer_if_neuron_III_0_readout_score ) 
        );

//--------Not_gate
Not_gate Not_gate_0(
        // Inputs
        .latched_brake_trigger     ( latched_brake_trigger_net_0 ),
        // Outputs
        .latched_non_brake_trigger ( latched_non_brake_trigger_net_0 ) 
        );

//--------PF_CCC_C0
PF_CCC_C0 PF_CCC_C0_0(
        // Inputs
        .REF_CLK_0     ( CLKINT_0_Y ),
        // Outputs
        .OUT0_FABCLK_0 ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .PLL_LOCK_0    ( PF_CCC_C0_0_PLL_LOCK_0 ) 
        );

//--------reset
reset reset_0(
        // Inputs
        .rst_n        ( rst_n ),
        .lock         ( PF_CCC_C0_0_PLL_LOCK_0 ),
        // Outputs
        .rst_n_global ( reset_0_rst_n_global ) 
        );

//--------snn_output_latch
snn_output_latch snn_output_latch_0(
        // Inputs
        .clk                    ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .rst_n                  ( reset_0_rst_n_global ),
        .inference_done_in      ( snnController_0_inference_done ),
        .raw_readout_score      ( layer_if_neuron_III_0_readout_score ),
        // Outputs
        .latched_brake_trigger  ( latched_brake_trigger_net_0 ),
        .latched_inference_done ( latched_inference_done ),
        .inference_led          ( inference_led_net_0 ),
        .latched_readout_score  ( latched_readout_score ) 
        );

//--------SNN_UART_REPORTER
SNN_UART_REPORTER SNN_UART_REPORTER_0(
        // Inputs
        .clk                    ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .rst_n                  ( reset_0_rst_n_global ),
        .latched_inference_done ( latched_inference_done ),
        .latched_brake_trigger  ( latched_brake_trigger_net_0 ),
        .txrdy                  ( COREUART_C0_0_TXRDY ),
        .latched_readout_score  ( latched_readout_score ),
        .inference_cycles       ( inference_perf_counter_0_inference_cycles ),
        // Outputs
        .uart_wen_n             ( SNN_UART_REPORTER_0_uart_wen_n ),
        .reporter_busy          (  ),
        .packet_queued          (  ),
        .report_overrun         (  ),
        .uart_data_in           ( SNN_UART_REPORTER_0_uart_data_in ) 
        );

//--------snnController
snnController snnController_0(
        // Inputs
        .clk                 ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .rst_n               ( reset_0_rst_n_global ),
        .snn_start           ( INPUT_READY_0_combined_snn_start ),
        .layer1_current_done ( layer_if_neuron_0_current_done ),
        .layer3_done         ( layer_if_neuron_III_0_layer_done ),
        // Outputs
        .current_start       ( snnController_0_current_start ),
        .step_tick           ( snnController_0_step_tick ),
        .clear_accum         ( snnController_0_clear_accum ),
        .inference_done      ( snnController_0_inference_done ),
        .frame_clear         ( snnController_0_frame_clear_0 ) 
        );

//--------uart_emg_bridge
uart_emg_bridge uart_emg_bridge_0(
        // Inputs
        .clk          ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .rst_n        ( reset_0_rst_n_global ),
        .rxrdy        ( COREUART_C0_0_RXRDY ),
        .uart_data    ( COREUART_C0_0_DATA_OUT ),
        // Outputs
        .uart_oen_n   ( uart_emg_bridge_0_uart_oen_n ),
        .sample_valid ( uart_emg_bridge_0_sample_valid ),
        .sample_data  ( uart_emg_bridge_0_sample_data ) 
        );

//--------UART_INPUT_ROUTER
UART_INPUT_ROUTER UART_INPUT_ROUTER_0(
        // Inputs
        .clk         ( PF_CCC_C0_0_OUT0_FABCLK_0 ),
        .rst_n       ( reset_0_rst_n_global ),
        .uart_valid  ( uart_emg_bridge_0_sample_valid ),
        .frame_clear ( snnController_0_frame_clear_0 ),
        .uart_data   ( uart_emg_bridge_0_sample_data ),
        // Outputs
        .emg_valid   ( UART_INPUT_ROUTER_0_emg_valid ),
        .adas_valid  ( UART_INPUT_ROUTER_0_adas_valid ),
        .emg_data    ( UART_INPUT_ROUTER_0_emg_data ),
        .adas_data   ( UART_INPUT_ROUTER_0_adas_data ) 
        );


endmodule
