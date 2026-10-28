///////////////////////////////////////////////////////////////////////////////////////////////////
// Description:
// Combines 300 EMG samples and 90 ADAS features into
// one 390-element input vector for the MLP-to-SNN accelerator.
//
// Target: PolarFire SoC MPFS250T
///////////////////////////////////////////////////////////////////////////////////////////////////

module INPUT_COMBINER (
    // 300 EMG samples x 8 bits
    input  wire [2399:0] emg_flat,

    // 90 ADAS features x 8 bits
    input  wire [719:0]  context_flat,

    // Combined 390 x 8-bit feature vector
    output wire [3119:0] snn_input
);

    assign snn_input = {context_flat, emg_flat};

endmodule