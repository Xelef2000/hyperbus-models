`timescale 1ps/1ps

// Dedicated fixture: the same controller interface driving a device profile
// whose memory writes begin immediately after CA.
module tb_controller_zero_latency;
    logic clk = 0, clk_4x = 0, reset_n = 0;
    logic request_valid = 0, request_write = 0, request_register_space = 0;
    logic request_linear_burst = 1;
    logic [31:0] request_address = 0;
    logic [15:0] request_words = 1;
    logic write_valid = 0;
    logic [15:0] write_data = 0;
    logic [1:0] write_mask = 0;
    logic read_ready = 1, response_ready = 0;
    logic request_ready, write_ready, read_valid, read_last;
    logic [15:0] read_data;
    logic response_valid, response_error;
    logic [3:0] response_code;
    logic cs_n, ck, ck_n, dq_oe, rwds_oe, rwds_o;
    logic [7:0] dq_o;
    tri [7:0] dq;
    tri rwds;
    int unsigned failures = 0;

    import "DPI-C" function byte unsigned hyperram_model_read_byte(
        input int unsigned address
    );

    initial forever #5000 clk = ~clk;
    initial forever #1250 clk_4x = ~clk_4x;
    assign dq = dq_oe ? dq_o : {8{1'bz}};
    assign rwds = rwds_oe ? rwds_o : 1'bz;

    hyperbus_controller #(.CHIP_PROFILE("test_zero_latency")) controller (
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

    hyperram #(.CHIP_PROFILE("test_zero_latency")) memory (
        .clk, .clk_4x, .reset_n, .cs_n, .ck, .ck_n, .dq, .rwds
    );

    initial begin
        repeat (2) @(posedge clk);
        reset_n = 1;
        request_write = 1;
        request_address = 32'h0000_0040;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (write_ready);
        #1;
        if (cs_n || ck || dq_oe || rwds_oe) begin
            $display("FAIL: zero-latency write retained normal-latency RWDS preamble");
            ++failures;
        end
        // RWDS masks are ignored in zero-latency mode.
        write_data = 16'ha55a;
        write_mask = 2'b11;
        write_valid = 1;
        @(posedge clk); #1;
        write_valid = 0;
        wait (response_valid);
        #1;
        if (response_error || response_code != 3'd0 ||
            {hyperram_model_read_byte(64), hyperram_model_read_byte(65)} != 16'ha55a ||
            !cs_n || ck || !ck_n || dq_oe || rwds_oe) begin
            $display("FAIL: zero-latency write did not complete correctly data=%h",
                     {hyperram_model_read_byte(64), hyperram_model_read_byte(65)});
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;

        // Register-space zero-latency writes use the same immediate path.
        request_register_space = 1;
        request_address = 32'h0000_1002; // CR1 word address 0x801.
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (write_ready);
        #1;
        if (rwds_oe) begin
            $display("FAIL: zero-latency register write drove RWDS mask data");
            ++failures;
        end
        write_data = 16'hffc0;
        write_mask = 2'b11;
        write_valid = 1;
        @(posedge clk); #1;
        write_valid = 0;
        wait (response_valid);
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;

        request_write = 0;
        read_ready = 0;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (read_valid);
        #1;
        if (!read_last || read_data != 16'hffc0) begin
            $display("FAIL: zero-latency register write was not read back data=%h",
                     read_data);
            ++failures;
        end
        read_ready = 1;
        @(posedge clk); #1;
        read_ready = 0;
        wait (response_valid);
        response_ready = 1;
        @(posedge clk); #1;
        if (failures == 0)
            $display("PASS: zero-latency memory and register writes.");
        else
            $display("FAIL: %0d zero-latency controller check(s).", failures);
        $finish;
    end
endmodule
