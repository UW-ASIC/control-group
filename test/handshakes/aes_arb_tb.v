`timescale 1ns/1ps

module aes_arb_tb;

    parameter ADDRW = 24;

    reg clk, rst_n;
    reg bus_ready;
    reg [2:0] ack_in;
    reg req_valid;
    reg [3*ADDRW+1:0] req_data;
    reg compq_ready_in;

    wire arb_req;
    wire [ADDRW+7:0] fsm_data_out;
    wire aes_grant;
    wire sha_grant;
    wire [7:0] data_bus_out;
    wire data_bus_valid;
    wire ready_req_out;
    wire valid_compq_out;
    wire [ADDRW-1:0] compq_data_out;


    aes_fsm #(
        .ADDRW(ADDRW)
    ) fsm_inst (
        .clk(clk), .rst_n(rst_n),
        .req_valid(req_valid), .req_data(req_data),
        .ready_req_out(ready_req_out),
        .compq_ready_in(compq_ready_in),
        .compq_data_out(compq_data_out),
        .valid_compq_out(valid_compq_out),
        .arb_req(arb_req),
        .arb_grant(aes_grant),
        .ack_in(ack_in),
        .data_out(fsm_data_out)
    );

    bus_arbiter #(
        .ADDRW(ADDRW)
    ) arb_inst (
        .clk(clk), .rst_n(rst_n),
        .aes_req(arb_req),
        .sha_req(1'b0),
        .aes_data_in(fsm_data_out),
        .sha_data_in({(ADDRW+8){1'b0}}),
        .bus_ready(bus_ready),
        .data_out(data_bus_out),
        .valid_out(data_bus_valid),
        .aes_grant(aes_grant),
        .sha_grant(sha_grant)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("aes_arb_tb.vcd");
        $dumpvars(0, aes_arb_tb);
    end

    task do_reset;
        begin
            rst_n = 0; bus_ready = 0; ack_in = 0;
            req_valid = 0; req_data = 0; compq_ready_in = 0;
            #20 rst_n = 1;
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        clk = 0; rst_n = 0;
        bus_ready = 0; ack_in = 0;
        req_valid = 0; req_data = 0;
        compq_ready_in = 0;
        #20 rst_n = 1; #50;

        // =============================================
        // TEST 1: single AES op, grant level vs pulse
        // =============================================
        // feed request
        @(posedge clk);
        req_valid = 1;
        req_data = {2'b00, 24'hAA_0001, 24'hBB_0001, 24'hCC_0001};
        @(posedge clk);
        req_valid = 0;

        // FSM enters RDKEY, arb_req goes high
        // arbiter sets curr_mode = AES, aes_grant goes high
        // FSM should move to WAIT_RDKEY

        // hold bus_ready high so arbiter counter advances
        bus_ready = 1;

        // wait for arbiter to complete 4 beats
        repeat (10) @(posedge clk);

        // send mem ack for RDKEY
        ack_in = 3'b100;
        @(posedge clk);
        ack_in = 0;

        // FSM should go to RDTEXT
        // KEY QUESTION: does aes_grant drop between transactions?
        // if not, FSM skips straight to WAIT_RDTXT without new arbiter transaction
        repeat (10) @(posedge clk);

        // send mem ack for RDTEXT
        ack_in = 3'b100;
        @(posedge clk);
        ack_in = 0;

        repeat (10) @(posedge clk);

        // send accel ack for HASHOP
        ack_in = 3'b110;
        @(posedge clk);
        ack_in = 0;

        repeat (10) @(posedge clk);

        // send mem ack for MEMWR
        ack_in = 3'b100;
        @(posedge clk);
        ack_in = 0;

        repeat (5) @(posedge clk);

        // complete
        compq_ready_in = 1;
        @(posedge clk);
        compq_ready_in = 0;

        repeat (10) @(posedge clk);

        do_reset;

        // =============================================
        // TEST 2: verify arbiter counter and grant per transaction
        // =============================================
        // same as test 1 but watch counter and curr_mode carefully
        // bus_ready pulsed instead of held to control beat timing

        @(posedge clk);
        req_valid = 1;
        req_data = {2'b00, 24'hAA_0002, 24'hBB_0002, 24'hCC_0002};
        @(posedge clk);
        req_valid = 0;

        // RDKEY: manually clock 4 beats
        repeat (4) begin
            @(posedge clk); bus_ready = 1;
            @(posedge clk); bus_ready = 0;
        end
        // arbiter should return to idle after counter wraps
        repeat (3) @(posedge clk);
        // send ack
        ack_in = 3'b100;
        @(posedge clk);
        ack_in = 0;

        repeat (5) @(posedge clk);

        // RDTEXT: manually clock 4 beats
        repeat (4) begin
            @(posedge clk); bus_ready = 1;
            @(posedge clk); bus_ready = 0;
        end
        repeat (3) @(posedge clk);
        ack_in = 3'b100;
        @(posedge clk);
        ack_in = 0;

        repeat (5) @(posedge clk);

        // HASHOP: manually clock 4 beats
        repeat (4) begin
            @(posedge clk); bus_ready = 1;
            @(posedge clk); bus_ready = 0;
        end
        repeat (3) @(posedge clk);
        ack_in = 3'b110;
        @(posedge clk);
        ack_in = 0;

        repeat (5) @(posedge clk);

        // MEMWR: manually clock 4 beats
        repeat (4) begin
            @(posedge clk); bus_ready = 1;
            @(posedge clk); bus_ready = 0;
        end
        repeat (3) @(posedge clk);
        ack_in = 3'b100;
        @(posedge clk);
        ack_in = 0;

        repeat (5) @(posedge clk);

        compq_ready_in = 1;
        @(posedge clk);
        compq_ready_in = 0;

        repeat (10) @(posedge clk);

        do_reset;

        // =============================================
        // TEST 3: bus_ready held high, check for state skipping
        // =============================================
        // bus_ready = 1 the whole time
        // if grant stays high between transactions, FSM may skip states

        bus_ready = 1;

        @(posedge clk);
        req_valid = 1;
        req_data = {2'b00, 24'hAA_0003, 24'hBB_0003, 24'hCC_0003};
        @(posedge clk);
        req_valid = 0;

        // just watch — does the FSM blow through all states
        // before any ack arrives?
        repeat (30) @(posedge clk);

        // now try sending acks and see what state the FSM is in
        ack_in = 3'b100; @(posedge clk); ack_in = 0;
        repeat (10) @(posedge clk);
        ack_in = 3'b100; @(posedge clk); ack_in = 0;
        repeat (10) @(posedge clk);
        ack_in = 3'b110; @(posedge clk); ack_in = 0;
        repeat (10) @(posedge clk);
        ack_in = 3'b100; @(posedge clk); ack_in = 0;
        repeat (10) @(posedge clk);

        compq_ready_in = 1;
        @(posedge clk);
        compq_ready_in = 0;

        repeat (10) @(posedge clk);

        $finish;
    end

endmodule