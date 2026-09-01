`timescale 1ps/1ps

// HyperRAM pin wrapper for the cycle-accurate C++ protocol and memory core.
module hyperram #(
    parameter string CHIP_PROFILE = "s27ks0642_200mhz"
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
        input bit reset_n,
        input bit clk,
        input bit cs_n,
        input bit ck,
        input bit ck_n,
        input byte unsigned dq,
        input bit rwds
    );
    import "DPI-C" function bit hyperram_model_select_profile(input string name);
    import "DPI-C" function longint unsigned hyperram_model_output_timing(
        input int unsigned index
    );
    import "DPI-C" function bit hyperram_model_dq_oe();
    import "DPI-C" function byte unsigned hyperram_model_dq_o();
    import "DPI-C" function bit hyperram_model_rwds_oe();
    import "DPI-C" function bit hyperram_model_rwds_o();

    logic dq_oe;
    logic [7:0] dq_o;
    logic rwds_oe;
    logic rwds_o;
    wire dq_oe_timed;
    wire [7:0] dq_o_timed;
    wire rwds_oe_timed;
    wire rwds_o_timed;
    time dq_output_delay = 5000ps;
    time rwds_output_delay = 5000ps;
    time dq_output_disable_delay = 5000ps;
    time rwds_output_disable_delay = 5000ps;
    time dq_data_valid_delay = 5000ps;
    time rwds_strobe_delay = 5000ps;

    initial begin
        if (!hyperram_model_select_profile(CHIP_PROFILE))
            $fatal(1, "Unknown HyperRAM chip profile: %s", CHIP_PROFILE);
        dq_output_delay = hyperram_model_output_timing(0);
        rwds_output_delay = hyperram_model_output_timing(1);
        dq_output_disable_delay = hyperram_model_output_timing(2);
        rwds_output_disable_delay = hyperram_model_output_timing(3);
        dq_data_valid_delay = hyperram_model_output_timing(4);
        rwds_strobe_delay = hyperram_model_output_timing(5);
        hyperram_model_reset();
    end

    always_ff @(posedge clk)
        hyperram_model_tick();

    always @(clk_4x) begin
        begin
            hyperram_model_tick_4x(reset_n, clk, cs_n, ck, ck_n, dq, rwds);
            dq_oe = hyperram_model_dq_oe();
            dq_o = hyperram_model_dq_o();
            rwds_oe = hyperram_model_rwds_oe();
            rwds_o = hyperram_model_rwds_o();
        end
    end

    // Separate logical ownership from physical pin timing. Enables are
    // delayed independently, so their falling edge models output turn-off
    // before the undelayed tri-state pin assignment releases the bus.
    // Physical delays are selected with the C++ chip profile.
    assign #(dq_output_delay, dq_output_disable_delay) dq_oe_timed = dq_oe;
    assign #(dq_data_valid_delay) dq_o_timed = dq_o;
    assign #(rwds_output_delay, rwds_output_disable_delay) rwds_oe_timed = rwds_oe;
    assign #(rwds_strobe_delay) rwds_o_timed = rwds_o;
    assign rwds = rwds_oe_timed ? rwds_o_timed : 1'bz;
    assign dq = dq_oe_timed ? dq_o_timed : {8{1'bz}};

endmodule
