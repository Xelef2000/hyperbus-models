`timescale 1ps/1ps

// Fault-injection fixture for controller read-strobe recovery. No slave is
// instantiated: RWDS is driven explicitly to create missing read strobes.
module tb_controller_read_error;
    logic clk = 0, clk_4x = 0, reset_n = 0;
    logic request_valid = 0, request_write = 0, request_register_space = 0;
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
    logic slave_rwds = 0;
    tri [7:0] dq;
    tri rwds;
    int unsigned failures = 0;
    int unsigned clock_edges = 0;

    initial forever #5000 clk = ~clk;
    initial forever #1250 clk_4x = ~clk_4x;
    initial begin
        #2000000;
        $display("FAIL: read-error fixture timed out cs=%b edges=%0d response=%b",
                 cs_n, clock_edges, response_valid);
        $finish;
    end
    assign dq = dq_oe ? dq_o : {8{1'bz}};
    assign rwds = rwds_oe ? rwds_o : slave_rwds;

    always @(negedge cs_n) clock_edges = 0;
    always @(ck) if (!cs_n) ++clock_edges;
    always @(posedge read_valid) begin
        $display("FAIL: aborted read published data=%h last=%b", read_data, read_last);
        ++failures;
    end

    hyperbus_controller #(.CHIP_PROFILE("test_read_error")) controller (
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

    task automatic start_read();
        wait (request_ready);
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
    endtask

    task automatic expect_strobe_timeout(input string label);
        wait (response_valid);
        #1;
        if (!response_error || response_code != 3'd6 ||
            !cs_n || ck || !ck_n || dq_oe || rwds_oe) begin
            $display("FAIL: %s error=%b code=%0d pins cs=%b ck=%b dq_oe=%b rwds_oe=%b",
                     label, response_error, response_code, cs_n, ck, dq_oe, rwds_oe);
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset_n = 1;

        // RWDS stays Low: no Byte-A strobe arrives within the profile bound.
        start_read();
        expect_strobe_timeout("missing Byte-A");

        // Send Byte A at the start of the data phase, then hold RWDS High so
        // Byte B never arrives. CA has six edges and normal CR0 latency has
        // twenty-six, so edge 32 is the transition into ReadClock.
        slave_rwds = 0;
        fork
            begin
                wait (!cs_n);
                wait (clock_edges >= 32);
                #1 slave_rwds = 1;
            end
            begin
                start_read();
                expect_strobe_timeout("missing Byte-B");
            end
        join
        slave_rwds = 0;

        if (failures == 0)
            $display("PASS: controller aborts malformed reads without publishing data.");
        else
            $display("FAIL: %0d controller read-error check(s).", failures);
        $finish;
    end
endmodule
