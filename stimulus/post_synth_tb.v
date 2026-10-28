`timescale 1ns / 1ps

module post_synth_tb;

    // ---------------------------------------------
    // Parameters
    // ---------------------------------------------

    parameter CLK_PERIOD = 20;

    // 115200 baud
    parameter BIT_PERIOD = 8681;

    // ---------------------------------------------
    // Test memory
    // ---------------------------------------------

    reg [7:0] test_mem [0:299];

    // ---------------------------------------------
    // DUT inputs
    // ---------------------------------------------

    reg REF_CLK_0;
    reg rst_n;
    reg PLL_POWERDOWN_N_0;
    reg RX;

    // ---------------------------------------------
    // DUT outputs
    // ---------------------------------------------

    wire brake_trigger;
    wire latched_brake_trigger;
    wire latched_non_brake_trigger;
    wire latched_inference_done;

    wire [15:0] latched_class_0_score;
    wire [15:0] latched_class_1_score;

    integer idx;
    integer bit_idx;

    // ---------------------------------------------
    // DUT instantiation
    // ---------------------------------------------

    SNN uut (

        .REF_CLK_0(REF_CLK_0),

        .rst_n(rst_n),

        .PLL_POWERDOWN_N_0(PLL_POWERDOWN_N_0),

        .RX(RX),

        .brake_trigger(brake_trigger),

        .latched_brake_trigger(
            latched_brake_trigger
        ),

        .latched_non_brake_trigger(
            latched_non_brake_trigger
        ),

        .latched_inference_done(
            latched_inference_done
        ),

        .latched_class_0_score(
            latched_class_0_score
        ),

        .latched_class_1_score(
            latched_class_1_score
        )

    );

    // ---------------------------------------------
    // 50 MHz reference clock
    // ---------------------------------------------

    initial REF_CLK_0 = 1'b0;

    always #(CLK_PERIOD/2)
        REF_CLK_0 = ~REF_CLK_0;

    // ---------------------------------------------
    // UART transmit task
    // ---------------------------------------------

    task uart_send_byte;

        input [7:0] data;

        begin

            // Start bit
            RX = 1'b0;
            #(BIT_PERIOD);

            // 8 data bits, LSB first
            for (bit_idx = 0; bit_idx < 8;
                 bit_idx = bit_idx + 1) begin

                RX = data[bit_idx];
                #(BIT_PERIOD);

            end

            // Stop bit
            RX = 1'b1;
            #(BIT_PERIOD);

        end

    endtask

    // ---------------------------------------------
    // Main simulation
    // ---------------------------------------------

    initial begin

        $readmemh("emg_sample.mem", test_mem);

        rst_n             = 1'b0;
        PLL_POWERDOWN_N_0 = 1'b0;
        RX                = 1'b1;

        // Reset period
        #1000;

        PLL_POWERDOWN_N_0 = 1'b1;
        rst_n             = 1'b1;

        // Allow PLL startup and reset release
        #10000;

        $display("Starting UART EMG transmission");

        // Send 300 samples
        for (idx = 0; idx < 300;
             idx = idx + 1) begin

            uart_send_byte(test_mem[idx]);

        end

        $display("All 300 EMG samples transmitted");

        // Wait for completed inference
        wait(latched_inference_done === 1'b1);

        $display("SNN inference completed!");

        $display("Class 0 Score = %d",
                 latched_class_0_score);

        $display("Class 1 Score = %d",
                 latched_class_1_score);

        $display("Brake Trigger = %b",
                 latched_brake_trigger);

        #1000;

        $finish;

    end

    // ---------------------------------------------
    // Simulation timeout
    // ---------------------------------------------

    initial begin

        #40000000;  // 40 ms

        $display("ERROR: Simulation timed out");

        $finish;

    end

endmodule