`timescale 1ps/1ps

module tb;

    // Use a deterministic 13-clock, fixed-low profile. A separate test below
    // changes CR0 through Register Space.
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

    tri [7:0] model_dq;
    tri model_rwds;

    logic [15:0] model_word;
    int unsigned discrepancies = 0;
    int unsigned errors_before;
    logic [7:0] device_states_seen = '0;
    logic [63:0] device_transitions_seen = '0;
    int unsigned previous_device_state = 1;
    bit have_previous_device_state = 1'b0;
    logic previous_ck_for_assert = 1'b0;
    logic previous_model_rwds_for_assert = 1'b0;

    import "DPI-C" function byte unsigned hyperram_model_read_byte(
        input int unsigned address
    );
    import "DPI-C" function bit hyperram_model_dq_oe();
    import "DPI-C" function bit hyperram_model_rwds_oe();
    import "DPI-C" function bit hyperram_model_rwds_o();
    import "DPI-C" function int unsigned hyperram_model_read_configuration_register0();
    import "DPI-C" function int unsigned hyperram_model_read_configuration_register1();
    import "DPI-C" function bit hyperram_model_refresh_active();
    import "DPI-C" function int unsigned hyperram_model_device_state();
    import "DPI-C" function int unsigned hyperram_model_bus_state();
    import "DPI-C" function int unsigned hyperram_model_protocol_errors();
    import "DPI-C" function int unsigned hyperram_model_last_error_code();
    import "DPI-C" function longint unsigned hyperram_model_last_error_tick();
    import "DPI-C" function int unsigned hyperram_model_last_error_address();
    import "DPI-C" function void hyperram_model_set_zero_latency_support(
        input bit memory_writes,
        input bit register_writes,
        input bit rwds_low
    );
    import "DPI-C" function void hyperram_model_set_memory_geometry(
        input int unsigned bytes,
        input bit rollover
    );
    import "DPI-C" function void hyperram_model_set_interword_latency_for_test(
        input bit enabled, input int unsigned stall_edges
    );
    import "DPI-C" function void hyperram_model_force_refresh_collision_for_test();

    assign ck_n = ~ck;
    assign model_dq = host_dq_oe ? host_dq : {8{1'bz}};
    assign model_rwds = host_rwds_oe ? host_rwds : 1'bz;

    initial forever #5000 clk = ~clk;
    initial forever #1250 clk_4x = ~clk_4x;

    // Protocol assertions and functional coverage.  These observe the core's
    // logical ownership before the wrapper's configurable physical delays.
    always @(posedge clk_4x) begin
        int unsigned current_device_state;
        #1;
        assert (!(cs_n && (hyperram_model_dq_oe() || hyperram_model_rwds_oe())))
        else begin
            $display("ASSERTION: slave retained logical bus ownership while CS# was High");
            ++discrepancies;
        end
        assert (!(hyperram_model_dq_oe() && !hyperram_model_rwds_oe()))
        else begin
            $display("ASSERTION: DQ ownership without RWDS is not a legal slave phase");
            ++discrepancies;
        end
        if (hyperram_model_bus_state() == 3 && hyperram_model_rwds_oe() &&
            hyperram_model_rwds_o() != previous_model_rwds_for_assert) begin
            assert (ck != previous_ck_for_assert)
            else begin
                $display("ASSERTION: read RWDS changed without a CK edge");
                ++discrepancies;
            end
        end
        previous_ck_for_assert = ck;
        previous_model_rwds_for_assert = hyperram_model_rwds_o();

        current_device_state = hyperram_model_device_state();
        if (current_device_state < 8) begin
            device_states_seen[current_device_state] = 1'b1;
            if (have_previous_device_state && previous_device_state < 8)
                device_transitions_seen[previous_device_state * 8 + current_device_state] = 1'b1;
        end
        previous_device_state = current_device_state;
        have_previous_device_state = 1'b1;
    end

    hyperram #(
        .CONFIGURATION_REGISTER0_RESET(16'h8f8f),
        .FIXED_LATENCY_RWDS_HIGH(1'b0),
        .VARIABLE_LATENCY_SUPPORTED(1'b1),
        .REFRESH_INTERVAL_4X_TICKS(1000),
        .REFRESH_BUSY_4X_TICKS(100),
        .T_RWR_4X_TICKS(28),
        .T_RESET_RECOVERY_4X_TICKS(8),
        .RESET_CLEARS_MEMORY(1'b0),
        .DEEP_POWER_DOWN_SUPPORTED(1'b1),
        .T_DPD_ENTRY_4X_TICKS(8),
        .T_DPD_EXIT_4X_TICKS(16),
        .T_CSDPD_4X_TICKS(12),
        .HYBRID_SLEEP_SUPPORTED(1'b1),
        .T_HS_ENTRY_4X_TICKS(8),
        .T_HS_EXIT_4X_TICKS(16),
        .T_CSHS_4X_TICKS(12),
        .DIFFERENTIAL_CLOCK_MODE(1'b1),
        .T_CA_SETUP_4X_TICKS(1),
        .T_CA_HOLD_4X_TICKS(1),
        .T_WRITE_SETUP_4X_TICKS(1),
        .T_WRITE_HOLD_4X_TICKS(1)
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
        #2000;
        ck = ~ck;
        #3000;
    endtask

    task automatic advance_clock_edge();
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

    // End a command while allowing only enough time for the model to observe
    // CS# high.  This is used solely to exercise tRWR enforcement.
    task automatic end_transaction_without_recovery();
        host_dq_oe = 1'b0;
        host_rwds_oe = 1'b0;
        #1000;
        cs_n = 1'b1;
        #2000;
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
        host_rwds_oe = 1'b1;
        host_rwds = 1'b0;
        #1;
        if (model_rwds !== 1'b0) begin
            $display("DISCREPANCY: model RWDS did not accept the host mask preamble at %0t", $time);
            ++discrepancies;
        end
        repeat (latency_edges) send_byte(8'h00);
        send_byte(data[15:8]);
        send_byte(data[7:0]);
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

    task automatic write_configuration_register1(input logic [15:0] data,
                                                  input int unsigned latency_edges);
        begin_transaction();
        // Register-space, linear write at word address 0x801 (CR1).
        send_byte(8'h60);
        send_byte(8'h00);
        send_byte(8'h01);
        repeat (2) send_byte(8'h00);
        send_byte(8'h01);
        host_rwds_oe = 1'b1;
        host_rwds = 1'b0;
        repeat (latency_edges) send_byte(8'h00);
        send_byte(data[15:8]);
        send_byte(data[7:0]);
        end_transaction();
    endtask

    task automatic write_masked_configuration_register(
        input bit cr1,
        input logic [15:0] data,
        input bit mask_byte_a,
        input bit mask_byte_b,
        input int unsigned latency_edges
    );
        begin_transaction();
        send_byte(8'h60);
        send_byte(8'h00);
        send_byte(8'h01);
        repeat (2) send_byte(8'h00);
        send_byte(cr1 ? 8'h01 : 8'h00);
        host_rwds_oe = 1'b1;
        host_rwds = 1'b0;
        repeat (latency_edges) send_byte(8'h00);
        host_rwds = mask_byte_a;
        send_byte(data[15:8]);
        host_rwds = mask_byte_b;
        send_byte(data[7:0]);
        end_transaction();
    endtask

    task automatic write_masked_word();
        begin_transaction();
        // Linear write at word 3. Mask byte A, write byte B.
        send_byte(8'h20);
        repeat (4) send_byte(8'h00);
        send_byte(8'h03);
        #20000;
        host_rwds_oe = 1'b1;
        host_rwds = 1'b0;
        repeat (InitialLatencyEdges) send_byte(8'h00);
        host_rwds = 1'b1;
        send_byte(8'haa);
        host_rwds = 1'b0;
        send_byte(8'hbb);
        end_transaction();
    endtask

    task automatic write_mask_matrix();
        begin_transaction();
        // Linear write beginning at word 8.  Each pair below exercises one
        // complete RWDS Byte-A/Byte-B mask combination.
        send_byte(8'h20);
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'h01);
        repeat (2) send_byte(8'h00);
        #20000;
        host_rwds_oe = 1'b1;
        host_rwds = 1'b0;
        repeat (InitialLatencyEdges) send_byte(8'h00);

        // Neither masked, A masked, B masked, both masked, neither masked.
        host_rwds = 1'b0; send_byte(8'h11);
        host_rwds = 1'b0; send_byte(8'h22);
        host_rwds = 1'b1; send_byte(8'haa);
        host_rwds = 1'b0; send_byte(8'h33);
        host_rwds = 1'b0; send_byte(8'h44);
        host_rwds = 1'b1; send_byte(8'hbb);
        host_rwds = 1'b1; send_byte(8'hcc);
        host_rwds = 1'b1; send_byte(8'hdd);
        host_rwds = 1'b0; send_byte(8'h55);
        host_rwds = 1'b0; send_byte(8'h66);
        end_transaction();
    endtask

    task automatic write_density_rollover_words();
        begin_transaction();
        // Linear write at word 15: a 32-byte device wraps the next word to 0.
        send_byte(8'h20);
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'h01);
        send_byte(8'h00);
        send_byte(8'h07);
        #20000;
        host_rwds_oe = 1'b1;
        host_rwds = 1'b0;
        repeat (InitialLatencyEdges) send_byte(8'h00);
        send_byte(8'haa);
        send_byte(8'haa);
        send_byte(8'hbb);
        send_byte(8'hbb);
        end_transaction();
    endtask

    task automatic write_strict_out_of_range_word();
        begin_transaction();
        // Linear write at word 16, immediately beyond a 32-byte device.
        send_byte(8'h20);
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'h02);
        repeat (2) send_byte(8'h00);
        #20000;
        host_rwds_oe = 1'b1;
        host_rwds = 1'b0;
        repeat (InitialLatencyEdges) send_byte(8'h00);
        send_byte(8'hcc);
        send_byte(8'hdd);
        end_transaction();
    endtask

    task automatic issue_unsupported_register_write();
        begin_transaction();
        // Register-space write at unsupported word address 0x802.
        send_byte(8'h60);
        send_byte(8'h00);
        send_byte(8'h01);
        repeat (2) send_byte(8'h00);
        send_byte(8'h02);
        // The model is now in Ignore state; these would-be data bytes must
        // neither change state nor generate additional CA/data effects.
        send_byte(8'h12);
        send_byte(8'h34);
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
        repeat (latency_edges) send_byte(8'h00);
        send_byte(8'h12);
        send_byte(8'h34);
        send_byte(8'hab);
        send_byte(8'hcd);
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
        repeat (14) send_byte(8'h00);
        for (int i = 0; i < 17; ++i) begin
            send_byte(8'ha0);
            send_byte(i[7:0]);
        end
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
        // Even a driven-high RWDS is ignored in zero-latency mode.
        host_rwds_oe = 1'b1;
        host_rwds = 1'b1;
        send_byte(8'hde);
        send_byte(8'had);
        end_transaction();
    endtask

    task automatic read_models_word();
        begin_transaction();

        // Linear-memory read CA for byte address 0.
        send_byte(8'ha0);
        repeat (5) send_byte(8'h00);
        host_dq_oe = 1'b0;
        repeat (InitialLatencyEdges) advance_clock_edge();

        // Advance two DDR data edges.  The deterministic comparison below
        // reads each model's memory; pin capture timing is a later test.
        advance_clock_edge();
        advance_clock_edge();

        end_transaction();
    endtask

    task automatic verify_read_pin_timing(input logic [15:0] expected);
        ck = 1'b0;
        #5000;
        begin_transaction();
        // Linear-memory read CA for word zero, then release DQ immediately.
        send_byte(8'ha0);
        repeat (5) send_byte(8'h00);
        host_dq_oe = 1'b0;
        #2000;
        if (model.dq_oe_timed !== 1'b0) begin
            $display("DISCREPANCY: model drove DQ during read latency");
            ++discrepancies;
        end

        repeat (InitialLatencyEdges) advance_clock_edge();
        // The device owns DQ/RWDS after latency, but the first data byte is
        // not presented until the next valid DDR edge.
        #2000;
        if (model.dq_oe_timed !== 1'b1 || model.rwds_oe_timed !== 1'b1 ||
            model.dq_o_timed !== 8'h00 || model.rwds_o_timed !== 1'b0) begin
            $display("DISCREPANCY: read-output ownership did not begin in the expected idle phase");
            ++discrepancies;
        end
        advance_clock_edge();
        #2000;
        if (model.dq_o_timed !== expected[15:8] || model.rwds_o_timed !== 1'b1) begin
            $display("DISCREPANCY: first read byte/RWDS phase expected %h/1, got %h/%b",
                     expected[15:8], model.dq_o_timed, model.rwds_o_timed);
            ++discrepancies;
        end
        advance_clock_edge();
        #2000;
        if (model.dq_o_timed !== expected[7:0] || model.rwds_o_timed !== 1'b0) begin
            $display("DISCREPANCY: second read byte/RWDS phase expected %h/0, got %h/%b",
                     expected[7:0], model.dq_o_timed, model.rwds_o_timed);
            ++discrepancies;
        end

        #1000;
        cs_n = 1'b1;
        #8000;
        if (model.dq_oe_timed !== 1'b0 || model.rwds_oe_timed !== 1'b0) begin
            $display("DISCREPANCY: model did not release DQ/RWDS after read CS# deassertion");
            ++discrepancies;
        end
        #32000; // complete the profile's tRWR interval before the next test
    endtask

    task automatic compare_word(input logic [15:0] expected);
        model_word = {hyperram_model_read_byte(0), hyperram_model_read_byte(1)};

        if (model_word !== expected) begin
            $display("DISCREPANCY: C++ model write: expected %h, got %h",
                     expected, model_word);
            ++discrepancies;
        end
    endtask

    task automatic verify_state_coverage();
        begin
            // Device-state encodings are ResetRecovery=0 through
            // HybridSleepRecovery=7. The directed reset/DPD/sleep scenarios
            // below must cover every legal state and transition arc.
            if (device_states_seen != 8'hff ||
                !device_transitions_seen[1 * 8 + 0] ||
                !device_transitions_seen[0 * 8 + 1] ||
                !device_transitions_seen[1 * 8 + 2] ||
                !device_transitions_seen[2 * 8 + 3] ||
                !device_transitions_seen[3 * 8 + 4] ||
                !device_transitions_seen[4 * 8 + 1] ||
                !device_transitions_seen[1 * 8 + 5] ||
                !device_transitions_seen[5 * 8 + 6] ||
                !device_transitions_seen[6 * 8 + 7] ||
                !device_transitions_seen[7 * 8 + 1]) begin
                $display("DISCREPANCY: incomplete device-state coverage states=%b transitions=%h",
                         device_states_seen, device_transitions_seen);
                ++discrepancies;
            end
        end
    endtask

    initial begin
        #50000;

        write_word(16'h1234, InitialLatencyEdges, 1'b0);
        read_models_word();
        compare_word(16'h1234);
        verify_read_pin_timing(16'h1234);

        write_masked_word();
        if ({hyperram_model_read_byte(6), hyperram_model_read_byte(7)} != 16'hffbb) begin
            $display("DISCREPANCY: byte-A write mask was not honored");
            ++discrepancies;
        end
        write_mask_matrix();
        if ({hyperram_model_read_byte(16), hyperram_model_read_byte(17)} != 16'h1122 ||
            {hyperram_model_read_byte(18), hyperram_model_read_byte(19)} != 16'hff33 ||
            {hyperram_model_read_byte(20), hyperram_model_read_byte(21)} != 16'h44ff ||
            {hyperram_model_read_byte(22), hyperram_model_read_byte(23)} != 16'hffff ||
            {hyperram_model_read_byte(24), hyperram_model_read_byte(25)} != 16'h5566) begin
            $display("DISCREPANCY: RWDS mask matrix failed: %h %h %h %h %h",
                     {hyperram_model_read_byte(16), hyperram_model_read_byte(17)},
                     {hyperram_model_read_byte(18), hyperram_model_read_byte(19)},
                     {hyperram_model_read_byte(20), hyperram_model_read_byte(21)},
                     {hyperram_model_read_byte(22), hyperram_model_read_byte(23)},
                     {hyperram_model_read_byte(24), hyperram_model_read_byte(25)});
            ++discrepancies;
        end

        // A masked CR0 high byte must not turn a presented DPD request into
        // a side effect; a masked CR1 low byte must not request hybrid sleep.
        write_masked_configuration_register(1'b0, 16'h0f8c, 1'b1, 1'b0,
                                            InitialLatencyEdges);
        if (hyperram_model_read_configuration_register0() != 16'h8f8c ||
            hyperram_model_device_state() != 1) begin
            $display("DISCREPANCY: masked CR0 high byte changed DPD state or register value");
            ++discrepancies;
        end
        write_masked_configuration_register(1'b1, 16'hffe1, 1'b0, 1'b1,
                                            InitialLatencyEdges);
        if (hyperram_model_read_configuration_register1() != 16'hffc1 ||
            hyperram_model_device_state() != 1) begin
            $display("DISCREPANCY: masked CR1 low byte changed hybrid-sleep state or register value");
            ++discrepancies;
        end

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
        if (hyperram_model_protocol_errors() != 0) begin
            $display("DISCREPANCY: valid test traffic produced %0d protocol error(s)",
                     hyperram_model_protocol_errors());
            ++discrepancies;
        end

        // Finish a benign (intentionally incomplete) CA while CK is Low, then
        // issue another transaction immediately.  Its first CA edge occurs
        // well before this profile's 28-tick (35 ns) recovery interval.
        begin_transaction();
        send_byte(8'h20);
        send_byte(8'h00);
        end_transaction_without_recovery();
        errors_before = hyperram_model_protocol_errors();
        begin_transaction();
        send_byte(8'h20);
        send_byte(8'h00);
        end_transaction();
        if (hyperram_model_protocol_errors() != errors_before + 1) begin
            $display("DISCREPANCY: tRWR violation was not detected");
            ++discrepancies;
        end

        // Reset must abort the bus, restore volatile registers, retain memory
        // for this profile, and reject CS# during its recovery interval.
        reset_n = 1'b0;
        #10000;
        reset_n = 1'b1;
        errors_before = hyperram_model_protocol_errors();
        begin_transaction();
        send_byte(8'h20);
        send_byte(8'h00);
        end_transaction();
        if (hyperram_model_protocol_errors() != errors_before + 1) begin
            $display("DISCREPANCY: reset recovery traffic was not rejected");
            ++discrepancies;
        end
        if (hyperram_model_read_configuration_register0() != 16'h8f8f ||
            {hyperram_model_read_byte(4), hyperram_model_read_byte(5)} != 16'hdead) begin
            $display("DISCREPANCY: reset did not restore registers or retain memory");
            ++discrepancies;
        end

        // CR0[15] 1->0 requests DPD.  The device must release the bus, ignore
        // a too-short CS# pulse, then require both a valid wake pulse and the
        // configured wake-up recovery time before returning active.
        hyperram_model_set_zero_latency_support(1'b0, 1'b0, 1'b0);
        write_configuration_register0(16'h0f8f, InitialLatencyEdges);
        #12000;
        if (hyperram_model_device_state() != 3 || hyperram_model_dq_oe() ||
            hyperram_model_rwds_oe()) begin
            $display("DISCREPANCY: DPD device retained bus ownership");
            ++discrepancies;
        end
        errors_before = hyperram_model_protocol_errors();
        cs_n = 1'b0;
        #3000;
        cs_n = 1'b1;
        #2500; // allow the 4x model scheduler to observe CS# high
        if (hyperram_model_protocol_errors() != errors_before + 1 ||
            hyperram_model_device_state() != 3) begin
            $display("DISCREPANCY: short DPD wake pulse was not rejected (state=%0d)",
                     hyperram_model_device_state());
            ++discrepancies;
        end
        cs_n = 1'b0;
        #20000;
        cs_n = 1'b1;
        #2500; // allow the 4x model scheduler to observe CS# high
        errors_before = hyperram_model_protocol_errors();
        begin_transaction();
        send_byte(8'h20);
        send_byte(8'h00);
        end_transaction();
        if (hyperram_model_protocol_errors() != errors_before + 1) begin
            $display("DISCREPANCY: DPD wake recovery traffic was not rejected");
            ++discrepancies;
        end
        #25000;
        if (hyperram_model_device_state() != 1 ||
            hyperram_model_read_configuration_register0() != 16'h8f8f) begin
            $display("DISCREPANCY: DPD exit did not restore CR0[15] (state=%0d)",
                     hyperram_model_device_state());
            ++discrepancies;
        end

        // CR1[5] requests hybrid sleep.  It retains memory, uses a qualified
        // CS# wake pulse, and clears its request bit only after wake recovery.
        ck = 1'b0;
        #5000; // establish the required idle-low CK state before a new CA
        write_configuration_register1(16'hffe1, InitialLatencyEdges);
        if (hyperram_model_read_configuration_register1() != 16'hffe1) begin
            $display("DISCREPANCY: CR1 hybrid-sleep request was not retained (got %h)",
                     hyperram_model_read_configuration_register1());
            ++discrepancies;
        end
        #12000;
        if (hyperram_model_device_state() != 6 || hyperram_model_dq_oe() ||
            hyperram_model_rwds_oe()) begin
            $display("DISCREPANCY: hybrid-sleep device retained bus ownership (state=%0d CR1=%h)",
                     hyperram_model_device_state(),
                     hyperram_model_read_configuration_register1());
            ++discrepancies;
        end
        errors_before = hyperram_model_protocol_errors();
        cs_n = 1'b0;
        #3000;
        cs_n = 1'b1;
        #2500;
        if (hyperram_model_protocol_errors() != errors_before + 1 ||
            hyperram_model_device_state() != 6) begin
            $display("DISCREPANCY: short hybrid-sleep wake pulse was accepted");
            ++discrepancies;
        end
        cs_n = 1'b0;
        #20000;
        cs_n = 1'b1;
        #2500;
        errors_before = hyperram_model_protocol_errors();
        begin_transaction();
        send_byte(8'h20);
        send_byte(8'h00);
        end_transaction();
        if (hyperram_model_protocol_errors() != errors_before + 1) begin
            $display("DISCREPANCY: hybrid-sleep recovery traffic was not rejected");
            ++discrepancies;
        end
        #25000;
        if (hyperram_model_device_state() != 1 ||
            hyperram_model_read_configuration_register1() != 16'hffc1 ||
            {hyperram_model_read_byte(4), hyperram_model_read_byte(5)} != 16'hdead) begin
            $display("DISCREPANCY: hybrid-sleep exit lost retention or CR1 state");
            ++discrepancies;
        end

        // Differential mode accepts the regular complementary clock stream,
        // but must reject a non-complementary CK/CK# level without consuming
        // a CA/data edge.
        ck = 1'b0;
        #5000;
        errors_before = hyperram_model_protocol_errors();
        begin_transaction();
        force ck_n = ck;
        #2500;
        release ck_n;
        end_transaction();
        if (hyperram_model_protocol_errors() != errors_before + 1) begin
            $display("DISCREPANCY: malformed differential clock was not rejected");
            ++discrepancies;
        end

        // CS# rising while CK is High is an illegal transaction termination.
        errors_before = hyperram_model_protocol_errors();
        ck = 1'b0;
        #5000;
        begin_transaction();
        send_byte(8'h20); // Leaves CK High.
        end_transaction();
        if (hyperram_model_protocol_errors() != errors_before + 1) begin
            $display("DISCREPANCY: High-CK CS# deassertion was not rejected");
            ++discrepancies;
        end

        hyperram_model_set_memory_geometry(32, 1'b1);
        ck = 1'b0;
        #5000;
        write_density_rollover_words();
        if ({hyperram_model_read_byte(30), hyperram_model_read_byte(31)} != 16'haaaa ||
            {hyperram_model_read_byte(0), hyperram_model_read_byte(1)} != 16'hbbbb) begin
            $display("DISCREPANCY: physical memory-density rollover failed");
            ++discrepancies;
        end
        hyperram_model_set_memory_geometry(32, 1'b0);
        errors_before = hyperram_model_protocol_errors();
        write_strict_out_of_range_word();
        if (hyperram_model_protocol_errors() != errors_before + 2 ||
            {hyperram_model_read_byte(0), hyperram_model_read_byte(1)} != 16'hbbbb ||
            {hyperram_model_read_byte(32), hyperram_model_read_byte(33)} != 16'hffff) begin
            $display("DISCREPANCY: strict memory-density rejection failed");
            ++discrepancies;
        end
        errors_before = hyperram_model_protocol_errors();
        issue_unsupported_register_write();
        if (hyperram_model_protocol_errors() != errors_before + 1 ||
            hyperram_model_last_error_code() != 6 ||
            hyperram_model_last_error_address() != 32'h0000_0802 ||
            hyperram_model_read_configuration_register0() != 16'h8f8f ||
            hyperram_model_read_configuration_register1() != 16'hffc1) begin
            $display("DISCREPANCY: unsupported register CA diagnostic or handling failed (code=%0d address=%08x tick=%0d)",
                     hyperram_model_last_error_code(),
                     hyperram_model_last_error_address(),
                     hyperram_model_last_error_tick());
            ++discrepancies;
        end

        verify_state_coverage();

        if (discrepancies == 0)
            $display("PASS: C++ HyperRAM model directed tests completed.");
        else
            $display("FAIL: %0d discrepancy(s) detected.", discrepancies);
        $finish;
    end

endmodule
