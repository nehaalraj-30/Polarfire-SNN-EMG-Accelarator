`timescale 1ns / 1ps

// Layer 1 of single-member 390 -> 128 -> 64 -> 1 integer LIF network.
// The input current is computed ONCE per frame, then reused for T=8 LIF steps.
module layer_if_neuron #(
    parameter IN_SIZE = 390,
    parameter OUT_SIZE = 128,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32,
    parameter signed [ACC_WIDTH-1:0] VTH = 32'sd23540,
    parameter signed [ACC_WIDTH-1:0] VINIT = 32'sd11770
)(
    input  wire clk,
    input  wire rst_n,
    input  wire current_start,  // once per inference: begin 390x128 MAC
    input  wire step_tick,      // eight times per inference: one LIF update
    input  wire clear_accum,    // initialize membranes before new inference
    input  wire [IN_SIZE*DATA_WIDTH-1:0] samples_in,
    output reg  [OUT_SIZE-1:0] spikes_out,
    output reg  current_done,  // one clock pulse after all MAC rows accumulated
    output reg  layer_done     // one clock pulse after LIF step
);
    localparam LINE_WIDTH = OUT_SIZE * DATA_WIDTH;
    localparam S_IDLE  = 2'd0;
    localparam S_FETCH = 2'd1;
    localparam S_MAC   = 2'd2;
    reg [1:0] state;

    // Row k contains the weights W1[0:OUT_SIZE-1, k].
    // Explicitly request LSRAM, matching the working prior layer.
    (* syn_romstyle = "lsram" *)
    reg [LINE_WIDTH-1:0] weight_rom [0:IN_SIZE-1];
    reg [LINE_WIDTH-1:0] weight_row_reg;

    // Signed 32-bit biases from the trained model.
    reg signed [ACC_WIDTH-1:0] bias_array [0:OUT_SIZE-1];

    reg signed [ACC_WIDTH-1:0] current [0:OUT_SIZE-1];
    reg signed [ACC_WIDTH-1:0] v_mem   [0:OUT_SIZE-1];
    reg [8:0] input_idx; // 0 ... 389

    reg [7:0] x_reg;
    reg signed [7:0] w_temp;
    reg signed [16:0] product_temp;
    reg signed [ACC_WIDTH-1:0] v_next;
    integer i;

    initial begin
        $readmemh("layer1_weights_packed.mem", weight_rom);
        $readmemh("layer1_biases.mem", bias_array);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            input_idx <= 9'd0;
            weight_row_reg <= {LINE_WIDTH{1'b0}};
            x_reg <= 8'd0;
            spikes_out <= {OUT_SIZE{1'b0}};
            current_done <= 1'b0;
            layer_done <= 1'b0;
            for (i = 0; i < OUT_SIZE; i = i + 1) begin
                current[i] <= {ACC_WIDTH{1'b0}};
                v_mem[i] <= VINIT;
            end
        end else begin
            current_done <= 1'b0;
            layer_done <= 1'b0;

            if (clear_accum) begin
                state <= S_IDLE;
                input_idx <= 9'd0;
                spikes_out <= {OUT_SIZE{1'b0}};
                for (i = 0; i < OUT_SIZE; i = i + 1) begin
                    current[i] <= {ACC_WIDTH{1'b0}};
                    v_mem[i] <= VINIT;
                end
            end else begin
                case (state)
                    S_IDLE: begin
                        if (current_start) begin
                            input_idx <= 9'd0;
                            for (i = 0; i < OUT_SIZE; i = i + 1)
                                current[i] <= bias_array[i];
                            state <= S_FETCH;
                        end else if (step_tick) begin
                            // Arithmetic right shift reproduces Python's signed >> 3.
                            // Evaluate threshold AFTER leak + held input current.
                            for (i = 0; i < OUT_SIZE; i = i + 1) begin
                                v_next = v_mem[i] - (v_mem[i] >>> 3) + current[i];
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
                    S_FETCH: begin
                        // Synchronous ROM read and feature capture.
                        weight_row_reg <= weight_rom[input_idx];
                        x_reg <= samples_in[input_idx*DATA_WIDTH +: DATA_WIDTH];
                        state <= S_MAC;
                    end
                    S_MAC: begin
                        // 128 signed INT8 weights times the same unsigned input byte.
                        // One entire input row is accumulated in this clock.
                        for (i = 0; i < OUT_SIZE; i = i + 1) begin
                            w_temp = $signed(weight_row_reg[i*DATA_WIDTH +: DATA_WIDTH]);
                            product_temp = $signed({1'b0, x_reg}) * w_temp;
                            current[i] <= current[i] + product_temp;
                        end
                        if (input_idx == IN_SIZE - 1) begin
                            current_done <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            input_idx <= input_idx + 1'b1;
                            state <= S_FETCH;
                        end
                    end
                    default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule
