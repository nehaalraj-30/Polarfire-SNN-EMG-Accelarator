`timescale 1ns / 1ps

// Layer 2: 128 input spikes -> 64 LIF neurons, evaluated each timestep.
// Weight layout: weight_matrix[j*OUT_SIZE+i] = W2[i,j].
module layer_if_neuron_II #(
    parameter IN_SIZE = 128,
    parameter OUT_SIZE = 64,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32,
    parameter signed [ACC_WIDTH-1:0] VTH = 32'sd96,
    parameter signed [ACC_WIDTH-1:0] VINIT = 32'sd48,
    parameter LEAK_SHIFT = 3
)(
    input wire clk,
    input wire rst_n,
    input wire step_tick,   // one pulse from Layer 1 layer_done each timestep
    input wire clear_accum, // initialize membrane before a new frame
    input wire [IN_SIZE-1:0] spikes_in,
    output reg [OUT_SIZE-1:0] spikes_out,
    output reg layer_done
);
    // Small 8192-byte constant weight table; parallel combinational reads.
    (* syn_ramstyle = "registers" *)
    reg signed [DATA_WIDTH-1:0] weight_matrix [0:IN_SIZE*OUT_SIZE-1];

    // Model biases are signed INT32, not INT8.
    (* syn_ramstyle = "registers" *)
    reg signed [ACC_WIDTH-1:0] bias_array [0:OUT_SIZE-1];

    reg signed [ACC_WIDTH-1:0] v_mem [0:OUT_SIZE-1];

    integer i, j;
    reg signed [ACC_WIDTH-1:0] syn_input;
    reg signed [ACC_WIDTH-1:0] v_next;

    initial begin
        $readmemh("layer2_weights.mem", weight_matrix);
        $readmemh("layer2_biases.mem", bias_array);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spikes_out <= {OUT_SIZE{1'b0}};
            layer_done <= 1'b0;
            for (i = 0; i < OUT_SIZE; i = i + 1)
                v_mem[i] <= VINIT;
        end else if (clear_accum) begin
            spikes_out <= {OUT_SIZE{1'b0}};
            layer_done <= 1'b0;
            for (i = 0; i < OUT_SIZE; i = i + 1)
                v_mem[i] <= VINIT;
        end else begin
            layer_done <= 1'b0;
            if (step_tick) begin
                for (i = 0; i < OUT_SIZE; i = i + 1) begin
                    syn_input = {ACC_WIDTH{1'b0}};
                    for (j = 0; j < IN_SIZE; j = j + 1) begin
                        if (spikes_in[j])
                            syn_input = syn_input + $signed(weight_matrix[j*OUT_SIZE+i]);
                    end
                    // Python: v2 -= v2 >> 3; v2 += W2 @ s1 + b2
                    v_next = v_mem[i] - (v_mem[i] >>> LEAK_SHIFT)
                             + syn_input + bias_array[i];
                    if (v_next >= VTH) begin
                        spikes_out[i] <= 1'b1;
                        v_mem[i] <= v_next - VTH;
                    end else begin
                        spikes_out[i] <= 1'b0;
                        v_mem[i] <= v_next;
                    end
                end
                layer_done <= 1'b1;
            end
        end
    end
endmodule
