`timescale 1ps/1ps

// Brings up the C++-backed controller wrapper on the same HyperBus pins as the
// HyperRAM slave.
module tb_controller;
    logic clk = 0, clk_4x = 0, reset_n = 0;
    logic request_valid = 0, request_write = 0, request_register_space = 0;
    logic request_linear_burst = 1;
    logic [31:0] request_address = 0;
    logic [15:0] request_words = 1;
    logic write_valid = 0;
    logic [15:0] write_data = 0;
    logic [1:0] write_mask = 0;
    logic read_ready = 1;
    logic response_ready = 0;
    logic request_ready, write_ready, read_valid, read_last;
    logic [15:0] read_data;
    logic response_valid, response_error;
    logic [3:0] response_code;
    logic cs_n, ck, ck_n, dq_oe, rwds_oe, rwds_o;
    logic [7:0] dq_o;
    tri [7:0] dq;
    tri rwds;
    logic [47:0] observed_ca = '0;
    int unsigned observed_ca_bytes = 0;
    int unsigned failures = 0;

    import "DPI-C" function byte unsigned hyperram_model_read_byte(
        input int unsigned address
    );

    initial forever #5000 clk = ~clk;
    initial forever #1250 clk_4x = ~clk_4x;

    assign dq = dq_oe ? dq_o : {8{1'bz}};
    assign rwds = rwds_oe ? rwds_o : 1'bz;

    // Capture the controller-driven CA stream on both DDR CK edges.
    always @(ck) begin
        #1;
        if (!cs_n && dq_oe && observed_ca_bytes < 6) begin
            observed_ca = {observed_ca[39:0], dq};
            ++observed_ca_bytes;
        end
    end

    hyperbus_controller #(.CHIP_PROFILE("generic_hyperram_controller")) controller (
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

    hyperram #(.CHIP_PROFILE("test_default")) memory (
        .clk, .clk_4x, .reset_n, .cs_n,
        .ck, .ck_n, .dq, .rwds
    );

    initial begin
        repeat (2) @(posedge clk);
        reset_n = 1;
        @(posedge clk); #1;
        if (!request_ready || !cs_n || ck || !ck_n || dq_oe || rwds_oe) begin
            $display("FAIL: controller shell is not electrically idle after reset");
            ++failures;
        end

        // Validation errors do not assert any HyperBus pins.
        request_words = 0;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        @(posedge clk); #1;
        if (!response_valid || !response_error || response_code != 3'd2) begin
            $display("FAIL: zero-length request did not return InvalidLength");
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;

        request_words = 1;
        request_address = 32'h0000_0041;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        @(posedge clk); #1;
        if (!response_valid || !response_error || response_code != 3'd3) begin
            $display("FAIL: odd byte address did not return UnalignedAddress");
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;

        // First implemented pin operation: a linear memory read emits CA
        // only, then returns a successful completion. Address 0x40 is byte
        // aligned and must encode as word address 0x20 in the CA stream.
        observed_ca = '0;
        observed_ca_bytes = 0;
        request_write = 0;
        request_register_space = 0;
        request_linear_burst = 1;
        request_address = 32'h0000_0040;
        request_words = 1;
        read_ready = 0;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (read_valid);
        #1;
        if (!read_last || read_data != 16'hffff ||
            observed_ca_bytes != 6 || observed_ca != 48'ha000_0004_0000 ||
            cs_n || ck || !ck_n || dq_oe || rwds_oe) begin
            $display("FAIL: fixed-latency read failed bytes=%0d ca=%h data=%h",
                     observed_ca_bytes, observed_ca, read_data);
            ++failures;
        end
        read_ready = 1;
        @(posedge clk); #1;
        read_ready = 0;
        wait (response_valid);
        #1;
        if (response_error || response_code != 3'd0 ||
            !cs_n || ck || !ck_n || dq_oe || rwds_oe) begin
            $display("FAIL: fixed-latency read did not terminate cleanly code=%0d",
                     response_code);
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;

        // A normal-latency write uses the same CA/latency sequence, then
        // takes RWDS ownership for its mask preamble and the two data bytes.
        request_write = 1;
        request_address = 32'h0000_0042;
        request_words = 1;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (write_ready);
        #1;
        if (!rwds_oe || rwds_o || dq_oe || cs_n || ck) begin
            $display("FAIL: write phase did not expose a Low RWDS preamble");
            ++failures;
        end
        write_data = 16'h1234;
        write_mask = 2'b00;
        write_valid = 1;
        @(posedge clk); #1;
        write_valid = 0;
        wait (response_valid);
        #1;
        if (response_error || response_code != 3'd0 ||
            {hyperram_model_read_byte(66), hyperram_model_read_byte(67)} != 16'h1234 ||
            !cs_n || ck || !ck_n || dq_oe || rwds_oe) begin
            $display("FAIL: fixed-latency write did not complete correctly (code=%0d data=%h)",
                     response_code,
                     {hyperram_model_read_byte(66), hyperram_model_read_byte(67)});
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;

        // A linear burst has one CA phase and one initial-latency interval.
        // Write three words with distinct masks, then read all three back.
        request_write = 1;
        request_address = 32'h0000_0050;
        request_words = 3;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;

        wait (write_ready);
        write_data = 16'h1122;
        write_mask = 2'b00;
        write_valid = 1;
        @(posedge clk); #1;
        write_valid = 0;

        wait (write_ready);
        write_data = 16'h3344;
        write_mask = 2'b10;
        write_valid = 1;
        @(posedge clk); #1;
        write_valid = 0;

        wait (write_ready);
        write_data = 16'h5566;
        write_mask = 2'b01;
        write_valid = 1;
        @(posedge clk); #1;
        write_valid = 0;
        wait (response_valid);
        #1;
        if (response_error || response_code != 3'd0 ||
            {hyperram_model_read_byte(80), hyperram_model_read_byte(81)} != 16'h1122 ||
            {hyperram_model_read_byte(82), hyperram_model_read_byte(83)} != 16'hff44 ||
            {hyperram_model_read_byte(84), hyperram_model_read_byte(85)} != 16'h55ff) begin
            $display("FAIL: linear burst write data/masks were not applied");
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;

        observed_ca = '0;
        observed_ca_bytes = 0;
        request_write = 0;
        read_ready = 0;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;

        wait (read_valid);
        #1;
        if (read_last || read_data != 16'h1122) begin
            $display("FAIL: first linear burst read word was data=%h last=%b",
                     read_data, read_last);
            ++failures;
        end
        read_ready = 1;
        @(posedge clk); #1;
        read_ready = 0;

        wait (read_valid);
        #1;
        if (read_last || read_data != 16'hff44) begin
            $display("FAIL: second linear burst read word was data=%h last=%b",
                     read_data, read_last);
            ++failures;
        end
        read_ready = 1;
        @(posedge clk); #1;
        read_ready = 0;

        wait (read_valid);
        #1;
        if (!read_last || read_data != 16'h55ff ||
            observed_ca_bytes != 6 || observed_ca != 48'ha000_0005_0000) begin
            $display("FAIL: final linear burst read failed bytes=%0d ca=%h data=%h last=%b",
                     observed_ca_bytes, observed_ca, read_data, read_last);
            ++failures;
        end
        read_ready = 1;
        @(posedge clk); #1;
        read_ready = 0;
        wait (response_valid);
        #1;
        if (response_error || response_code != 3'd0 ||
            !cs_n || ck || !ck_n || dq_oe || rwds_oe) begin
            $display("FAIL: linear burst read did not terminate cleanly code=%0d",
                     response_code);
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;

        // Register space uses the same transaction phases as memory, with
        // CA[46] set. Read ID0, then change only CR0 Byte B and read it back.
        observed_ca = '0;
        observed_ca_bytes = 0;
        request_write = 0;
        request_register_space = 1;
        request_address = 32'h0000_0000;
        request_words = 1;
        read_ready = 0;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (read_valid);
        #1;
        if (!read_last || read_data != 16'h0c81 ||
            observed_ca_bytes != 6 || observed_ca != 48'he000_0000_0000) begin
            $display("FAIL: register ID0 read failed bytes=%0d ca=%h data=%h",
                     observed_ca_bytes, observed_ca, read_data);
            ++failures;
        end
        read_ready = 1;
        @(posedge clk); #1;
        read_ready = 0;
        wait (response_valid);
        if (response_error || response_code != 3'd0) begin
            $display("FAIL: register ID0 read returned code=%0d", response_code);
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;

        observed_ca = '0;
        observed_ca_bytes = 0;
        request_write = 1;
        request_address = 32'h0000_1000; // CR0 word address 0x800.
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (write_ready);
        // Mask Byte A and replace only CR0 Byte B: 8f8f -> 8f7e. This
        // changes the initial-latency code from 13 to 12 CK cycles.
        write_data = 16'h007e;
        write_mask = 2'b10;
        write_valid = 1;
        @(posedge clk); #1;
        write_valid = 0;
        wait (response_valid);
        #1;
        if (response_error || response_code != 3'd0 ||
            observed_ca_bytes != 6 || observed_ca != 48'h6000_0100_0000) begin
            $display("FAIL: register CR0 write failed bytes=%0d ca=%h code=%0d",
                     observed_ca_bytes, observed_ca, response_code);
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;

        observed_ca = '0;
        observed_ca_bytes = 0;
        request_write = 0;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (read_valid);
        #1;
        if (!read_last || read_data != 16'h8f7e ||
            observed_ca_bytes != 6 || observed_ca != 48'he000_0100_0000) begin
            $display("FAIL: register CR0 readback failed bytes=%0d ca=%h data=%h",
                     observed_ca_bytes, observed_ca, read_data);
            ++failures;
        end
        read_ready = 1;
        @(posedge clk); #1;
        read_ready = 0;
        wait (response_valid);
        if (response_error || response_code != 3'd0) begin
            $display("FAIL: register CR0 readback returned code=%0d", response_code);
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;
        request_register_space = 0;

        // CR0's new latency applies after its write transaction. This read
        // catches a controller which still waits using the reset CR0 value:
        // the earlier word at byte address 0x42 must be captured first.
        observed_ca = '0;
        observed_ca_bytes = 0;
        request_write = 0;
        request_address = 32'h0000_0042;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (read_valid);
        #1;
        if (!read_last || read_data != 16'h1234 ||
            observed_ca_bytes != 6 || observed_ca != 48'ha000_0004_0001) begin
            $display("FAIL: post-CR0 latency read failed bytes=%0d ca=%h data=%h",
                     observed_ca_bytes, observed_ca, read_data);
            ++failures;
        end
        read_ready = 1;
        @(posedge clk); #1;
        read_ready = 0;
        wait (response_valid);
        if (response_error || response_code != 3'd0) begin
            $display("FAIL: post-CR0 latency read returned code=%0d", response_code);
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;

        // CR0[1:0]=2 selected an eight-word (16-byte) wrapped window above.
        // Starting at word 39 must continue at words 32 and 33, not 40/41.
        request_write = 1;
        request_linear_burst = 0;
        request_address = 32'h0000_004e;
        request_words = 3;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (write_ready);
        write_data = 16'h1111;
        write_mask = 2'b00;
        write_valid = 1;
        @(posedge clk); #1;
        write_valid = 0;
        wait (write_ready);
        write_data = 16'h2222;
        write_valid = 1;
        @(posedge clk); #1;
        write_valid = 0;
        wait (write_ready);
        write_data = 16'h3333;
        write_valid = 1;
        @(posedge clk); #1;
        write_valid = 0;
        wait (response_valid);
        #1;
        if (response_error ||
            {hyperram_model_read_byte(78), hyperram_model_read_byte(79)} != 16'h1111 ||
            {hyperram_model_read_byte(64), hyperram_model_read_byte(65)} != 16'h2222 ||
            {hyperram_model_read_byte(66), hyperram_model_read_byte(67)} != 16'h3333) begin
            $display("FAIL: wrapped write did not follow the CR0 window");
            ++failures;
        end
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;

        observed_ca = '0;
        observed_ca_bytes = 0;
        request_write = 0;
        read_ready = 0;
        request_valid = 1;
        @(posedge clk); #1;
        request_valid = 0;
        wait (read_valid);
        #1;
        if (read_last || read_data != 16'h1111) begin
            $display("FAIL: first wrapped read word was data=%h last=%b",
                     read_data, read_last);
            ++failures;
        end
        read_ready = 1;
        @(posedge clk); #1;
        read_ready = 0;
        wait (read_valid);
        #1;
        if (read_last || read_data != 16'h2222) begin
            $display("FAIL: second wrapped read word was data=%h last=%b",
                     read_data, read_last);
            ++failures;
        end
        read_ready = 1;
        @(posedge clk); #1;
        read_ready = 0;
        wait (read_valid);
        #1;
        if (!read_last || read_data != 16'h3333 ||
            observed_ca_bytes != 6 || observed_ca != 48'h8000_0004_0007) begin
            $display("FAIL: wrapped read failed bytes=%0d ca=%h data=%h last=%b",
                     observed_ca_bytes, observed_ca, read_data, read_last);
            ++failures;
        end
        read_ready = 1;
        @(posedge clk); #1;
        read_ready = 0;
        wait (response_valid);
        response_ready = 1;
        @(posedge clk); #1;
        response_ready = 0;
        request_linear_burst = 1;

        if (failures == 0)
            $display("PASS: controller and HyperRAM slave support linear, wrapped, and register transactions.");
        else
            $display("FAIL: %0d controller-shell check(s).", failures);
        $finish;
    end
endmodule
