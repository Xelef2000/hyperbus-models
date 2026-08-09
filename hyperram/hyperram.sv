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
    // Output timing is profile-specific. The defaults match the supplied
    // S27KS0642 reference model's 200 MHz timing selection.
    parameter time T_DQ_OUTPUT_DELAY = 5000ps,
    parameter time T_RWDS_OUTPUT_DELAY = 5000ps,
    parameter time T_DQ_OUTPUT_DISABLE_DELAY = 5000ps,
    parameter time T_RWDS_OUTPUT_DISABLE_DELAY = 5000ps
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
        input bit zero_latency_write_rwds_low
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
            ZERO_LATENCY_WRITE_RWDS_LOW
        );
    endtask

    initial begin
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

    // Separate logical ownership from physical pin timing. Enables are
    // delayed independently, so their falling edge models output turn-off
    // before the undelayed tri-state pin assignment releases the bus.
    assign #(T_DQ_OUTPUT_DELAY, T_DQ_OUTPUT_DISABLE_DELAY) dq_oe_timed = dq_oe;
    assign #(T_DQ_OUTPUT_DELAY) dq_o_timed = dq_o;
    assign #(T_RWDS_OUTPUT_DELAY, T_RWDS_OUTPUT_DISABLE_DELAY) rwds_oe_timed = rwds_oe;
    assign #(T_RWDS_OUTPUT_DELAY) rwds_o_timed = rwds_o;
    assign rwds = rwds_oe_timed ? rwds_o_timed : 1'bz;
    assign dq = dq_oe_timed ? dq_o_timed : {8{1'bz}};

endmodule
