`timescale 1ns/1ps

// Standalone RTL verification of inference_perf_counter + SNN_UART_REPORTER.
// CoreUART TXRDY is emulated: each accepted WEN_N pulse briefly makes it busy.
// This does not simulate CoreUART's serial TX pin, which can be verified later.
module tb_snn_telemetry;
    reg clk = 1'b0;
    always #10 clk = ~clk; // 50 MHz

    reg rst_n = 1'b0;
    reg inference_start = 1'b0;
    reg inference_done = 1'b0;
    wire [31:0] inference_cycles;
    wire measurement_valid, counting;
    reg latched_inference_done = 1'b0;
    reg signed [31:0] latched_readout_score = 0;
    reg latched_brake_trigger = 1'b0;
    reg txrdy = 1'b1;
    wire [7:0] uart_data_in;
    wire uart_wen_n;
    wire reporter_busy, packet_queued, report_overrun;

    inference_perf_counter counter (
        .clk(clk), .rst_n(rst_n),
        .inference_start(inference_start), .inference_done(inference_done),
        .inference_cycles(inference_cycles),
        .measurement_valid(measurement_valid), .counting(counting)
    );
    SNN_UART_REPORTER reporter (
        .clk(clk), .rst_n(rst_n),
        .latched_inference_done(latched_inference_done),
        .latched_readout_score(latched_readout_score),
        .latched_brake_trigger(latched_brake_trigger),
        .inference_cycles(inference_cycles),
        .txrdy(txrdy), .uart_data_in(uart_data_in),
        .uart_wen_n(uart_wen_n), .reporter_busy(reporter_busy),
        .packet_queued(packet_queued), .report_overrun(report_overrun)
    );

    reg [7:0] expected_packet[0:11];
    integer accepted = 0;
    integer packet_completions = 0;
    integer busy_clocks = 0;
    reg [7:0] checksum;

    // Emulate a slow non-FIFO UART that deasserts TXRDY after accepting a byte.
    // Observe values at posedge just as real CoreUART captures DATA_IN/WEN_N.
    always @(posedge clk) begin
        if (rst_n && !uart_wen_n) begin
            if (!txrdy) begin
                $display("FAIL: WEN_N low while TXRDY=0 at %0t", $time);
                $fatal(1);
            end
            if (accepted >= 12) begin
                $display("FAIL: more than 12 bytes in packet");
                $fatal(1);
            end
            if (uart_data_in !== expected_packet[accepted]) begin
                $display("FAIL: byte %0d expected %02h got %02h", accepted,
                         expected_packet[accepted], uart_data_in);
                $fatal(1);
            end
            $display("TX byte %0d: %02h", accepted, uart_data_in);
            accepted = accepted + 1;
            txrdy <= 1'b0;
            busy_clocks <= 3;
        end else if (rst_n && !txrdy) begin
            if (busy_clocks > 0)
                busy_clocks <= busy_clocks - 1;
            else
                txrdy <= 1'b1;
        end
        if (rst_n && packet_queued)
            packet_completions = packet_completions + 1;
    end

    task prepare_packet;
        input [31:0] score;
        input [31:0] cycles;
        input brake;
        integer i;
        begin
            expected_packet[0] = 8'hA5;
            expected_packet[1] = 8'h5A;
            expected_packet[2] = score[7:0];
            expected_packet[3] = score[15:8];
            expected_packet[4] = score[23:16];
            expected_packet[5] = score[31:24];
            expected_packet[6] = cycles[7:0];
            expected_packet[7] = cycles[15:8];
            expected_packet[8] = cycles[23:16];
            expected_packet[9] = cycles[31:24];
            expected_packet[10] = {7'b0,brake};
            checksum = 0;
            for (i=0; i<11; i=i+1)
                checksum = checksum ^ expected_packet[i];
            expected_packet[11] = checksum;
            accepted = 0;
        end
    endtask

    task run_case;
        input [31:0] score;
        input brake;
        input integer cycles;
        integer timeout;
        begin
            // Begins a measurement at this posedge, stops at the closing edge.
            @(negedge clk);
            inference_start = 1;
            @(negedge clk);
            inference_start = 0;
            repeat (cycles-1) @(negedge clk);
            inference_done = 1;
            @(negedge clk);
            inference_done = 0;
            if (inference_cycles !== cycles) begin
                $display("FAIL: cycle count expected=%0d actual=%0d",
                         cycles, inference_cycles);
                $fatal(1);
            end
            $display("Counter PASS: %0d cycles = %0d ns", cycles, cycles*20);

            // Mimic the actual SNN output latch updating its registered outputs
            // after the controller's done event; generate its one-cycle pulse.
            prepare_packet(score, cycles, brake);
            latched_readout_score = score;
            latched_brake_trigger = brake;
            latched_inference_done = 1;
            @(negedge clk);
            latched_inference_done = 0;

            timeout = 0;
            while (accepted != 12 && timeout < 200) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (accepted != 12) begin
                $display("FAIL: UART reporter timeout at byte %0d", accepted);
                $fatal(1);
            end
            // Wait for reporter to exit ST_RELEASE and assert packet_queued.
            repeat (4) @(negedge clk);
            if (reporter_busy !== 1'b0 || report_overrun !== 1'b0) begin
                $display("FAIL: reporter busy or unexpected overrun");
                $fatal(1);
            end
            $display("Packet PASS: score=%0d cycles=%0d brake=%0d checksum=%02h",
                     $signed(score), cycles, brake, checksum);
        end
    endtask

    initial begin
        #1;
        $display("Standalone SNN telemetry RTL test at 50 MHz");
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        // Synthetic known readout from previous complete test.
        run_case(32'd2880, 1'b0, 650);
        // Second packet tests a real above-threshold brake decision.
        run_case(32'd4000, 1'b1, 40);
        // Negative signed readout must also classify as non-braking.
        run_case(-32'sd17, 1'b0, 25);
        if (packet_completions != 3) begin
            $display("FAIL: expected 3 packet completions, got %0d", packet_completions);
            $fatal(1);
        end
        $display("PASS: counter, all three 12-byte packets, signed score, checksum, CoreUART WEN/TXRDY handshake");
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: global testbench timeout");
        $fatal(1);
    end
endmodule
