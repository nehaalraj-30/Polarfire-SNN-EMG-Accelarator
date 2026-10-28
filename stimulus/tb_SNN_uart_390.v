`timescale 1ns / 1ps

// End-to-end RTL test of the current SmartDesign SNN top level.
// 50 MHz reference clock; 115200-baud UART, 8-N-1, LSB first.
// Input: 390-byte frame from input_390.mem.
// Output: 12-byte binary telemetry packet on TX:
//   [0]  A5 start marker
//   [1]  5A start marker
//   [2:5]  signed readout (int32, little endian)
//   [6:9]  inference cycles (uint32, little endian)
//   [10]  brake decision (0 or 1)
//   [11]  XOR of bytes [0:10]
module tb_SNN_uart_390;
    localparam integer CLK_HALF_NS = 10;
    localparam integer UART_BIT_NS = 8680;
    localparam integer NUM_BYTES = 390;
    localparam integer PACKET_BYTES = 12;

    reg REF_CLK_0 = 1'b0;
    reg rst_n = 1'b0;
    reg RX = 1'b1; // UART idle HIGH

    wire TX;
    wire latched_brake_trigger;
    wire latched_non_brake_trigger;
    wire inference_led;

    reg [7:0] stimulus [0:NUM_BYTES-1];
    reg [7:0] packet [0:PACKET_BYTES-1];
    reg [7:0] checksum;
    reg [31:0] score_bits;
    reg [31:0] inference_cycles;
    reg [7:0] brake_byte;
    integer n;
    integer p;

    `include "expected.vh"

    SNN dut (
        .REF_CLK_0(REF_CLK_0),
        .rst_n(rst_n),
        .RX(RX),
        .TX(TX),
        .latched_brake_trigger(latched_brake_trigger),
        .latched_non_brake_trigger(latched_non_brake_trigger),
        .inference_led(inference_led)
    );

    always #CLK_HALF_NS REF_CLK_0 = ~REF_CLK_0;

    task uart_send_byte;
        input [7:0] b;
        integer bit_index;
        begin
            RX = 1'b0;
            #(UART_BIT_NS);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                RX = b[bit_index];
                #(UART_BIT_NS);
            end
            RX = 1'b1;
            #(UART_BIT_NS);
        end
    endtask

    // Sample each TX data bit at approximately its midpoint.
    // Call when ready for the NEXT UART byte.
    task uart_receive_byte;
        output [7:0] b;
        integer bit_index;
        begin
            b = 8'h00;
            @(negedge TX);
            #(UART_BIT_NS / 2);
            if (TX !== 1'b0)
                $fatal(1, "FAIL: invalid UART TX start bit at %0t ns", $time);

            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                #(UART_BIT_NS);
                b[bit_index] = TX;
            end
            #(UART_BIT_NS);
            if (TX !== 1'b1)
                $fatal(1, "FAIL: invalid UART TX stop bit at %0t ns", $time);
        end
    endtask

    // Independent watchdog in case UART reception or inference stalls.
    initial begin
        #50000000; // 50 ms
        $fatal(1, "FAIL: timeout at %0t ns", $time);
    end

    // Drive the 390-byte input frame.
    initial begin
        $readmemh("input_390.mem", stimulus);
        $display("Expected signed readout=%0d, brake=%0d",
                 EXPECTED_READOUT, EXPECTED_BRAKE);
        $display("Beginning UART test of 390-byte frame");

        // The updated SmartDesign no longer exposes PLL_POWERDOWN_N_0.
        // Allow PLL startup while external reset remains asserted.
        #20200;
        rst_n = 1'b1;
        #20000;

        for (n = 0; n < NUM_BYTES; n = n + 1) begin
            uart_send_byte(stimulus[n]);
            if ((n + 1) % 100 == 0)
                $display("%0t ns: sent %0d/%0d UART bytes", $time, n + 1, NUM_BYTES);
        end
        $display("%0t ns: all 390 UART bytes transmitted", $time);
    end

    // Independently receive the FPGA's binary UART telemetry.
    initial begin
        wait (rst_n === 1'b1);
        wait (TX === 1'b1); // Ignore startup unknowns/reset transitions
        for (p = 0; p < PACKET_BYTES; p = p + 1)
            uart_receive_byte(packet[p]);

        $display("%0t ns: complete TX telemetry packet received", $time);

        if (packet[0] !== 8'hA5 || packet[1] !== 8'h5A)
            $fatal(1, "FAIL: telemetry header: %02h %02h", packet[0], packet[1]);

        checksum = 8'h00;
        for (p = 0; p < PACKET_BYTES - 1; p = p + 1)
            checksum = checksum ^ packet[p];
        if (packet[11] !== checksum)
            $fatal(1, "FAIL: checksum expected=%02h actual=%02h",
                   checksum, packet[11]);

        score_bits = {packet[5], packet[4], packet[3], packet[2]};
        inference_cycles = {packet[9], packet[8], packet[7], packet[6]};
        brake_byte = packet[10];

        $display("Readout: expected=%0d actual=%0d (0x%08h)",
                 EXPECTED_READOUT, $signed(score_bits), score_bits);
        $display("Brake: expected=%0d actual=%0d", EXPECTED_BRAKE, brake_byte);
        $display("Inference cycles=%0d", inference_cycles);
        $display("Non-brake=%0d; inference LED=%0d",
                 latched_non_brake_trigger, inference_led);

        if ($signed(score_bits) !== EXPECTED_READOUT)
            $fatal(1, "FAIL: signed readout mismatch");
        if (brake_byte !== EXPECTED_BRAKE)
            $fatal(1, "FAIL: UART brake decision mismatch");
        if (latched_brake_trigger !== EXPECTED_BRAKE)
            $fatal(1, "FAIL: brake LED mismatch");
        if (latched_non_brake_trigger !== !EXPECTED_BRAKE)
            $fatal(1, "FAIL: non-brake LED mismatch");
        if (inference_led !== 1'b1)
            $fatal(1, "FAIL: inference completion LED not asserted");
        if (inference_cycles === 32'hxxxxxxxx || inference_cycles == 0)
            $fatal(1, "FAIL: inference cycle counter is invalid");

        $display("PASS: 390 UART bytes, signed readout, brake decision, cycle counter, checksum, and LEDs");
        #1000;
        $finish;
    end
endmodule
