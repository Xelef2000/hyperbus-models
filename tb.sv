module tb;

    logic clk;
    logic rst_n;

    import "DPI-C" function void model_reset();

    import "DPI-C" function bit model_request(
        input int a,
        input int b
    );

    import "DPI-C" function void model_tick();

    import "DPI-C" function bit model_result_valid();

    import "DPI-C" function int model_result();

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Advance the C++ model once per simulation cycle.
    always @(posedge clk) begin
        if (!rst_n)
            model_reset();
        else
            model_tick();
    end

    initial begin
        bit accepted;
        int result;

        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;

        // Submit immediately after a clock edge so the following
        // three rising edges represent the three latency cycles.
        @(negedge clk);

        accepted = model_request(10, 20);

        if (!accepted)
            $fatal(1, "Adder model rejected request");

        $display("[%0t] Request submitted", $time);

        repeat (2) begin
            @(posedge clk);
            #1;

            if (model_result_valid())
                $fatal(1, "Result became valid too early");

            $display("[%0t] Result not valid yet", $time);
        end

        @(posedge clk);
        #1;

        if (!model_result_valid())
            $fatal(1, "Result was not valid after three cycles");

        result = model_result();

        $display("[%0t] Result valid: %0d", $time, result);

        if (result != 30)
            $fatal(1, "Expected 30, got %0d", result);

        $display("PASS");
        $finish;
    end

endmodule
