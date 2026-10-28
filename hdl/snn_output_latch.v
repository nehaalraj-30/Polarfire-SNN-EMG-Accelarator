`timescale 1ns / 1ps

module snn_output_latch #(
    parameter ACC_WIDTH = 32,

    // Trained model's classification threshold
    parameter signed [ACC_WIDTH-1:0]
        DECISION_THRESHOLD = 32'sd3145
)(
    input  wire clk,
    input  wire rst_n,

    // From snnController
    input  wire inference_done_in,

    // From Layer 3
    input  wire signed [ACC_WIDTH-1:0] raw_readout_score,

    // Latched inference outputs
    output reg signed [ACC_WIDTH-1:0] latched_readout_score,
    output reg latched_brake_trigger,
    output reg latched_inference_done,

    // Toggles after each completed inference
    output reg inference_led
);

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            latched_readout_score   <= {ACC_WIDTH{1'b0}};
            latched_brake_trigger   <= 1'b0;
            latched_inference_done  <= 1'b0;
            inference_led           <= 1'b0;

        end
        else begin

            // Preserve the original one-clock completion pulse
            latched_inference_done <= inference_done_in;

            if (inference_done_in) begin

                // Freeze final numerical readout
                latched_readout_score <= raw_readout_score;

                // Brake decision: score >= 3145
                latched_brake_trigger <=
                    (raw_readout_score >= DECISION_THRESHOLD);

                // Toggle LED after every completed inference
                inference_led <= ~inference_led;

            end

        end

    end

endmodule