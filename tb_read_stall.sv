`timescale 1ps/1ps

// Deterministic fixture for refresh-collision inter-word read stalls.
module tb_read_stall;
    localparam int unsigned LatencyEdges = 26;
    logic clk = 0, clk_4x = 0, reset_n = 1, cs_n = 1, ck = 0;
    wire ck_n = ~ck;
    logic host_dq_oe = 0, host_rwds_oe = 0;
    logic [7:0] host_dq = 0;
    logic host_rwds = 0;
    tri [7:0] dq;
    tri rwds;
    int unsigned failures = 0;

    import "DPI-C" function void hyperram_model_force_refresh_collision_for_test();

    assign dq = host_dq_oe ? host_dq : {8{1'bz}};
    assign rwds = host_rwds_oe ? host_rwds : 1'bz;
    initial forever #5000 clk = ~clk;
    initial forever #1250 clk_4x = ~clk_4x;

    hyperram #(.CHIP_PROFILE("test_read_stall")) dut (.*);

    task automatic send_byte(input logic [7:0] value);
        host_dq = value;
        #2000; ck = ~ck; #3000;
    endtask
    task automatic advance_edge();
        #1000; ck = ~ck; #4000;
    endtask
    task automatic begin_transaction();
        cs_n = 0; host_dq_oe = 1; #4000;
    endtask
    task automatic end_transaction();
        host_dq_oe = 0; host_rwds_oe = 0; #1000; cs_n = 1; #40000;
    endtask
    task automatic check_output(input logic [7:0] expected_dq, input logic expected_rwds,
                                input string label);
        #1;
        if (dut.dq_o_timed !== expected_dq || dut.rwds_o_timed !== expected_rwds) begin
            $display("FAIL %s: DQ=%h RWDS=%b", label, dut.dq_o_timed, dut.rwds_o_timed);
            ++failures;
        end
    endtask

    initial begin
        // Seed words 0 and 1 with 1122 and 3344.
        begin_transaction();
        send_byte(8'h20); repeat (5) send_byte(8'h00);
        host_rwds_oe = 1; host_rwds = 0;
        repeat (LatencyEdges) send_byte(8'h00);
        send_byte(8'h11); send_byte(8'h22); send_byte(8'h33); send_byte(8'h44);
        end_transaction();

        begin_transaction();
        send_byte(8'ha0); repeat (5) send_byte(8'h00);
        host_dq_oe = 0;
        repeat (LatencyEdges) advance_edge();
        advance_edge(); check_output(8'h11, 1'b1, "word 0 byte A");
        hyperram_model_force_refresh_collision_for_test();
        advance_edge(); check_output(8'h22, 1'b1, "word 0 byte B / stall indication");
        advance_edge(); check_output(8'h22, 1'b1, "stall edge 1");
        advance_edge(); check_output(8'h22, 1'b0, "stall recovery");
        advance_edge(); check_output(8'h33, 1'b1, "word 1 byte A");
        // Refresh remains forced, so completing word 1 starts the next
        // legal boundary stall and leaves RWDS High again.
        advance_edge(); check_output(8'h44, 1'b1, "word 1 byte B / next stall");
        end_transaction();

        if (failures == 0) $display("PASS: deterministic inter-word read stall.");
        else $display("FAIL: %0d read-stall check(s).", failures);
        $finish;
    end
endmodule
