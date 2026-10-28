`timescale 1ns / 1ps

module tn_SNN;

    // 1. Declare Test Memory at Module Scope
    reg [7:0] test_mem [0:299];

    // 2. Clocks & Resets
    reg REF_CLK_0;
    reg rst_n;
    reg PLL_POWERDOWN_N_0;

    // 3. Stimulus Signals
    reg [7:0] sample_in;
    reg       sample_valid;
    integer   idx;

    // 4. Instantiate Top-Level Design (SNN)
    SNN uut (
        .REF_CLK_0        (REF_CLK_0),
        .rst_n            (rst_n),
        .PLL_POWERDOWN_N_0(PLL_POWERDOWN_N_0),
        .sample_in        (sample_in),
        .sample_valid     (sample_valid)
    );

    // 5. Reference Clock Generator (50 MHz = 20 ns period -> toggle every 10 ns)
    always #10 REF_CLK_0 = ~REF_CLK_0;

    // 6. Testbench Stimulus Logic
    initial begin
        // Load quantized EMG data from .mem file
        $readmemh("emg_sample.mem", test_mem);

        // Initialize signals
        REF_CLK_0         = 1'b0;
        rst_n             = 1'b0;
        PLL_POWERDOWN_N_0 = 1'b0;
        sample_valid      = 1'b0;
        sample_in         = 7'd0;

        // Release reset & power down
        #100;
        rst_n             = 1'b1;
        PLL_POWERDOWN_N_0 = 1'b1;

        // Wait past PLL lock (~600 ns)
        #600;

        // Synchronize to internal PLL clock edge
        repeat (5) @(posedge uut.emgBuffer_0.clk);

        $display("[%0t ns] Feeding real subject EMG sample from emg_sample.mem...", $time);
        
        // Stream all 300 samples on the internal clock domain
        for (idx = 0; idx < 300; idx = idx + 1) begin
            @(posedge uut.emgBuffer_0.clk);
            sample_in    <= test_mem[idx];
            sample_valid <= 1'b1;
        end

        // Deassert valid pulse
        @(posedge uut.emgBuffer_0.clk);
        sample_valid <= 1'b0;
        sample_in    <= 7'd0;
    end

endmodule