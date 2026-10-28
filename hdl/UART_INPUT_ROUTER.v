module UART_INPUT_ROUTER (
    input  wire       clk,
    input  wire       rst_n,

    // From uart_emg_bridge
    input  wire [7:0] uart_data,
    input  wire       uart_valid,

    // Reset the router before a new 390-byte frame
    input  wire       frame_clear,

    // To existing emgBuffer
    output reg  [7:0] emg_data,
    output reg        emg_valid,

    // To modified ADAS_BUFFER
    output reg  [7:0] adas_data,
    output reg        adas_valid

);

    // 9 bits can represent counts 0 through 390
    reg [8:0] byte_count;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin
            byte_count     <= 9'd0;

            emg_data       <= 8'd0;
            emg_valid      <= 1'b0;

            adas_data      <= 8'd0;
            adas_valid     <= 1'b0;

        end

        else if (frame_clear) begin
            byte_count     <= 9'd0;

            emg_data       <= 8'd0;
            emg_valid      <= 1'b0;

            adas_data      <= 8'd0;
            adas_valid     <= 1'b0;

 
        end

        else begin

            // Default: one-clock valid pulses
            emg_valid  <= 1'b0;
            adas_valid <= 1'b0;

            if (uart_valid) begin

                // Bytes 0–299: EMG
                if (byte_count < 9'd300) begin

                    emg_data  <= uart_data;
                    emg_valid <= 1'b1;

                    byte_count <= byte_count + 1'b1;
                end

                // Bytes 300–389: ADAS
                else if (byte_count < 9'd390) begin

                    adas_data  <= uart_data;
                    adas_valid <= 1'b1;

                    byte_count <= byte_count + 1'b1;
                end

            end

        end
    end

endmodule