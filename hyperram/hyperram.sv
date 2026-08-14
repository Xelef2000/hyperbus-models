`timescale 1ps/1ps

// HyperRAM chip wrapper.  The C++ core will eventually implement the
// cycle-accurate HyperBus protocol and memory array.
module hyperram #(
    // S27KS0642-compatible defaults. Override these for another device.
    parameter logic [15:0] IDENTIFICATION_REGISTER0_RESET = 16'h0c81,
    parameter logic [15:0] IDENTIFICATION_REGISTER1_RESET = 16'h0001,
    parameter logic [15:0] CONFIGURATION_REGISTER0_RESET = 16'h8f2f,
    parameter logic [15:0] CONFIGURATION_REGISTER1_RESET = 16'hffc1,
    parameter bit FIXED_LATENCY_RWDS_HIGH = 1'b1,
    parameter bit VARIABLE_LATENCY_SUPPORTED = 1'b0,
    parameter int unsigned REFRESH_INTERVAL_4X_TICKS = 0,
    parameter int unsigned REFRESH_BUSY_4X_TICKS = 0,
    parameter bit ZERO_LATENCY_MEMORY_WRITES = 1'b0,
    parameter bit ZERO_LATENCY_REGISTER_WRITES = 1'b0,
    parameter bit ZERO_LATENCY_WRITE_RWDS_LOW = 1'b0,
    parameter int unsigned T_RWR_4X_TICKS = 0,
    parameter int unsigned T_CSS_4X_TICKS = 0,
    parameter int unsigned T_RESET_RECOVERY_4X_TICKS = 0,
    parameter bit RESET_CLEARS_MEMORY = 1'b0,
    parameter bit DEEP_POWER_DOWN_SUPPORTED = 1'b0,
    parameter int unsigned T_DPD_ENTRY_4X_TICKS = 0,
    parameter int unsigned T_DPD_EXIT_4X_TICKS = 0,
    parameter int unsigned T_CSDPD_4X_TICKS = 0,
    parameter bit HYBRID_SLEEP_SUPPORTED = 1'b0,
    parameter int unsigned T_HS_ENTRY_4X_TICKS = 0,
    parameter int unsigned T_HS_EXIT_4X_TICKS = 0,
    parameter int unsigned T_CSHS_4X_TICKS = 0,
    // 0 selects single-ended CK operation; 1 requires complementary CK/CK#.
    parameter bit DIFFERENTIAL_CLOCK_MODE = 1'b0,
    parameter int unsigned T_CA_SETUP_4X_TICKS = 0,
    parameter int unsigned T_CA_HOLD_4X_TICKS = 0,
    parameter int unsigned T_WRITE_SETUP_4X_TICKS = 0,
    parameter int unsigned T_WRITE_HOLD_4X_TICKS = 0,
    parameter int unsigned MEMORY_DENSITY_BYTES = 0,
    parameter bit ADDRESS_ROLLOVER = 1'b1,
    parameter bit INTER_WORD_VARIABLE_LATENCY_SUPPORTED = 1'b0,
    parameter int unsigned INTER_WORD_STALL_EDGES = 0,
    // Minimum active-transaction CK high/low phase widths, in 4× ticks.
    // A value of zero disables the corresponding duty-cycle check.
    parameter int unsigned T_CK_HIGH_MIN_4X_TICKS = 0,
    parameter int unsigned T_CK_LOW_MIN_4X_TICKS = 0,
    // Output timing is profile-specific. The defaults match a 200 MHz
    // S27KS0642-compatible timing selection.
    parameter time T_DQ_OUTPUT_DELAY = 5000ps,
    parameter time T_RWDS_OUTPUT_DELAY = 5000ps,
    parameter time T_DQ_OUTPUT_DISABLE_DELAY = 5000ps,
    parameter time T_RWDS_OUTPUT_DISABLE_DELAY = 5000ps,
    // Data validity and read-strobe phase may differ on a real device.
    parameter time T_DQ_DATA_VALID_DELAY = T_DQ_OUTPUT_DELAY,
    parameter time T_RWDS_STROBE_DELAY = T_RWDS_OUTPUT_DELAY
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
    import "DPI-C" function void hyperram_model_set_device_profile(
        input int unsigned id0,
        input int unsigned id1,
        input int unsigned config0,
        input int unsigned config1,
        input bit fixed_latency_rwds_high,
        input bit variable_latency_supported,
        input int unsigned refresh_interval_4x_ticks,
        input int unsigned refresh_busy_4x_ticks,
        input bit zero_latency_memory_writes,
        input bit zero_latency_register_writes,
        input bit zero_latency_write_rwds_low,
        input int unsigned t_rwr_4x_ticks,
        input int unsigned t_css_4x_ticks,
        input int unsigned t_reset_recovery_4x_ticks,
        input bit reset_clears_memory,
        input bit deep_power_down_supported,
        input int unsigned t_dpd_entry_4x_ticks,
        input int unsigned t_dpd_exit_4x_ticks,
        input int unsigned t_csdpd_4x_ticks,
        input bit hybrid_sleep_supported,
        input int unsigned t_hs_entry_4x_ticks,
        input int unsigned t_hs_exit_4x_ticks,
        input int unsigned t_cshs_4x_ticks,
        input bit differential_clock_mode,
        input int unsigned t_ca_setup_4x_ticks,
        input int unsigned t_ca_hold_4x_ticks,
        input int unsigned t_write_setup_4x_ticks,
        input int unsigned t_write_hold_4x_ticks,
        input bit inter_word_variable_latency_supported,
        input int unsigned inter_word_stall_edges,
        input int unsigned t_ck_high_min_4x_ticks,
        input int unsigned t_ck_low_min_4x_ticks
    );
    import "DPI-C" function void hyperram_model_set_memory_geometry(
        input int unsigned bytes,
        input bit rollover
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

    task automatic configure_model_profile();
        hyperram_model_set_device_profile(
            IDENTIFICATION_REGISTER0_RESET,
            IDENTIFICATION_REGISTER1_RESET,
            CONFIGURATION_REGISTER0_RESET,
            CONFIGURATION_REGISTER1_RESET,
            FIXED_LATENCY_RWDS_HIGH,
            VARIABLE_LATENCY_SUPPORTED,
            REFRESH_INTERVAL_4X_TICKS,
            REFRESH_BUSY_4X_TICKS,
            ZERO_LATENCY_MEMORY_WRITES,
            ZERO_LATENCY_REGISTER_WRITES,
            ZERO_LATENCY_WRITE_RWDS_LOW,
            T_RWR_4X_TICKS,
            T_CSS_4X_TICKS,
            T_RESET_RECOVERY_4X_TICKS,
            RESET_CLEARS_MEMORY,
            DEEP_POWER_DOWN_SUPPORTED,
            T_DPD_ENTRY_4X_TICKS,
            T_DPD_EXIT_4X_TICKS,
            T_CSDPD_4X_TICKS,
            HYBRID_SLEEP_SUPPORTED,
            T_HS_ENTRY_4X_TICKS,
            T_HS_EXIT_4X_TICKS,
            T_CSHS_4X_TICKS,
            DIFFERENTIAL_CLOCK_MODE,
            T_CA_SETUP_4X_TICKS,
            T_CA_HOLD_4X_TICKS,
            T_WRITE_SETUP_4X_TICKS,
            T_WRITE_HOLD_4X_TICKS,
            INTER_WORD_VARIABLE_LATENCY_SUPPORTED,
            INTER_WORD_STALL_EDGES,
            T_CK_HIGH_MIN_4X_TICKS,
            T_CK_LOW_MIN_4X_TICKS
        );
        hyperram_model_set_memory_geometry(MEMORY_DENSITY_BYTES,
                                           ADDRESS_ROLLOVER);
    endtask

    initial begin
        configure_model_profile();
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
    assign #(T_DQ_OUTPUT_DELAY, T_DQ_OUTPUT_DISABLE_DELAY) dq_oe_timed = dq_oe;
    assign #(T_DQ_DATA_VALID_DELAY) dq_o_timed = dq_o;
    assign #(T_RWDS_OUTPUT_DELAY, T_RWDS_OUTPUT_DISABLE_DELAY) rwds_oe_timed = rwds_oe;
    assign #(T_RWDS_STROBE_DELAY) rwds_o_timed = rwds_o;
    assign rwds = rwds_oe_timed ? rwds_o_timed : 1'bz;
    assign dq = dq_oe_timed ? dq_o_timed : {8{1'bz}};

endmodule
