`timescale 1ns / 1ps

// Layer 3: signed non-spiking readout with three pipeline stages.
// Optimized for 64 input spikes with a balanced narrow-width reduction.
//
// Stage 1: 8 groups of 8 weights -> 8 registered partial sums.
// Stage 2: combine groups, add bias -> registered signed current.
// Stage 3: accumulate into 32-bit readout, pulse layer_done.
//
// One step_tick is accepted when the pipeline is idle.
// The controller must wait for layer_done before starting the next step.
// clear_accum cancels any pending operation and resets readout.

module layer_if_neuron_III #(
    parameter IN_SIZE    = 64,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire clk,
    input  wire rst_n,
    input  wire step_tick,
    input  wire clear_accum,
    input  wire [IN_SIZE-1:0] spikes_in,
    output wire signed [ACC_WIDTH-1:0] readout_score,
    output reg layer_done
);
    localparam GROUPS = 8;
    localparam GROUP_SIZE = 8;
    localparam PART_WIDTH = DATA_WIDTH + 3; // 8 signed weights -> 11 bits
    localparam SUM_WIDTH  = DATA_WIDTH + 6; // 64 signed weights -> 14 bits

    // IN_SIZE must be 1..64; ACC_WIDTH must be >= SUM_WIDTH.
    (* syn_ramstyle = "registers" *)
    reg signed [DATA_WIDTH-1:0] weight_matrix [0:IN_SIZE-1];
    reg signed [ACC_WIDTH-1:0] bias_array [0:0];

    initial begin
        $readmemh("layer3_weights.mem", weight_matrix);
        $readmemh("layer3_biases.mem", bias_array);
    end

    wire signed [PART_WIDTH-1:0] partial_comb [0:GROUPS-1];
    reg  signed [PART_WIDTH-1:0] partial_reg  [0:GROUPS-1];

    // assigning groups of 8 for 8 spikes 
    genvar g, k;
    generate
        for (g = 0; g < GROUPS; g = g + 1) begin : G_GROUP
            wire signed [DATA_WIDTH-1:0] w [0:7];
            for (k = 0; k < GROUP_SIZE; k = k + 1) begin : G_WEIGHT
                if ((g*GROUP_SIZE + k) < IN_SIZE) begin : G_PRESENT
                    assign w[k] = spikes_in[g*GROUP_SIZE+k]
                                ? weight_matrix[g*GROUP_SIZE+k]
                                : {DATA_WIDTH{1'b0}};
                end else begin : G_PAD
                    assign w[k] = {DATA_WIDTH{1'b0}};
                end
            end

            // Binary reduction tree: 8 -> 4 -> 2 -> 1.
            wire signed [DATA_WIDTH:0]   pair0, pair1, pair2, pair3;
            wire signed [DATA_WIDTH+1:0] quad0, quad1;
            assign pair0 = $signed(w[0]) + $signed(w[1]);
            assign pair1 = $signed(w[2]) + $signed(w[3]);
            assign pair2 = $signed(w[4]) + $signed(w[5]);
            assign pair3 = $signed(w[6]) + $signed(w[7]);
            assign quad0 = $signed(pair0) + $signed(pair1);
            assign quad1 = $signed(pair2) + $signed(pair3);
            assign partial_comb[g] = $signed(quad0) + $signed(quad1);
        end
    endgenerate

    // Stage 2: balanced 8-to-1 reduction, with exact signed widths.
    wire signed [PART_WIDTH:0]   sum2_0, sum2_1, sum2_2, sum2_3;
    wire signed [PART_WIDTH+1:0] sum4_0, sum4_1;
    wire signed [SUM_WIDTH-1:0]  sum8;

    assign sum2_0 = $signed(partial_reg[0]) + $signed(partial_reg[1]);
    assign sum2_1 = $signed(partial_reg[2]) + $signed(partial_reg[3]);
    assign sum2_2 = $signed(partial_reg[4]) + $signed(partial_reg[5]);
    assign sum2_3 = $signed(partial_reg[6]) + $signed(partial_reg[7]);
    assign sum4_0 = $signed(sum2_0) + $signed(sum2_1);
    assign sum4_1 = $signed(sum2_2) + $signed(sum2_3);
    assign sum8   = $signed(sum4_0) + $signed(sum4_1);

    reg signed [ACC_WIDTH-1:0] syn_input_reg;
    reg signed [ACC_WIDTH-1:0] readout;
    reg stage1_valid;
    reg stage2_valid;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < GROUPS; i = i + 1)
                partial_reg[i] <= {PART_WIDTH{1'b0}};
            syn_input_reg <= {ACC_WIDTH{1'b0}};
            readout       <= {ACC_WIDTH{1'b0}};
            stage1_valid  <= 1'b0;
            stage2_valid  <= 1'b0;
            layer_done    <= 1'b0;
        end else if (clear_accum) begin
            for (i = 0; i < GROUPS; i = i + 1)
                partial_reg[i] <= {PART_WIDTH{1'b0}};
            syn_input_reg <= {ACC_WIDTH{1'b0}};
            readout       <= {ACC_WIDTH{1'b0}};
            stage1_valid  <= 1'b0;
            stage2_valid  <= 1'b0;
            layer_done    <= 1'b0;
        end else begin
            layer_done <= 1'b0;

            // Stage 3: accumulator update; done reports actual readout update.
            if (stage2_valid) begin
                readout    <= readout + syn_input_reg;
                layer_done <= 1'b1;
            end

            // Stage 2: narrow sum sign-extends to accumulator width.
            if (stage1_valid)
                syn_input_reg <= $signed(sum8) + bias_array[0];

            // Stage 1: snapshot all spikes at the accepted step_tick.
            if (step_tick && !stage1_valid && !stage2_valid) begin
                for (i = 0; i < GROUPS; i = i + 1)
                    partial_reg[i] <= partial_comb[i];
                stage1_valid <= 1'b1;
            end else begin
                stage1_valid <= 1'b0;
            end

            stage2_valid <= stage1_valid;
        end
    end

    assign readout_score = readout;
endmodule
