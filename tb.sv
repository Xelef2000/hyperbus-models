`timescale 1ns/1ps

`include "axi/typedef.svh"
`include "register_interface/typedef.svh"

module tb;

    localparam int unsigned AxiAddrWidth = 32;
    localparam int unsigned AxiDataWidth = 64;
    localparam int unsigned AxiIdWidth = 1;
    localparam int unsigned RegAddrWidth = 32;
    localparam int unsigned RegDataWidth = 32;

    typedef logic [AxiAddrWidth-1:0] axi_addr_t;
    typedef logic [AxiDataWidth-1:0] axi_data_t;
    typedef logic [AxiDataWidth/8-1:0] axi_strb_t;
    typedef logic [AxiIdWidth-1:0] axi_id_t;
    typedef axi_pkg::xbar_rule_32_t axi_rule_t;

    `AXI_TYPEDEF_AW_CHAN_T(axi_aw_chan_t, axi_addr_t, axi_id_t, logic [0:0])
    `AXI_TYPEDEF_W_CHAN_T(axi_w_chan_t, axi_data_t, axi_strb_t, logic [0:0])
    `AXI_TYPEDEF_B_CHAN_T(axi_b_chan_t, axi_id_t, logic [0:0])
    `AXI_TYPEDEF_AR_CHAN_T(axi_ar_chan_t, axi_addr_t, axi_id_t, logic [0:0])
    `AXI_TYPEDEF_R_CHAN_T(axi_r_chan_t, axi_data_t, axi_id_t, logic [0:0])
    `AXI_TYPEDEF_REQ_T(axi_req_t, axi_aw_chan_t, axi_w_chan_t, axi_ar_chan_t)
    `AXI_TYPEDEF_RESP_T(axi_rsp_t, axi_b_chan_t, axi_r_chan_t)

    `REG_BUS_TYPEDEF_REQ(reg_req_t, logic [RegAddrWidth-1:0],
                         logic [RegDataWidth-1:0], logic [RegDataWidth/8-1:0])
    `REG_BUS_TYPEDEF_RSP(reg_rsp_t, logic [RegDataWidth-1:0])

    logic clk_sys = 1'b0;
    logic clk_phy = 1'b0;
    logic rst_n = 1'b0;
    axi_req_t axi_req = '{default: '0, b_ready: 1'b1, r_ready: 1'b1};
    axi_rsp_t axi_rsp;
    reg_req_t reg_req = '0;
    reg_rsp_t reg_rsp;

    logic [0:0][1:0] hyper_cs_n;
    logic [0:0] hyper_ck;
    logic [0:0] hyper_ck_n;
    logic [0:0] hyper_rwds_o;
    logic [0:0] hyper_rwds_i;
    logic [0:0] hyper_rwds_oe;
    logic [0:0][7:0] hyper_dq_o;
    logic [0:0][7:0] hyper_dq_i;
    logic [0:0] hyper_dq_oe;
    logic [0:0] hyper_reset_n;
    tri0 rwds;
    tri0 [7:0] dq;

    initial begin
        forever #5 clk_sys = ~clk_sys;
    end

    initial begin
        forever #1.25 clk_phy = ~clk_phy;
    end

    assign rwds = hyper_rwds_oe[0] ? hyper_rwds_o[0] : 1'bz;
    assign hyper_rwds_i[0] = rwds;
    assign dq = hyper_dq_oe[0] ? hyper_dq_o[0] : {8{1'bz}};
    assign hyper_dq_i[0] = dq;

    hyperbus #(
        .NumChips(2),
        .NumPhys(1),
        .UsePhyClkDivider(0),
        .AxiAddrWidth(AxiAddrWidth),
        .AxiDataWidth(AxiDataWidth),
        .AxiIdWidth(AxiIdWidth),
        .AxiUserWidth(1),
        .axi_req_t(axi_req_t),
        .axi_rsp_t(axi_rsp_t),
        .axi_w_chan_t(axi_w_chan_t),
        .axi_b_chan_t(axi_b_chan_t),
        .axi_ar_chan_t(axi_ar_chan_t),
        .axi_r_chan_t(axi_r_chan_t),
        .axi_aw_chan_t(axi_aw_chan_t),
        .RegAddrWidth(RegAddrWidth),
        .RegDataWidth(RegDataWidth),
        .reg_req_t(reg_req_t),
        .reg_rsp_t(reg_rsp_t),
        .axi_rule_t(axi_rule_t),
        .PhyStartupCycles(4)
    ) controller (
        .clk_phy_i(clk_phy),
        .rst_phy_ni(rst_n),
        .clk_sys_i(clk_sys),
        .rst_sys_ni(rst_n),
        .test_mode_i(1'b0),
        .axi_req_i(axi_req),
        .axi_rsp_o(axi_rsp),
        .reg_req_i(reg_req),
        .reg_rsp_o(reg_rsp),
        .hyper_cs_no(hyper_cs_n),
        .hyper_ck_o(hyper_ck),
        .hyper_ck_no(hyper_ck_n),
        .hyper_rwds_o(hyper_rwds_o),
        .hyper_rwds_i(hyper_rwds_i),
        .hyper_rwds_oe_o(hyper_rwds_oe),
        .hyper_dq_i(hyper_dq_i),
        .hyper_dq_o(hyper_dq_o),
        .hyper_dq_oe_o(hyper_dq_oe),
        .hyper_reset_no(hyper_reset_n)
    );

    hyperram chip (
        .clk(clk_sys),
        .clk_4x(clk_phy),
        .reset_n(hyper_reset_n[0]),
        .cs_n(hyper_cs_n[0][0]),
        .ck(hyper_ck[0]),
        .ck_n(hyper_ck_n[0]),
        .rwds,
        .dq
    );

    task automatic write64(input axi_addr_t addr, input axi_data_t data);
        axi_req.aw = '0;
        axi_req.aw.addr = addr;
        axi_req.aw.len = 0;
        axi_req.aw.size = 3;
        axi_req.aw.burst = axi_pkg::BURST_INCR;
        axi_req.aw_valid = 1'b1;
        axi_req.w = '0;
        axi_req.w.data = data;
        axi_req.w.strb = '1;
        axi_req.w.last = 1'b1;
        axi_req.w_valid = 1'b1;

        do @(posedge clk_sys); while (!axi_rsp.aw_ready);
        axi_req.aw_valid = 1'b0;
        do @(posedge clk_sys); while (!axi_rsp.w_ready);
        axi_req.w_valid = 1'b0;
        do @(posedge clk_sys); while (!axi_rsp.b_valid);
        if (axi_rsp.b.resp != axi_pkg::RESP_OKAY)
            $fatal(1, "AXI write failed: response %0d", axi_rsp.b.resp);
    endtask

    task automatic read64(input axi_addr_t addr, input axi_data_t expected);
        axi_req.ar = '0;
        axi_req.ar.addr = addr;
        axi_req.ar.len = 0;
        axi_req.ar.size = 3;
        axi_req.ar.burst = axi_pkg::BURST_INCR;
        axi_req.ar_valid = 1'b1;
        do @(posedge clk_sys); while (!axi_rsp.ar_ready);
        axi_req.ar_valid = 1'b0;
        do @(posedge clk_sys); while (!axi_rsp.r_valid);
        if (axi_rsp.r.resp != axi_pkg::RESP_OKAY || axi_rsp.r.data != expected)
            $fatal(1, "AXI read failed: expected %h, got %h", expected, axi_rsp.r.data);
    endtask

    initial begin
        repeat (8) @(posedge clk_sys);
        rst_n = 1'b1;
        repeat (16) @(posedge clk_sys);

        write64(32'h0000_0100, 64'h0123_4567_89ab_cdef);
        read64(32'h0000_0100, 64'h0123_4567_89ab_cdef);

        $display("PASS");
        $finish;
    end

endmodule
