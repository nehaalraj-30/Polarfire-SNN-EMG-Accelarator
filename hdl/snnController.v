`timescale 1ns / 1ps

module snnController #(
    parameter TIMESTEPS = 8
)(
    input  wire clk,
    input  wire rst_n,

    // Complete 390-input frame available
    input  wire snn_start,

    // Layer 1 initial MAC completion
    input  wire layer1_current_done,

    // Layer 3 completion for each timestep
    input  wire layer3_done,

    // Layer 1 initial current computation
    output reg  current_start,

    // Trigger each SNN timestep
    output reg  step_tick,

    // Reset LIF states and readout accumulator
    output reg  clear_accum,

    // Complete inference notification
    output reg  inference_done,

    // Rearm input buffers and UART router
    output reg  frame_clear
);

    localparam IDLE          = 3'd0;
    localparam CLEAR         = 3'd1;
    localparam START_CURRENT = 3'd2;
    localparam WAIT_CURRENT  = 3'd3;
    localparam START_STEP    = 3'd4;
    localparam WAIT_STEP     = 3'd5;
    localparam DONE          = 3'd6;
    localparam FRAME_CLEAR   = 3'd7;

    reg [2:0] state;
    reg [7:0] step_count;

    // Rising-edge detection for snn_start
    reg snn_start_d;

    wire start_pulse;

    assign start_pulse = snn_start && !snn_start_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            snn_start_d <= 1'b0;
        else
            snn_start_d <= snn_start;
    end

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state          <= IDLE;
            step_count     <= 8'd0;

            current_start  <= 1'b0;
            step_tick      <= 1'b0;
            clear_accum    <= 1'b0;
            inference_done <= 1'b0;
            frame_clear    <= 1'b0;

        end
        else begin

            // Default: all control outputs are one-cycle pulses
            current_start  <= 1'b0;
            step_tick      <= 1'b0;
            clear_accum    <= 1'b0;
            inference_done <= 1'b0;
            frame_clear    <= 1'b0;

            case (state)

                // Wait for new input frame
                IDLE: begin

                    if (start_pulse) begin
                        step_count <= 8'd0;
                        state      <= CLEAR;
                    end

                end

                // Initialize membrane potentials
                CLEAR: begin

                    clear_accum <= 1'b1;
                    state       <= START_CURRENT;

                end

                // Calculate Layer 1 currents once
                START_CURRENT: begin

                    current_start <= 1'b1;
                    state         <= WAIT_CURRENT;

                end

                // Wait for Layer 1 MAC
                WAIT_CURRENT: begin

                    if (layer1_current_done)
                        state <= START_STEP;

                end

                // Start SNN timestep
                START_STEP: begin

                    step_tick <= 1'b1;
                    state     <= WAIT_STEP;

                end

                // Wait for Layer 3 to finish timestep
                WAIT_STEP: begin

                    if (layer3_done) begin

                        if (step_count == TIMESTEPS - 1) begin
                            state <= DONE;
                        end
                        else begin
                            step_count <= step_count + 1'b1;
                            state      <= START_STEP;
                        end

                    end

                end

                // Inference complete
                DONE: begin

                    inference_done <= 1'b1;
                    state          <= FRAME_CLEAR;

                end

                // Rearm inputs for the next frame
                FRAME_CLEAR: begin

                    frame_clear <= 1'b1;
                    state       <= IDLE;

                end

                default: state <= IDLE;

            endcase

        end

    end

endmodule