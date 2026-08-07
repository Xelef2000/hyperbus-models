// Functional simulation replacement for the technology delay line used by
// the controller.  Pin timing will be modelled by the HyperRAM device model.
module configurable_delay #(
    parameter int unsigned NUM_STEPS = 32,
    localparam int unsigned DELAY_SEL_WIDTH = $clog2(NUM_STEPS)
) (
    input  logic clk_i,
    input  logic [DELAY_SEL_WIDTH-1:0] delay_i,
    output logic clk_o
);
    assign clk_o = clk_i;
endmodule
