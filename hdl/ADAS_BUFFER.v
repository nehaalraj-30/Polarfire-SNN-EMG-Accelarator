module ADAS_BUFFER (
    input  wire clk,
    input  wire rst_n,

    input  wire [7:0] adas_data,
    input  wire       adas_valid,

    // Reset the frame counter before loading another ADAS vector
    input  wire       frame_clear,

    // 90 x 8 = 720 bits
    output wire [719:0] context_flat,

    // HIGH after all 90 ADAS bytes have been received
    output reg         context_full
);

    reg [7:0] adas_buffer [0:89];

    // 7 bits required to count from 0 to 89
    reg [6:0] sample_count;

    integer i;
    genvar j;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            sample_count <= 7'd0;
            context_full <= 1'b0;

            for (i = 0; i < 90; i = i + 1)
                adas_buffer[i] <= 8'd0;

        end

        else if (frame_clear) begin

            sample_count <= 7'd0;
            context_full <= 1'b0;

            // No need to clear the entire memory.
            // New frame will overwrite all 90 locations.

        end

        else if (adas_valid && !context_full) begin

            // Store incoming bytes in the exact received order
            adas_buffer[sample_count] <= adas_data;

            if (sample_count == 7'd89) begin

                context_full <= 1'b1;

            end
            else begin

                sample_count <= sample_count + 1'b1;

            end

        end

    end

    // Pack all 90 bytes into the output bus
    generate
        for (j = 0; j < 90; j = j + 1) begin

            assign context_flat[j*8 +: 8] = adas_buffer[j];

        end
    endgenerate

endmodule