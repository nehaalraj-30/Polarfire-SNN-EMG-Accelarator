`timescale 1ns / 1ps

module INPUT_READY (
    input  wire clk,
    input  wire rst_n,

    // From emgBuffer
    input  wire emg_snn_start,

    // From ADAS_BUFFER
    input  wire context_full,

    // Clear before loading another frame
    input  wire frame_clear,

    // To snnController
    output wire combined_snn_start
);

    reg emg_full;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n)
            emg_full <= 1'b0;

        else if (frame_clear)
            emg_full <= 1'b0;

        else if (emg_snn_start)
            emg_full <= 1'b1;

    end

    assign combined_snn_start = emg_full && context_full;

endmodule