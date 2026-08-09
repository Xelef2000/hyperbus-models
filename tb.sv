`timescale 1ps/1ps

module tb;

    // The reference comparison uses a deterministic 13-clock, fixed-low
    // profile. A separate test below changes CR0 through Register Space.
    localparam int unsigned InitialLatencyEdges = 26;

    logic clk = 1'b0;
    logic clk_4x = 1'b0;
    logic reset_n = 1'b1;
    logic cs_n = 1'b1;
    logic ck = 1'b0;
    logic ck_n;
    logic host_dq_oe = 1'b0;
    logic [7:0] host_dq = '0;
    logic host_rwds_oe = 1'b0;
    logic host_rwds = 1'b0;

    tri [7:0] infineon_dq;
    tri infineon_rwds;
    tri [7:0] model_dq;
    tri model_rwds;

    logic [15:0] infineon_word;
    logic [15:0] model_word;
    int unsigned discrepancies = 0;
    wire reset_n_wire;

    import "DPI-C" function byte unsigned hyperram_model_read_byte(
        input int unsigned address
    );
    import "DPI-C" function bit hyperram_model_rwds_oe();
    import "DPI-C" function bit hyperram_model_rwds_o();
    import "DPI-C" function int unsigned hyperram_model_read_configuration_register0();
    import "DPI-C" function bit hyperram_model_refresh_active();
    import "DPI-C" function void hyperram_model_set_zero_latency_support(
        input bit memory_writes,
        input bit register_writes,
        input bit rwds_low
    );

    assign ck_n = ~ck;
    assign reset_n_wire = reset_n;
    assign infineon_dq = host_dq_oe ? host_dq : {8{1'bz}};
    assign model_dq = host_dq_oe ? host_dq : {8{1'bz}};
    assign infineon_rwds = host_rwds_oe ? host_rwds : 1'bz;
    assign model_rwds = host_rwds_oe ? host_rwds : 1'bz;

    initial forever #5000 clk = ~clk;
    initial forever #1250 clk_4x = ~clk_4x;

    s27kl0642 infineon_model (
        .DQ7(infineon_dq[7]), .DQ6(infineon_dq[6]),
        .DQ5(infineon_dq[5]), .DQ4(infineon_dq[4]),
        .DQ3(infineon_dq[3]), .DQ2(infineon_dq[2]),
        .DQ1(infineon_dq[1]), .DQ0(infineon_dq[0]),
        .RWDS(infineon_rwds),
        .CSNeg(cs_n), .CK(ck), .CKn(ck_n), .RESETNeg(reset_n_wire)
    );

    hyperram #(
        .CONFIGURATION_REGISTER0_RESET(16'h8f8f),
        .FIXED_LATENCY_RWDS_HIGH(1'b0),
        .VARIABLE_LATENCY_SUPPORTED(1'b1),
        .REFRESH_INTERVAL_4X_TICKS(1000),
        .REFRESH_BUSY_4X_TICKS(100)
    ) model (
        .clk,
        .clk_4x,
        .reset_n,
        .cs_n,
        .ck,
        .ck_n,
        .rwds(model_rwds),
        .dq(model_dq)
    );

    task automatic send_byte(input logic [7:0] byte_value);
        host_dq = byte_value;
        #1000;
        ck = ~ck;
        #4000;
    endtask

    task automatic begin_transaction();
        cs_n = 1'b0;
        host_dq_oe = 1'b1;
        #4000; // tCSS before the first CK edge
    endtask

    task automatic end_transaction();
        host_dq_oe = 1'b0;
        host_rwds_oe = 1'b0;
        #1000;
        cs_n = 1'b1;
        #40000; // exceed the device's read/write recovery time
    endtask

    task automatic write_word(input logic [15:0] data,
                              input int unsigned latency_edges,
                              input bit expect_additional_latency);
        begin_transaction();

        if (!hyperram_model_rwds_oe() ||
            hyperram_model_rwds_o() != expect_additional_latency) begin
            $display("DISCREPANCY: model CA RWDS expected %b, got %b",
                     expect_additional_latency, hyperram_model_rwds_o());
            ++discrepancies;
        end

        // Linear-memory write CA for byte address 0.
        send_byte(8'h20);
        repeat (5) send_byte(8'h00);

        if (hyperram_model_rwds_oe()) begin
            $display("DISCREPANCY: model must release RWDS after write CA");
            ++discrepancies;
        end

        // RWDS belongs to the slave during CA.  The host takes ownership
        // afterward and drives a low mask preamble before write data.
        #20000; // covers core sampling plus the configured 5 ns turn-off
        if (model.rwds_oe_timed !== 1'b0) begin
            $display("DISCREPANCY: model RWDS output enable was not low before write preamble at %0t",
                     $time);
            ++discrepancies;
        end
        if (infineon_model.RWDSout_zd !== 1'bz)
            $display("REFERENCE LIMITATION: Infineon RWDS remains driven after CA at %0t", $time);
        host_rwds_oe = 1'b1;
        host_rwds = 1'b0;
        // The vendor model's RWDS timing remains unusable as a write-mask
        // input under this simulator. Constrain only its memory-oracle side;
        // the custom model receives the ordinary host-driven mask signal.
        force infineon_rwds = 1'b0;
        #1;
        if (model_rwds !== 1'b0) begin
            $display("DISCREPANCY: model RWDS did not accept the host mask preamble at %0t", $time);
            ++discrepancies;
        end
        repeat (latency_edges) send_byte(8'h00);
        send_byte(data[15:8]);
        send_byte(data[7:0]);
        release infineon_rwds;

        end_transaction();
    endtask

    task automatic write_configuration_register0(input logic [15:0] data,
                                                  input int unsigned latency_edges);
        begin_transaction();
        // Register-space, linear write at word address 0x800 (CR0).
        send_byte(8'h60);
        send_byte(8'h00);
        send_byte(8'h01);
        repeat (3) send_byte(8'h00);
        host_rwds_oe = 1'b1;
        host_rwds = 1'b0;
        repeat (latency_edges) send_byte(8'h00);
        send_byte(data[15:8]);
        send_byte(data[7:0]);
        end_transaction();
    endtask

    task automatic write_wrapped_boundary_words(input int unsigned word_address,
                                                input int unsigned latency_edges);
        logic [47:0] ca;
        begin_transaction();
        ca = '0;
        ca[44:16] = word_address >> 3;
        ca[2:0] = word_address[2:0];
        for (int i = 5; i >= 0; --i)
            send_byte(ca[i*8 +: 8]);
        #20000;
        host_rwds_oe = 1'b1;
        host_rwds = 1'b0;
        force infineon_rwds = 1'b0;
        repeat (latency_edges) send_byte(8'h00);
        send_byte(8'h12);
        send_byte(8'h34);
        send_byte(8'hab);
        send_byte(8'hcd);
        release infineon_rwds;
        end_transaction();
    endtask

    task automatic write_hybrid_boundary_words();
        logic [47:0] ca;
        begin_transaction();
        // Start at word 15 of a 16-word window. The seventeenth word must be
        // placed at word 16 after one complete wrapped window.
        ca = '0;
        ca[44:16] = 15 >> 3;
        ca[2:0] = 15 & 7;
        for (int i = 5; i >= 0; --i)
            send_byte(ca[i*8 +: 8]);
        #20000;
        host_rwds_oe = 1'b1;
        host_rwds = 1'b0;
        force infineon_rwds = 1'b0;
        repeat (14) send_byte(8'h00);
        for (int i = 0; i < 17; ++i) begin
            send_byte(8'ha0);
            send_byte(i[7:0]);
        end
        release infineon_rwds;
        end_transaction();
    endtask

    task automatic write_zero_latency_memory_word();
        begin_transaction();
        // Linear memory write to word address 2. Data starts on the first
        // edge after CA; RWDS remains High-Z and cannot mask either byte.
        send_byte(8'h20);
        repeat (4) send_byte(8'h00);
        send_byte(8'h02);
        if (hyperram_model_rwds_oe()) begin
            $display("DISCREPANCY: zero-latency write must not retain RWDS ownership");
            ++discrepancies;
        end
        send_byte(8'hde);
        send_byte(8'had);
        end_transaction();
    endtask

    task automatic read_models_word();
        begin_transaction();

        // Linear-memory read CA for byte address 0.
        send_byte(8'ha0);
        repeat (5) send_byte(8'h00);
        repeat (InitialLatencyEdges) send_byte(8'h00);
        host_dq_oe = 1'b0;

        // Advance two DDR data edges.  The deterministic comparison below
        // reads each model's memory; pin capture timing is a later test.
        #1000; ck = ~ck; #7000;
        ck = ~ck; #8000;

        end_transaction();
    endtask

    task automatic compare_word(input logic [15:0] expected);
        infineon_word = infineon_model.Mem[0][15:0];
        model_word = {hyperram_model_read_byte(0), hyperram_model_read_byte(1)};

        if (infineon_word !== expected) begin
            $display("DISCREPANCY: Infineon write: expected %h, got %h",
                     expected, infineon_word);
            ++discrepancies;
        end
        if (model_word !== expected) begin
            $display("DISCREPANCY: C++ model write: expected %h, got %h",
                     expected, model_word);
            ++discrepancies;
        end
        if (infineon_word !== model_word) begin
            $display("DISCREPANCY: models differ: Infineon=%h C++=%h",
                     infineon_word, model_word);
            ++discrepancies;
        end
    endtask

    initial begin
        // The vendor model requires its power-up interval before accesses.
        #350000000;
        #50000;

        write_word(16'h1234, InitialLatencyEdges, 1'b0);
        read_models_word();
        compare_word(16'h1234);

        // CR0[7:4] = 0010 selects seven clocks; CR0[3] = 0 enables variable
        // latency. Start the next transaction during a scheduled refresh.
        write_configuration_register0(16'h8f27, InitialLatencyEdges);
        if (hyperram_model_read_configuration_register0() != 16'h8f27) begin
            $display("DISCREPANCY: CR0 write was not retained by the model");
            ++discrepancies;
        end
        while (hyperram_model_refresh_active()) #1250;
        write_word(16'h3456, 14, 1'b0);
        model_word = {hyperram_model_read_byte(0), hyperram_model_read_byte(1)};
        if (model_word != 16'h3456) begin
            $display("DISCREPANCY: idle variable-latency write used the wrong count");
            ++discrepancies;
        end
        while (!hyperram_model_refresh_active()) #1250;
        write_word(16'h5678, 28, 1'b1);
        model_word = {hyperram_model_read_byte(0), hyperram_model_read_byte(1)};
        if (model_word != 16'h5678) begin
            $display("DISCREPANCY: refresh-selected latency did not time the next write");
            ++discrepancies;
        end

        while (hyperram_model_refresh_active()) #1250;
        write_wrapped_boundary_words(15, 14);
        if ({hyperram_model_read_byte(30), hyperram_model_read_byte(31)} != 16'h1234 ||
            {hyperram_model_read_byte(0), hyperram_model_read_byte(1)} != 16'habcd) begin
            $display("DISCREPANCY: wrapped burst did not wrap from word 15 to word 0");
            ++discrepancies;
        end

        // Exercise every CR0 legacy-wrapped window length at its boundary.
        write_configuration_register0(16'h8f8c, 14);
        write_wrapped_boundary_words(63, 26);
        if ({hyperram_model_read_byte(126), hyperram_model_read_byte(127)} != 16'h1234 ||
            {hyperram_model_read_byte(0), hyperram_model_read_byte(1)} != 16'habcd) begin
            $display("DISCREPANCY: 128-byte wrapped window failed");
            ++discrepancies;
        end
        write_configuration_register0(16'h8f8d, 26);
        write_wrapped_boundary_words(31, 26);
        if ({hyperram_model_read_byte(62), hyperram_model_read_byte(63)} != 16'h1234 ||
            {hyperram_model_read_byte(0), hyperram_model_read_byte(1)} != 16'habcd) begin
            $display("DISCREPANCY: 64-byte wrapped window failed");
            ++discrepancies;
        end
        write_configuration_register0(16'h8f8e, 26);
        write_wrapped_boundary_words(7, 26);
        if ({hyperram_model_read_byte(14), hyperram_model_read_byte(15)} != 16'h1234 ||
            {hyperram_model_read_byte(0), hyperram_model_read_byte(1)} != 16'habcd) begin
            $display("DISCREPANCY: 16-byte wrapped window failed");
            ++discrepancies;
        end

        // CR0[2]=0 enables one wrapped 32-byte window, then linear mode.
        write_configuration_register0(16'h8f23, 26);
        while (hyperram_model_refresh_active()) #1250;
        write_hybrid_boundary_words();
        if ({hyperram_model_read_byte(30), hyperram_model_read_byte(31)} != 16'ha000 ||
            {hyperram_model_read_byte(32), hyperram_model_read_byte(33)} != 16'ha010) begin
            $display("DISCREPANCY: hybrid burst did not transition to linear addressing");
            ++discrepancies;
        end

        hyperram_model_set_zero_latency_support(1'b1, 1'b1, 1'b0);
        write_zero_latency_memory_word();
        if ({hyperram_model_read_byte(4), hyperram_model_read_byte(5)} != 16'hdead) begin
            $display("DISCREPANCY: zero-latency write did not capture immediate data");
            ++discrepancies;
        end

        if (discrepancies == 0)
            $display("PASS: Infineon and C++ models agree for the basic word write/read.");
        else
            $display("FAIL: %0d discrepancy(s) detected.", discrepancies);
        $finish;
    end

endmodule
