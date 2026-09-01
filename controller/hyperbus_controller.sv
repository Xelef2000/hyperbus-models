`timescale 1ps/1ps

// SystemVerilog pin wrapper for the cycle-scheduled C++ controller model.
/* verilator lint_off UNUSEDPARAM */
module hyperbus_controller #(
    parameter string CHIP_PROFILE = "generic_hyperram_controller"
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
    import "DPI-C" function bit hyperbus_controller_model_select_profile(input string name);
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
        if (!hyperbus_controller_model_select_profile(CHIP_PROFILE))
            $fatal(1, "Unknown HyperBus controller chip profile: %s", CHIP_PROFILE);
        hyperbus_controller_model_reset();
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
