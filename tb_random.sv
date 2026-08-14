`timescale 1ps/1ps

// Deterministic randomized normal-latency writes. Each completed burst is
// checked against the C++ slave array.
module tb_random;
    localparam int unsigned LatencyEdges = 26;
    localparam int unsigned Transactions = 24;

    logic clk = 0, clk_4x = 0, reset_n = 1, cs_n = 1, ck = 0;
    wire ck_n = ~ck;
    logic host_dq_oe = 0, host_rwds_oe = 0;
    logic [7:0] host_dq = 0;
    logic host_rwds = 0;
    tri [7:0] model_dq;
    tri model_rwds;
    logic [15:0] expected_words [0:31];
    bit expected_valid [0:31];
    int unsigned failures = 0;
    int unsigned random_state = 32'h54a9_13c7;
    int unsigned words;
    int unsigned start;

    import "DPI-C" function byte unsigned hyperram_model_read_byte(
        input int unsigned address
    );
    import "DPI-C" function int unsigned hyperram_model_protocol_errors();

    assign model_dq = host_dq_oe ? host_dq : {8{1'bz}};
    assign model_rwds = host_rwds_oe ? host_rwds : 1'bz;
    initial forever #5000 clk = ~clk;
    initial forever #1250 clk_4x = ~clk_4x;

    hyperram #(
        .CONFIGURATION_REGISTER0_RESET(16'h8f8f),
        .FIXED_LATENCY_RWDS_HIGH(1'b0),
        .T_RWR_4X_TICKS(0),
        .T_CA_SETUP_4X_TICKS(1), .T_CA_HOLD_4X_TICKS(1),
        .T_WRITE_SETUP_4X_TICKS(1), .T_WRITE_HOLD_4X_TICKS(1)
    ) model (
        .clk, .clk_4x, .reset_n, .cs_n, .ck, .ck_n,
        .rwds(model_rwds), .dq(model_dq)
    );

    function automatic int unsigned next_random();
        random_state = random_state * 32'd1664525 + 32'd1013904223;
        return random_state;
    endfunction

    task automatic send_byte(input logic [7:0] value);
        host_dq = value;
        #2000; ck = ~ck; #3000;
    endtask

    task automatic write_random_burst(input int unsigned start_word,
                                      input int unsigned word_count);
        logic [47:0] ca;
        logic [15:0] data;
        begin
            // Back-to-back operation: CS# is high for only one 4× scheduler
            // interval before the next transaction begins.
            cs_n = 0;
            host_dq_oe = 1;
            #4000;
            ca = '0;
            ca[45] = 1'b1; // linear memory burst
            ca[44:16] = start_word >> 3;
            ca[2:0] = start_word[2:0];
            for (int i = 5; i >= 0; --i)
                send_byte(ca[i*8 +: 8]);

            #10000;
            host_rwds_oe = 1;
            host_rwds = 0;
            repeat (LatencyEdges) send_byte(8'h00);
            for (int unsigned i = 0; i < word_count; ++i) begin
                data = next_random()[15:0];
                send_byte(data[15:8]);
                send_byte(data[7:0]);
                expected_words[start_word + i] = data;
                expected_valid[start_word + i] = 1'b1;
            end
            host_dq_oe = 0;
            host_rwds_oe = 0;
            #1000; cs_n = 1;
            #2500;
        end
    endtask

    task automatic check_scoreboard();
        logic [15:0] model_word;
        begin
            for (int unsigned word = 0; word < 32; ++word) begin
                if (!expected_valid[word])
                    continue;
                model_word = {hyperram_model_read_byte(word * 2),
                              hyperram_model_read_byte(word * 2 + 1)};
                if (model_word !== expected_words[word]) begin
                    $display("FAIL word %0d: expected=%h C++=%h",
                             word, expected_words[word], model_word);
                    ++failures;
                end
            end
        end
    endtask

    initial begin
        #50000;
        for (int unsigned transaction = 0; transaction < Transactions; ++transaction) begin
            words = (next_random() % 4) + 1;
            start = next_random() % (32 - words);
            write_random_burst(start, words);
        end
        check_scoreboard();
        if (hyperram_model_protocol_errors() != 0) begin
            $display("FAIL: randomized valid traffic generated %0d protocol error(s)",
                     hyperram_model_protocol_errors());
            ++failures;
        end
        if (failures == 0)
            $display("PASS: randomized and back-to-back C++ model tests completed.");
        else
            $display("FAIL: %0d randomized comparison failure(s).", failures);
        $finish;
    end
endmodule
