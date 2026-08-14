`timescale 1ps/1ps

// Small transaction-level shell for the new cycle-scheduled controller model.
// `request_*` describes one HyperBus request. Linear memory bursts with
// normal initial latency are implemented; other operations return an error.
/* verilator lint_off UNUSEDPARAM */
module hyperbus_controller #(
    // Device profile. Parameters marked future are exposed now so a board can
    // describe any compliant slave before the corresponding controller state
    // machine support is added.
    parameter logic [15:0] IDENTIFICATION_REGISTER0_RESET = 16'h0c81,
    parameter logic [15:0] IDENTIFICATION_REGISTER1_RESET = 16'h0001,
    parameter logic [15:0] CONFIGURATION_REGISTER0_RESET = 16'h8f8f,
    parameter logic [15:0] CONFIGURATION_REGISTER1_RESET = 16'hffc1,
    parameter bit AUTO_PROFILE_DISCOVERY = 1'b0,
    parameter bit ADOPT_DISCOVERED_CR0 = 1'b0,
    parameter bit FIXED_LATENCY_RWDS_HIGH = 1'b1, // Future policy check.
    parameter bit VARIABLE_LATENCY_SUPPORTED = 1'b0, // Future.
    parameter int unsigned REFRESH_INTERVAL_4X_TICKS = 0, // Future.
    parameter int unsigned REFRESH_BUSY_4X_TICKS = 0, // Future.
    parameter bit ZERO_LATENCY_MEMORY_WRITES = 1'b0,
    parameter bit ZERO_LATENCY_REGISTER_WRITES = 1'b0,
    parameter bit ZERO_LATENCY_WRITE_RWDS_LOW = 1'b0,
    parameter int unsigned T_RWR_4X_TICKS = 0, // Future.
    parameter int unsigned T_CSS_4X_TICKS = 0, // Future.
    parameter int unsigned T_RESET_RECOVERY_4X_TICKS = 0, // Future.
    parameter bit DEEP_POWER_DOWN_SUPPORTED = 1'b0, // Future.
    parameter int unsigned T_DPD_ENTRY_4X_TICKS = 0, // Future.
    parameter int unsigned T_DPD_EXIT_4X_TICKS = 0, // Future.
    parameter int unsigned T_CSDPD_4X_TICKS = 0, // Future.
    parameter bit HYBRID_SLEEP_SUPPORTED = 1'b0, // Future.
    parameter int unsigned T_HS_ENTRY_4X_TICKS = 0, // Future.
    parameter int unsigned T_HS_EXIT_4X_TICKS = 0, // Future.
    parameter int unsigned T_CSHS_4X_TICKS = 0, // Future.
    parameter bit DIFFERENTIAL_CLOCK_MODE = 1'b0, // Future validation.
    parameter int unsigned T_CA_SETUP_4X_TICKS = 0, // Future.
    parameter int unsigned T_CA_HOLD_4X_TICKS = 0, // Future.
    parameter int unsigned T_WRITE_SETUP_4X_TICKS = 0, // Future.
    parameter int unsigned T_WRITE_HOLD_4X_TICKS = 0, // Future.
    parameter int unsigned MEMORY_DENSITY_BYTES = 0,
    parameter bit ADDRESS_ROLLOVER = 1'b1,
    parameter bit INTER_WORD_VARIABLE_LATENCY_SUPPORTED = 1'b0,
    parameter int unsigned INTER_WORD_STALL_EDGES = 0,
    parameter int unsigned READ_STALL_TIMEOUT_EDGES = 64,
    parameter int unsigned T_READ_RWDS_QUALIFY_4X_TICKS = 0,
    parameter int unsigned T_READ_DQ_SAMPLE_DELAY_4X_TICKS = 0,
    parameter int unsigned READ_SAMPLE_TIMEOUT_4X_TICKS = 64,
    parameter int unsigned INITIAL_READ_STROBE_TIMEOUT_4X_TICKS = 0,
    parameter int unsigned READ_BYTE_B_TIMEOUT_4X_TICKS = 0,
    parameter bit UNEXPECTED_RWDS_FATAL = 1'b1,
    parameter int unsigned T_CK_HIGH_MIN_4X_TICKS = 0, // Future.
    parameter int unsigned T_CK_LOW_MIN_4X_TICKS = 0 // Future.
) (
    input  logic        clk,
    input  logic        clk_4x,
    input  logic        reset_n,
    output logic        init_valid_o,
    output logic        init_error_o,
    output logic [3:0]  init_code_o,

    input  logic        request_valid_i,
    output logic        request_ready_o,
    input  logic        request_write_i,
    input  logic        request_register_space_i,
    input  logic        request_linear_burst_i,
    input  logic [31:0] request_address_i,
    input  logic [15:0] request_words_i,

    input  logic        write_valid_i,
    output logic        write_ready_o,
    input  logic [15:0] write_data_i,
    input  logic [1:0]  write_mask_i,

    output logic        read_valid_o,
    input  logic        read_ready_i,
    output logic [15:0] read_data_o,
    output logic        read_last_o,

    output logic        response_valid_o,
    input  logic        response_ready_i,
    output logic        response_error_o,
    output logic [3:0]  response_code_o,

    output logic        hyper_cs_n_o,
    output logic        hyper_ck_o,
    output logic        hyper_ck_n_o,
    output logic        hyper_dq_oe_o,
    output logic [7:0]  hyper_dq_o,
    input  logic [7:0]  hyper_dq_i,
    output logic        hyper_rwds_oe_o,
    output logic        hyper_rwds_o,
    input  logic        hyper_rwds_i
);

    import "DPI-C" function void hyperbus_controller_model_reset();
    import "DPI-C" function void hyperbus_controller_model_set_configuration_register0(
        input int unsigned value
    );
    import "DPI-C" function void hyperbus_controller_model_set_zero_latency_write_support(
        input bit memory_writes, input bit register_writes, input bit rwds_low
    );
    import "DPI-C" function void hyperbus_controller_model_set_variable_read_latency_support(
        input bit variable_latency, input bit inter_word_latency,
        input int unsigned stall_timeout_edges
    );
    import "DPI-C" function void hyperbus_controller_model_set_timing_profile(
        input int unsigned t_rwr, input int unsigned t_css,
        input int unsigned t_ca_setup, input int unsigned t_ca_hold,
        input int unsigned t_write_setup, input int unsigned t_write_hold,
        input int unsigned t_ck_high_min, input int unsigned t_ck_low_min
    );
    import "DPI-C" function void hyperbus_controller_model_set_read_sampling_profile(
        input int unsigned rwds_qualify_ticks,
        input int unsigned dq_sample_delay_ticks,
        input int unsigned sample_timeout_ticks
    );
    import "DPI-C" function void hyperbus_controller_model_set_read_error_profile(
        input int unsigned initial_strobe_timeout_ticks,
        input int unsigned byte_b_timeout_ticks,
        input bit unexpected_rwds_fatal
    );
    import "DPI-C" function void hyperbus_controller_model_set_memory_geometry(
        input int unsigned bytes, input bit rollover
    );
    import "DPI-C" function void hyperbus_controller_model_set_reset_recovery(
        input int unsigned ticks
    );
    import "DPI-C" function void hyperbus_controller_model_set_profile_discovery(
        input bit enabled, input bit adopt_cr0, input int unsigned id0,
        input int unsigned id1, input int unsigned cr0, input int unsigned cr1
    );
    import "DPI-C" function void hyperbus_controller_model_tick_system(
        input bit reset_n, input bit request_valid, input bit request_write,
        input bit request_register_space, input bit request_linear_burst,
        input int unsigned request_address, input int unsigned request_words,
        input bit write_valid, input int unsigned write_data,
        input int unsigned write_mask, input bit read_ready, input bit response_ready
    );
    import "DPI-C" function void hyperbus_controller_model_tick_4x(
        input bit reset_n, input byte unsigned dq, input bit rwds
    );
    import "DPI-C" function bit hyperbus_controller_model_request_ready();
    import "DPI-C" function bit hyperbus_controller_model_write_ready();
    import "DPI-C" function bit hyperbus_controller_model_read_valid();
    import "DPI-C" function int unsigned hyperbus_controller_model_read_data();
    import "DPI-C" function bit hyperbus_controller_model_read_last();
    import "DPI-C" function bit hyperbus_controller_model_response_valid();
    import "DPI-C" function bit hyperbus_controller_model_response_error();
    import "DPI-C" function int unsigned hyperbus_controller_model_response_code();
    import "DPI-C" function bit hyperbus_controller_model_init_valid();
    import "DPI-C" function bit hyperbus_controller_model_init_error();
    import "DPI-C" function int unsigned hyperbus_controller_model_init_code();
    import "DPI-C" function bit hyperbus_controller_model_cs_n();
    import "DPI-C" function bit hyperbus_controller_model_ck();
    import "DPI-C" function bit hyperbus_controller_model_ck_n();
    import "DPI-C" function bit hyperbus_controller_model_dq_oe();
    import "DPI-C" function byte unsigned hyperbus_controller_model_dq_o();
    import "DPI-C" function bit hyperbus_controller_model_rwds_oe();
    import "DPI-C" function bit hyperbus_controller_model_rwds_o();

    task automatic sample_outputs();
        request_ready_o = hyperbus_controller_model_request_ready();
        write_ready_o = hyperbus_controller_model_write_ready();
        read_valid_o = hyperbus_controller_model_read_valid();
        read_data_o = hyperbus_controller_model_read_data()[15:0];
        read_last_o = hyperbus_controller_model_read_last();
        response_valid_o = hyperbus_controller_model_response_valid();
        response_error_o = hyperbus_controller_model_response_error();
        response_code_o = hyperbus_controller_model_response_code()[3:0];
        init_valid_o = hyperbus_controller_model_init_valid();
        init_error_o = hyperbus_controller_model_init_error();
        init_code_o = hyperbus_controller_model_init_code()[3:0];
        hyper_cs_n_o = hyperbus_controller_model_cs_n();
        hyper_ck_o = hyperbus_controller_model_ck();
        hyper_ck_n_o = hyperbus_controller_model_ck_n();
        hyper_dq_oe_o = hyperbus_controller_model_dq_oe();
        hyper_dq_o = hyperbus_controller_model_dq_o();
        hyper_rwds_oe_o = hyperbus_controller_model_rwds_oe();
        hyper_rwds_o = hyperbus_controller_model_rwds_o();
    endtask

    initial begin
        hyperbus_controller_model_reset();
        hyperbus_controller_model_set_configuration_register0(
            {16'b0, CONFIGURATION_REGISTER0_RESET}
        );
        hyperbus_controller_model_set_zero_latency_write_support(
            ZERO_LATENCY_MEMORY_WRITES, ZERO_LATENCY_REGISTER_WRITES,
            ZERO_LATENCY_WRITE_RWDS_LOW
        );
        hyperbus_controller_model_set_variable_read_latency_support(
            VARIABLE_LATENCY_SUPPORTED,
            INTER_WORD_VARIABLE_LATENCY_SUPPORTED,
            READ_STALL_TIMEOUT_EDGES
        );
        hyperbus_controller_model_set_timing_profile(
            T_RWR_4X_TICKS, T_CSS_4X_TICKS, T_CA_SETUP_4X_TICKS,
            T_CA_HOLD_4X_TICKS, T_WRITE_SETUP_4X_TICKS,
            T_WRITE_HOLD_4X_TICKS, T_CK_HIGH_MIN_4X_TICKS,
            T_CK_LOW_MIN_4X_TICKS
        );
        hyperbus_controller_model_set_read_sampling_profile(
            T_READ_RWDS_QUALIFY_4X_TICKS,
            T_READ_DQ_SAMPLE_DELAY_4X_TICKS,
            READ_SAMPLE_TIMEOUT_4X_TICKS
        );
        hyperbus_controller_model_set_read_error_profile(
            INITIAL_READ_STROBE_TIMEOUT_4X_TICKS,
            READ_BYTE_B_TIMEOUT_4X_TICKS,
            UNEXPECTED_RWDS_FATAL
        );
        hyperbus_controller_model_set_memory_geometry(
            MEMORY_DENSITY_BYTES, ADDRESS_ROLLOVER
        );
        hyperbus_controller_model_set_reset_recovery(T_RESET_RECOVERY_4X_TICKS);
        hyperbus_controller_model_set_profile_discovery(
            AUTO_PROFILE_DISCOVERY, ADOPT_DISCOVERED_CR0,
            {16'b0, IDENTIFICATION_REGISTER0_RESET},
            {16'b0, IDENTIFICATION_REGISTER1_RESET},
            {16'b0, CONFIGURATION_REGISTER0_RESET},
            {16'b0, CONFIGURATION_REGISTER1_RESET}
        );
        sample_outputs();
    end

    always_ff @(posedge clk) begin
        hyperbus_controller_model_tick_system(
            reset_n, request_valid_i, request_write_i,
            request_register_space_i, request_linear_burst_i,
            request_address_i, {16'b0, request_words_i}, write_valid_i,
            {16'b0, write_data_i}, {30'b0, write_mask_i}, read_ready_i,
            response_ready_i
        );
        sample_outputs();
    end

    always @(clk_4x) begin
        hyperbus_controller_model_tick_4x(reset_n, hyper_dq_i, hyper_rwds_i);
        sample_outputs();
    end

endmodule
/* verilator lint_on UNUSEDPARAM */
