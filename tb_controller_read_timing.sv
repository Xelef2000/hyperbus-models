`timescale 1ps/1ps

// Read timing fixture: DQ becomes valid two 4x ticks after RWDS changes.
// The controller must qualify the strobe and sample after the configured
// offset, rather than treating the strobe edge as an ideal simultaneous DQ
// sample point.
module tb_controller_read_timing;
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
    int unsigned failures = 0;

    initial forever #5000 clk = ~clk;
    initial forever #1250 clk_4x = ~clk_4x;
    assign dq = dq_oe ? dq_o : {8{1'bz}};
    assign rwds = rwds_oe ? rwds_o : 1'bz;

    hyperbus_controller #(.CHIP_PROFILE("test_read_timing")) controller (
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

    hyperram #(.CHIP_PROFILE("test_read_timing")) memory (
        .clk, .clk_4x, .reset_n, .cs_n, .ck, .ck_n, .dq, .rwds
    );

    task automatic wait_for_response();
        wait (response_valid);
        #1;
        if (response_error || response_code != 3'd0) begin
            $display("FAIL: transaction response error=%b code=%0d",
                     response_error, response_code);
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;
    endtask

    task automatic write_word(input logic [31:0] address,
                              input logic [15:0] value);
        wait (request_ready);
        request_write = 1;
        request_address = address;
        request_words = 1;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (write_ready);
        write_data = value;
        write_mask = 2'b00;
        write_valid = 1;
        @(posedge clk); #1;
        write_valid = 0;
        wait_for_response();
    endtask

    task automatic read_and_expect(input logic [31:0] address,
                                   input logic [15:0] expected);
        wait (request_ready);
        request_write = 0;
        request_address = address;
        request_words = 1;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (read_valid);
        #1;
        if (read_data != expected || !read_last) begin
            $display("FAIL: delayed read expected=%h/1 got=%h/%b",
                     expected, read_data, read_last);
            ++failures;
        end
        read_ready = 1;
        @(posedge clk); #1;
        read_ready = 0;
        wait_for_response();
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset_n = 1;
        write_word(32'h0000_0040, 16'h1234);
        read_and_expect(32'h0000_0040, 16'h1234);
        if (failures == 0)
            $display("PASS: controller samples delayed read DQ after qualified RWDS.");
        else
            $display("FAIL: %0d controller read-timing check(s).", failures);
        $finish;
    end
endmodule
