`timescale 1ns/1ps
// One 12-byte telemetry packet per completed inference.
// Byte order: A5 5A, signed score (32-bit LE), cycles (32-bit LE),
// brake decision (00/01), XOR checksum of bytes 0..10.
// Connect TX data / WEN_N / TXRDY to CoreUART DATA_IN / WEN / TXRDY.
// CoreUART CSN must stay LOW. TX FIFO may remain disabled.
// clk, rst_n are the same as the CoreUART clock/reset.
module SNN_UART_REPORTER (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               latched_inference_done,
    input  wire signed [31:0] latched_readout_score,
    input  wire               latched_brake_trigger,
    input  wire [31:0]        inference_cycles,
    input  wire               txrdy,
    output reg  [7:0]         uart_data_in,
    output reg                uart_wen_n,
    output wire               reporter_busy,
    output reg                packet_queued,
    output reg                report_overrun
);
    localparam [1:0] ST_IDLE=2'd0, ST_WAIT_READY=2'd1,
                     ST_WRITE=2'd2, ST_RELEASE=2'd3;
    reg [1:0] state;
    reg [3:0] byte_index;
    reg [31:0] score_q, cycles_q;
    reg brake_q;
    reg [7:0] checksum_q;

    function [7:0] packet_byte;
        input [3:0] idx;
        input [31:0] score;
        input [31:0] cycles;
        input brake;
        input [7:0] checksum;
        begin
            case (idx)
                4'd0: packet_byte = 8'hA5;
                4'd1: packet_byte = 8'h5A;
                4'd2: packet_byte = score[7:0];
                4'd3: packet_byte = score[15:8];
                4'd4: packet_byte = score[23:16];
                4'd5: packet_byte = score[31:24];
                4'd6: packet_byte = cycles[7:0];
                4'd7: packet_byte = cycles[15:8];
                4'd8: packet_byte = cycles[23:16];
                4'd9: packet_byte = cycles[31:24];
                4'd10: packet_byte = {7'd0, brake};
                4'd11: packet_byte = checksum;
                default: packet_byte = 8'h00;
            endcase
        end
    endfunction

    assign reporter_busy = (state != ST_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            byte_index     <= 4'd0;
            score_q        <= 32'd0;
            cycles_q       <= 32'd0;
            brake_q        <= 1'b0;
            checksum_q     <= 8'd0;
            uart_data_in   <= 8'd0;
            uart_wen_n     <= 1'b1;
            packet_queued  <= 1'b0;
            report_overrun <= 1'b0;
        end else begin
            uart_wen_n    <= 1'b1;
            packet_queued <= 1'b0;
            if (latched_inference_done && state != ST_IDLE)
                report_overrun <= 1'b1; // Sticky until reset.
            case (state)
                ST_IDLE: begin
                    if (latched_inference_done) begin
                        score_q    <= latched_readout_score;
                        cycles_q   <= inference_cycles;
                        brake_q    <= latched_brake_trigger;
                        checksum_q <= 8'hA5 ^ 8'h5A ^
                                      latched_readout_score[7:0] ^
                                      latched_readout_score[15:8] ^
                                      latched_readout_score[23:16] ^
                                      latched_readout_score[31:24] ^
                                      inference_cycles[7:0] ^
                                      inference_cycles[15:8] ^
                                      inference_cycles[23:16] ^
                                      inference_cycles[31:24] ^
                                      {7'd0,latched_brake_trigger};
                        byte_index <= 4'd0;
                        state      <= ST_WAIT_READY;
                    end
                end
                ST_WAIT_READY: begin
                    if (txrdy) begin
                        // CoreUART sees these registered values on the
                        // NEXT rising edge (state ST_WRITE).
                        uart_data_in <= packet_byte(byte_index,score_q,cycles_q,
                                                    brake_q,checksum_q);
                        uart_wen_n   <= 1'b0;
                        state        <= ST_WRITE;
                    end
                end
                ST_WRITE: begin
                    // WEN_N goes high on this edge; CoreUART has sampled
                    // the preceding full-cycle low WEN_N.
                    state <= ST_RELEASE;
                end
                ST_RELEASE: begin
                    if (byte_index == 4'd11) begin
                        packet_queued <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        byte_index <= byte_index + 4'd1;
                        state <= ST_WAIT_READY;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
