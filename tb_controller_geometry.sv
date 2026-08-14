`timescale 1ps/1ps

// Finite-density controller profile checks. The eight-byte device has four
// words, making the exact boundary and a crossing burst easy to observe.
module tb_controller_geometry;
    logic clk = 0, clk_4x = 0, reset_n = 0;
    logic request_valid = 0, request_write = 1, request_register_space = 0;
    logic request_linear_burst = 1;
    logic [31:0] request_address = 0;
    logic [15:0] request_words = 1;
    logic write_valid = 0;
    logic [15:0] write_data = 0;
    logic [1:0] write_mask = 0;
    logic read_ready = 0, response_ready = 0;
    logic request_ready, write_ready, read_valid, read_last;
    logic [15:0] read_data;
    logic response_valid, response_error;
    logic [3:0] response_code;
    logic cs_n, ck, ck_n, dq_oe, rwds_oe, rwds_o;
    logic [7:0] dq_o;
    tri [7:0] dq;
    tri rwds;
    int unsigned failures = 0, cs_assertions = 0, assertions_before = 0;

    initial forever #5000 clk = ~clk;
    initial forever #1250 clk_4x = ~clk_4x;
    initial begin
        #2000000;
        $fatal(1, "geometry fixture timed out cs=%b response=%b code=%0d read_valid=%b",
               cs_n, response_valid, response_code, read_valid);
    end
    assign dq = dq_oe ? dq_o : {8{1'bz}};
    assign rwds = rwds_oe ? rwds_o : 1'bz;
    always @(negedge cs_n) ++cs_assertions;

    hyperbus_controller #(
        .CONFIGURATION_REGISTER0_RESET(16'h8f8f),
        .MEMORY_DENSITY_BYTES(8), .ADDRESS_ROLLOVER(1'b0),
        .UNEXPECTED_RWDS_FATAL(1'b0)
    ) controller (
        .clk, .clk_4x, .reset_n,
        .request_valid_i(request_valid), .request_ready_o(request_ready),
        .request_write_i(request_write),
        .request_register_space_i(request_register_space),
        .request_linear_burst_i(request_linear_burst),
        .request_address_i(request_address), .request_words_i(request_words),
        .write_valid_i(write_valid), .write_ready_o(write_ready),
        .write_data_i(write_data), .write_mask_i(write_mask),
        .read_valid_o(read_valid), .read_ready_i(read_ready),
        .read_data_o(read_data), .read_last_o(read_last),
        .response_valid_o(response_valid), .response_ready_i(response_ready),
        .response_error_o(response_error), .response_code_o(response_code),
        .hyper_cs_n_o(cs_n), .hyper_ck_o(ck), .hyper_ck_n_o(ck_n),
        .hyper_dq_oe_o(dq_oe), .hyper_dq_o(dq_o), .hyper_dq_i(dq),
        .hyper_rwds_oe_o(rwds_oe), .hyper_rwds_o(rwds_o), .hyper_rwds_i(rwds)
    );

    hyperram #(
        .CONFIGURATION_REGISTER0_RESET(16'h8f8f),
        .FIXED_LATENCY_RWDS_HIGH(1'b0),
        .MEMORY_DENSITY_BYTES(8), .ADDRESS_ROLLOVER(1'b0),
        .T_DQ_OUTPUT_DELAY(0), .T_RWDS_OUTPUT_DELAY(0),
        .T_DQ_OUTPUT_DISABLE_DELAY(0), .T_RWDS_OUTPUT_DISABLE_DELAY(0)
    ) memory (.clk, .clk_4x, .reset_n, .cs_n, .ck, .ck_n, .dq, .rwds);

    task automatic consume_response(input bit expected_error,
                                    input logic [3:0] expected_code);
        wait (response_valid); #1;
        if (response_error != expected_error || response_code != expected_code) begin
            $display("FAIL: response expected error/code=%b/%0d got=%b/%0d",
                     expected_error, expected_code, response_error, response_code);
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;
    endtask

    task automatic write_four_words();
        logic [15:0] value;
        wait (request_ready);
        request_write = 1; request_register_space = 0;
        request_address = 0; request_words = 4; request_valid = 1;
        @(posedge clk); #1; request_valid = 0;
        for (int i = 0; i < 4; ++i) begin
            value = 16'(16'h1000 + i);
            wait (write_ready);
            write_data = value; write_mask = 0; write_valid = 1;
            @(posedge clk); #1; write_valid = 0;
        end
        consume_response(0, 0);
    endtask

    task automatic read_four_words();
        wait (request_ready);
        request_write = 0; request_register_space = 0;
        request_address = 0; request_words = 4; request_valid = 1;
        @(posedge clk); #1; request_valid = 0;
        for (int i = 0; i < 4; ++i) begin
            wait (read_valid); #1;
            if (read_data != 16'(16'h1000 + i) || read_last != (i == 3)) begin
                $display("FAIL: boundary read word %0d got=%h last=%b", i, read_data, read_last);
                ++failures;
            end
            read_ready = 1;
            @(posedge clk); #1; read_ready = 0;
        end
        consume_response(0, 0);
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset_n = 1;
        write_four_words();
        read_four_words();

        // Address 6 is valid, but a two-word burst extends through byte 9.
        wait (request_ready);
        request_write = 0; request_register_space = 0;
        request_address = 6; request_words = 2;
        assertions_before = cs_assertions;
        request_valid = 1;
        @(posedge clk); #1; request_valid = 0;
        consume_response(1, 4'd8);
        if (cs_assertions != assertions_before) begin
            $display("FAIL: out-of-range request asserted CS#");
            ++failures;
        end

        // Register addresses are outside the memory geometry by design.
        wait (request_ready);
        request_register_space = 1; request_address = 0; request_words = 1;
        request_valid = 1;
        @(posedge clk); #1; request_valid = 0;
        wait (read_valid); #1;
        if (read_data != 16'h0c81) begin
            $display("FAIL: register read was incorrectly geometry-rejected data=%h", read_data);
            ++failures;
        end
        read_ready = 1;
        @(posedge clk); #1; read_ready = 0;
        consume_response(0, 0);

        if (failures == 0)
            $display("PASS: controller finite geometry validation.");
        else
            $display("FAIL: %0d geometry check(s).", failures);
        $finish;
    end
endmodule
