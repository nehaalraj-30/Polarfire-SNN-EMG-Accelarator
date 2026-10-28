`timescale 1ns / 1ps

module rateEncoder #(
    parameter IN_SAMPLES = 300,
    parameter DATA_WIDTH = 8,
    parameter VTH        = 16'sd127
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              step_tick,          // Controller input strobe
    input  wire [IN_SAMPLES*DATA_WIDTH-1:0]  flat_samples_in,    // Packed parallel input bus
    output reg  [IN_SAMPLES-1:0]             spikes_out          // 300-bit parallel spike vector
);

    // Use 16-bit registers for accumulator calculations to prevent context truncation
    reg signed [15:0] acc [0:IN_SAMPLES-1];
    reg signed [15:0] sum_temp;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spikes_out <= {IN_SAMPLES{1'b0}};
            for (i = 0; i < IN_SAMPLES; i = i + 1) begin
                acc[i] <= 16'sd63; // Q7 midpoint init
            end
        end else if (step_tick) begin
            for (i = 0; i < IN_SAMPLES; i = i + 1) begin
                // Compute sum in 16-bit context to prevent 7-bit truncation wrap-around
                sum_temp = acc[i] + $signed({1'b0, flat_samples_in[i*DATA_WIDTH +: DATA_WIDTH]});
                
                if (sum_temp >= VTH) begin
                    spikes_out[i] <= 1'b1;
                    acc[i]        <= sum_temp - VTH;
                end else begin
                    spikes_out[i] <= 1'b0;
                    acc[i]        <= sum_temp;
                end
            end
        end
        // NOTE: The 'else' block clearing spikes_out has been removed.
        // spikes_out remains latched across all 300 cycles until the next step_tick.
    end

endmodule