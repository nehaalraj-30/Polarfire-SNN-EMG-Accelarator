`timescale 1ns / 1ps

module emgBuffer #(
    parameter IN_SAMPLES = 300,
    parameter DATA_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,

    // From UART_INPUT_ROUTER
    input  wire [DATA_WIDTH-1:0] sample_in,
    input  wire                  sample_valid,

    // From snnController
    input  wire frame_clear,

    // Flattened EMG samples
    output wire [IN_SAMPLES*DATA_WIDTH-1:0] flat_samples_out,

    // Pulses when 300 samples are received
    output reg snn_start
);

    reg [DATA_WIDTH-1:0] mem [0:IN_SAMPLES-1];

    reg [8:0] fill_count;
    reg       buffer_full;

    integer i;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            fill_count  <= 9'd0;
            buffer_full <= 1'b0;
            snn_start   <= 1'b0;

            for (i = 0; i < IN_SAMPLES; i = i + 1)
                mem[i] <= {DATA_WIDTH{1'b0}};

        end

        else if (frame_clear) begin

            // Rearm the buffer for a new 300-byte frame
            fill_count  <= 9'd0;
            buffer_full <= 1'b0;
            snn_start   <= 1'b0;

            // Do not clear mem[].
            // The next frame overwrites all 300 samples.

        end

        else begin

            snn_start <= 1'b0;

            // Accept samples only until the frame is complete
            if (sample_valid && !buffer_full) begin

                // Shift old samples toward index 0
                for (i = 0; i < IN_SAMPLES-1; i = i + 1)
                    mem[i] <= mem[i+1];

                // Insert newest sample
                mem[IN_SAMPLES-1] <= sample_in;

                // Track initial filling
                if (fill_count == IN_SAMPLES-1) begin

                    buffer_full <= 1'b1;
                    snn_start   <= 1'b1;

                end
                else begin

                    fill_count <= fill_count + 1'b1;

                end

            end

        end

    end

    // Flatten EMG buffer
    genvar k;

    generate
        for (k = 0; k < IN_SAMPLES; k = k + 1) begin : GEN_OUTPUT

            assign flat_samples_out[
                k*DATA_WIDTH +: DATA_WIDTH
            ] = mem[k];

        end
    endgenerate

endmodule