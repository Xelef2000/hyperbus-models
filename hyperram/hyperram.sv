// HyperRAM chip wrapper.  The C++ core will eventually implement the
// cycle-accurate HyperBus protocol and memory array.
module hyperram #(
    // POR configuration used until configuration-register support exists.
    parameter int unsigned INITIAL_LATENCY_CYCLES = 13,
    // S27KS0642-compatible defaults. Override these for another device
    // profile; register-space transactions will consume them in a later step.
    parameter logic [15:0] IDENTIFICATION_REGISTER0_RESET = 16'h0c81,
    parameter logic [15:0] IDENTIFICATION_REGISTER1_RESET = 16'h0001,
    parameter logic [15:0] CONFIGURATION_REGISTER0_RESET = 16'h8f2f,
    parameter logic [15:0] CONFIGURATION_REGISTER1_RESET = 16'hffc1
) (
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
        input bit clk,
        input bit cs_n,
        input bit ck,
        input bit ck_n,
        input byte unsigned dq,
        input bit rwds
    );
    import "DPI-C" function void hyperram_model_set_initial_latency_cycles(
        input int unsigned cycles
    );
    import "DPI-C" function void hyperram_model_set_device_profile(
        input int unsigned id0,
        input int unsigned id1,
        input int unsigned config0,
        input int unsigned config1
    );
    import "DPI-C" function bit hyperram_model_dq_oe();
    import "DPI-C" function byte unsigned hyperram_model_dq_o();
    import "DPI-C" function bit hyperram_model_rwds_oe();
    import "DPI-C" function bit hyperram_model_rwds_o();

    logic dq_oe;
    logic [7:0] dq_o;
    logic rwds_oe;
    logic rwds_o;

    task automatic configure_model_profile();
        hyperram_model_set_device_profile(
            IDENTIFICATION_REGISTER0_RESET,
            IDENTIFICATION_REGISTER1_RESET,
            CONFIGURATION_REGISTER0_RESET,
            CONFIGURATION_REGISTER1_RESET
        );
        hyperram_model_set_initial_latency_cycles(INITIAL_LATENCY_CYCLES);
    endtask

    initial begin
        if (INITIAL_LATENCY_CYCLES < 3 || INITIAL_LATENCY_CYCLES > 16)
            $fatal(1, "INITIAL_LATENCY_CYCLES must be in the range 3..16");
        configure_model_profile();
        hyperram_model_reset();
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            configure_model_profile();
            hyperram_model_reset();
        end else
            hyperram_model_tick();
    end

    always @(clk_4x) begin
        if (reset_n) begin
            hyperram_model_tick_4x(clk, cs_n, ck, ck_n, dq, rwds);
            dq_oe = hyperram_model_dq_oe();
            dq_o = hyperram_model_dq_o();
            rwds_oe = hyperram_model_rwds_oe();
            rwds_o = hyperram_model_rwds_o();
        end else begin
            dq_oe = 1'b0;
            dq_o = '0;
            rwds_oe = 1'b0;
            rwds_o = 1'b0;
        end
    end

    assign rwds = rwds_oe ? rwds_o : 1'bz;
    assign dq = dq_oe ? dq_o : {8{1'bz}};

endmodule
