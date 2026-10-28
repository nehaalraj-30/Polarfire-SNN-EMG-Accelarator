`timescale 1ns/1ps
// Counts system-clock cycles from launch of L1 current computation
// to the controller's inference_done pulse (inclusive).
// Connect start to snnController.current_start, done to
// snnController.inference_done; both in the SAME clock domain.
module inference_perf_counter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        inference_start,
    input  wire        inference_done,
    output reg  [31:0] inference_cycles,
    output reg         measurement_valid,
    output reg         counting
);
    reg [31:0] elapsed;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            elapsed           <= 32'd0;
            inference_cycles  <= 32'd0;
            measurement_valid <= 1'b0;
            counting          <= 1'b0;
        end else begin
            measurement_valid <= 1'b0;
            if (inference_start) begin
                elapsed  <= 32'd0;
                counting <= 1'b1;
            end else if (inference_done && counting) begin
                // Counts start-to-done inclusive (elapsed increments on
                // every intervening posedge, then add the closing edge).
                inference_cycles  <= elapsed + 32'd1;
                measurement_valid <= 1'b1;
                counting          <= 1'b0;
            end else if (counting) begin
                elapsed <= elapsed + 32'd1;
            end
        end
    end
endmodule
