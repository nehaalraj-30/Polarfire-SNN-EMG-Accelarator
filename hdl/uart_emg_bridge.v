///////////////////////////////////////////////////////////////////////////////////////////////////
// Company: <Name>
//
// File: uart_emg_bridge.v
// File history:
//      <Revision number>: <Date>: <Comments>
//      <Revision number>: <Date>: <Comments>
//      <Revision number>: <Date>: <Comments>
//
// Description: 
//
// <Description here>
//
// Targeted device: <Family::PolarFireSoC> <Die::MPFS250TC> <Package::FCVG484>
// Author: <Name>
//
/////////////////////////////////////////////////////////////////////////////////////////////////// 

module uart_emg_bridge (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rxrdy,
    input  wire [7:0] uart_data,

    output reg        uart_oen_n,
    output reg        sample_valid,
    output reg  [7:0] sample_data
);

    localparam S_WAIT  = 2'd0;
    localparam S_READ  = 2'd1;
    localparam S_CLEAR = 2'd2;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin
            state        <= S_WAIT;
            uart_oen_n   <= 1'b1;
            sample_valid <= 1'b0;
            sample_data  <= 8'd0;
        end else begin

            uart_oen_n   <= 1'b1;
            sample_valid <= 1'b0;

            case (state)

                S_WAIT: begin
                    if (rxrdy) begin
                        sample_data  <= uart_data;
                        sample_valid <= 1'b1;
                        uart_oen_n   <= 1'b0;
                        state        <= S_READ;
                    end
                end

                S_READ: begin
                    // Read acknowledgement was asserted.
                    // Return OEN high.
                    state <= S_CLEAR;
                end

                S_CLEAR: begin
                    // Wait until RXRDY has deasserted.
                    if (!rxrdy)
                        state <= S_WAIT;
                end

                default: state <= S_WAIT;

            endcase
        end
    end

endmodule



