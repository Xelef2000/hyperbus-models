`timescale 1ps/1ps

// Pin-timestamp checks for controller-owned profile timing.
module tb_controller_timing;
    localparam time Tick4x = 1250ps;
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
    time cs_assert_time = 0, cs_release_time = 0, first_ck_rise_time = 0;
    time last_ck_edge_time = 0;
    int unsigned failures = 0;

    initial forever #5000 clk = ~clk;
    initial forever #1250 clk_4x = ~clk_4x;
    assign dq = dq_oe ? dq_o : {8{1'bz}};
    assign rwds = rwds_oe ? rwds_o : 1'bz;

    always @(negedge cs_n) begin
        cs_assert_time = $time;
        first_ck_rise_time = 0;
        last_ck_edge_time = 0;
        if (cs_release_time != 0 && $time - cs_release_time < 6 * Tick4x) begin
            $display("FAIL: tRWR was %0t, expected at least %0t",
                     $time - cs_release_time, 6 * Tick4x);
            ++failures;
        end
    end
    always @(posedge cs_n) cs_release_time = $time;
    always @(ck) if (!cs_n) begin
        if (ck && first_ck_rise_time == 0) begin
            first_ck_rise_time = $time;
            if ($time - cs_assert_time < 4 * Tick4x) begin
                $display("FAIL: tCSS was %0t, expected at least %0t",
                         $time - cs_assert_time, 4 * Tick4x);
                ++failures;
            end
        end
        if (last_ck_edge_time != 0) begin
            const time required = ck ? 4 * Tick4x : 4 * Tick4x;
            if ($time - last_ck_edge_time < required) begin
                $display("FAIL: CK phase was %0t, expected at least %0t",
                         $time - last_ck_edge_time, required);
                ++failures;
            end
        end
        last_ck_edge_time = $time;
    end

    hyperbus_controller #(.CHIP_PROFILE("test_timing")) controller (
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

    hyperram #(.CHIP_PROFILE("test_timing")) memory (
        .clk, .clk_4x, .reset_n, .cs_n, .ck, .ck_n, .dq, .rwds
    );

    task automatic issue_write(input logic [31:0] address,
                               input logic [15:0] value);
        wait (request_ready);
        request_address = address;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (write_ready);
        write_data = value;
        write_mask = 2'b00;
        write_valid = 1;
        @(posedge clk); #1;
        write_valid = 0;
        wait (response_valid);
        if (response_error) begin
            $display("FAIL: timed write returned error code=%0d", response_code);
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset_n = 1;
        issue_write(32'h0000_0040, 16'h1234);
        issue_write(32'h0000_0042, 16'h5678);
        if (failures == 0)
            $display("PASS: controller timing profile deadlines.");
        else
            $display("FAIL: %0d timing-profile check(s).", failures);
        $finish;
    end
endmodule
