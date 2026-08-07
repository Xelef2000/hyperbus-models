// HyperRAM chip wrapper.  The C++ core will eventually implement the
// cycle-accurate HyperBus protocol and memory array.
module hyperram (
    input  logic       clk,
    input  logic       clk_4x,
    input  logic       reset_n,
    input  logic       cs_n,
    input  logic       ck,
    input  logic       ck_n,
    inout  wire        rwds,
    inout  wire [7:0]  dq
);

    import "DPI-C" function void hyperram_model_reset();
    import "DPI-C" function void hyperram_model_tick();
    import "DPI-C" function void hyperram_model_tick_4x(
        input bit cs_n,
        input bit ck,
        input bit ck_n
    );

    always_ff @(posedge clk) begin
        if (!reset_n)
            hyperram_model_reset();
        else
            hyperram_model_tick();
    end

    always_ff @(posedge clk_4x) begin
        if (reset_n)
            hyperram_model_tick_4x(cs_n, ck, ck_n);
    end

    // The bus remains high impedance until protocol behavior is implemented.
    assign rwds = 1'bz;
    assign dq = {8{1'bz}};

endmodule
