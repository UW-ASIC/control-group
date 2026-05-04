`timescale 1ns/1ps

module fsm_compq_tb;

    parameter ADDRW   = 24;
    parameter OPCODEW =  2;
    parameter QDEPTH  = 32;

    reg clk, rst_n;

    // aes_fsm side
    reg        aes_arb_grant;
    reg  [2:0] aes_ack_in;
    reg        aes_req_valid;
    reg [3*ADDRW+OPCODEW-1:0] aes_req_data;

    // sha_fsm side — tied off, not used
    reg        sha_arb_grant;
    reg  [2:0] sha_ack_in;
    reg        sha_req_valid;
    reg [2*ADDRW+OPCODEW-1:0] sha_req_data;

    // comp_queue output side
    reg        ser_ready_in;

    // aes_fsm <-> comp_queue wires
    wire                   aes_fsm_ready;
    wire                     aes_arb_req;
    wire      [ADDRW+7:0]   aes_data_out;
    wire      [ADDRW-1:0] compq_aes_data;
    wire                 compq_aes_valid;
    wire                 compq_ready_aes;

    // sha_fsm <-> comp_queue wires
    wire                   sha_fsm_ready;
    wire                     sha_arb_req;
    wire      [ADDRW+7:0]   sha_data_out;
    wire      [ADDRW-1:0] compq_sha_data;
    wire                 compq_sha_valid;
    wire                 compq_ready_sha;

    // comp_queue output wires
    wire      [ADDRW-1:0] compq_data_out;
    wire                  compq_valid_out;




    aes_fsm #(
    
        .ADDRW                       (ADDRW)
        
    ) aes_inst (
    
        .clk                           (clk),
        .rst_n                       (rst_n),
        .req_valid           (aes_req_valid),
        .req_data             (aes_req_data),
        .ready_req_out       (aes_fsm_ready),
        .compq_ready_in     (compq_ready_aes),
        .compq_data_out     (compq_aes_data),
        .valid_compq_out   (compq_aes_valid),
        .arb_req               (aes_arb_req),
        .arb_grant           (aes_arb_grant),
        .ack_in                 (aes_ack_in),
        .data_out             (aes_data_out)
    );

    sha_fsm #(
    
        .ADDRW                       (ADDRW)
        
    ) sha_inst (
    
        .clk                           (clk),
        .rst_n                       (rst_n),
        .req_valid           (sha_req_valid),
        .req_data             (sha_req_data),
        .ready_req_out       (sha_fsm_ready),
        .compq_ready_in     (compq_ready_sha),
        .compq_data_out     (compq_sha_data),
        .valid_compq_out   (compq_sha_valid),
        .arb_req               (sha_arb_req),
        .arb_grant           (sha_arb_grant),
        .ack_in                 (sha_ack_in),
        .data_out             (sha_data_out)
    );

    comp_queue #(
    
        .ADDRW                       (ADDRW),
        .QDEPTH                     (QDEPTH)
        
    ) compq_inst (
    
        .clk                           (clk),
        .rst_n                       (rst_n),
        .valid_in_aes       (compq_aes_valid),
        .valid_in_sha       (compq_sha_valid),
        .dest_addr_aes       (compq_aes_data),
        .dest_addr_sha       (compq_sha_data),
        .ready_out_aes     (compq_ready_aes),
        .ready_out_sha     (compq_ready_sha),
        .data_out           (compq_data_out),
        .valid_out         (compq_valid_out),
        .ready_in           (ser_ready_in)
    );

    always #5 clk = ~clk;

    initial begin
    
        $dumpfile("fsm_compq_tb.vcd");
        $dumpvars( 0,  fsm_compq_tb );
        
    end

    initial begin
        clk            = 0;
        rst_n          = 0;
        aes_arb_grant  = 0;
        aes_ack_in     = 0;
        aes_req_valid  = 0;
        aes_req_data   = 0;
        sha_arb_grant  = 0;
        sha_ack_in     = 0;
        sha_req_valid  = 0;
        sha_req_data   = 0;
        ser_ready_in   = 0;

        #20 rst_n      = 1;

        // valid_out holds when ser_ready_in is low
 

        // complete one AES op, ser_ready_in stays LOW
        @(posedge clk);
        aes_req_valid = 1;
        aes_req_data  = {2'b00, 24'hAA_0004, 24'hBB_0004, 24'hCC_0004};
        @(posedge clk);
        aes_req_valid = 0;

        // push FSM to COMPLETE
        wait (aes_arb_req); @(posedge clk); aes_arb_grant = 1;
        @(posedge clk); aes_arb_grant = 0;
        #30; @(posedge clk); aes_ack_in = 3'b100;
        @(posedge clk); aes_ack_in = 0;
        wait (aes_arb_req); @(posedge clk); aes_arb_grant = 1;
        @(posedge clk); aes_arb_grant = 0;
        #30; @(posedge clk); aes_ack_in = 3'b100;
        @(posedge clk); aes_ack_in = 0;
        wait (aes_arb_req); @(posedge clk); aes_arb_grant = 1;
        @(posedge clk); aes_arb_grant = 0;
        #30; @(posedge clk); aes_ack_in = 3'b110;
        @(posedge clk); aes_ack_in = 0;
        wait (aes_arb_req); @(posedge clk); aes_arb_grant = 1;
        @(posedge clk); aes_arb_grant = 0;
        #30; @(posedge clk); aes_ack_in = 3'b100;
        @(posedge clk); aes_ack_in = 0;

        // FSM hits COMPLETE, comp_queue enqueues
        // ser_ready_in is LOW — valid_out should hold HIGH
        repeat (30) @(posedge clk);

        // now assert ser_ready_in — valid_out should drop, head advances
        @(posedge clk);
        ser_ready_in = 1;
        @(posedge clk);
        ser_ready_in = 0;

        repeat (10) @(posedge clk);

 

        $finish;
    end

endmodule

