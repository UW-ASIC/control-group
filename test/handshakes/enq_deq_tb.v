`timescale 1ns/1ps

module enq_deq_tb;

    parameter ADDRW   = 24;
    parameter OPCODEW =  2;
    parameter QDEPTH  = 16;

    reg clk, rst_n;

    // deserializer
    
    reg              valid_in;
    reg [OPCODEW-1 :0] opcode;
    reg [ADDRW-1   :0] key_addr, text_addr, dest_addr;

    // fsm bus/ack side
    reg        aes_arb_grant;
    reg  [2:0] aes_ack_in;
    reg        aes_compq_ready_in;
    reg        sha_arb_grant;
    reg  [2:0] sha_ack_in;
    reg        sha_compq_ready_in;

    // queue <-> aes_fsm wires
    
    wire [3*ADDRW+OPCODEW-1:0] instr_aes;
    wire    valid_out_aes, ready_out_aes;
    wire                   aes_fsm_ready;
    wire                     aes_arb_req;
    wire      [ADDRW+7:0]   aes_data_out;
    wire      [ADDRW-1:0] compq_aes_data;
    wire                 compq_aes_valid;

    // queue <-> sha_fsm wires
    
    wire [2*ADDRW+OPCODEW-1:0] instr_sha;
    wire    valid_out_sha, ready_out_sha;
    wire                   sha_fsm_ready;
    wire                     sha_arb_req;
    wire      [ADDRW+7:0]   sha_data_out;
    wire      [ADDRW-1:0] compq_sha_data;
    wire                 compq_sha_valid;




    req_queue #(
    
        .ADDRW                 (ADDRW),
        .OPCODEW             (OPCODEW),
        .QDEPTH               (QDEPTH)
        
    ) queue_inst (
    
        .clk                     (clk),
        .rst_n                 (rst_n),
        .valid_in           (valid_in),
        .ready_in_aes  (aes_fsm_ready),
        .ready_in_sha  (sha_fsm_ready),
        .opcode               (opcode),
        .key_addr           (key_addr),
        .text_addr         (text_addr),
        .dest_addr         (dest_addr),
        .instr_aes         (instr_aes),
        .valid_out_aes (valid_out_aes),
        .ready_out_aes (ready_out_aes),
        .instr_sha         (instr_sha),
        .valid_out_sha (valid_out_sha),
        .ready_out_sha (ready_out_sha)
    );

    aes_fsm #(
    
        .ADDRW                     (ADDRW)
        
    ) aes_inst (
    
        .clk                             (clk),
        .rst_n                         (rst_n),
        .req_valid             (valid_out_aes),
        .req_data                  (instr_aes),
        .ready_req_out         (aes_fsm_ready),
        .compq_ready_in   (aes_compq_ready_in),
        .compq_data_out       (compq_aes_data),
        .valid_compq_out     (compq_aes_valid),
        .arb_req                 (aes_arb_req),
        .arb_grant             (aes_arb_grant),
        .ack_in                   (aes_ack_in),
        .data_out               (aes_data_out)
    );

    sha_fsm #(
    
        .ADDRW                     (ADDRW)
        
    ) sha_inst (
    
        .clk                             (clk),
        .rst_n                         (rst_n),
        .req_valid             (valid_out_sha),
        .req_data                  (instr_sha),
        .ready_req_out         (sha_fsm_ready),
        .compq_ready_in   (sha_compq_ready_in),
        .compq_data_out       (compq_sha_data),
        .valid_compq_out     (compq_sha_valid),
        .arb_req                 (sha_arb_req),
        .arb_grant             (sha_arb_grant),
        .ack_in                   (sha_ack_in),
        .data_out               (sha_data_out)
    );

    always #5 clk = ~clk;

    initial begin
    
        $dumpfile("enq_deq_tb.vcd");
        $dumpvars( 0,  enq_deq_tb );
        
    end

    // task: push AES FSM through one full operation
    task run_aes_cycle;
        begin
            // RDKEY
            wait (aes_arb_req); @(posedge clk); aes_arb_grant = 1;
            @(posedge clk); aes_arb_grant = 0;
            #30; @(posedge clk); aes_ack_in = 3'b100;
            @(posedge clk); aes_ack_in = 0;
            // RDTEXT
            wait (aes_arb_req); @(posedge clk); aes_arb_grant = 1;
            @(posedge clk); aes_arb_grant = 0;
            #30; @(posedge clk); aes_ack_in = 3'b100;
            @(posedge clk); aes_ack_in = 0;
            // HASHOP
            wait (aes_arb_req); @(posedge clk); aes_arb_grant = 1;
            @(posedge clk); aes_arb_grant = 0;
            #30; @(posedge clk); aes_ack_in = 3'b110;
            @(posedge clk); aes_ack_in = 0;
            // MEMWR
            wait (aes_arb_req); @(posedge clk); aes_arb_grant = 1;
            @(posedge clk); aes_arb_grant = 0;
            #30; @(posedge clk); aes_ack_in = 3'b100;
            @(posedge clk); aes_ack_in = 0;
            // COMPLETE
            #10; @(posedge clk); aes_compq_ready_in = 1;
            @(posedge clk); aes_compq_ready_in = 0;
        end
    endtask

    // task: push SHA FSM through one full operation (no RDKEY)
    task run_sha_cycle;
        begin
            // RDTEXT
            wait (sha_arb_req); @(posedge clk); sha_arb_grant = 1;
            @(posedge clk); sha_arb_grant = 0;
            #30; @(posedge clk); sha_ack_in = 3'b100;
            @(posedge clk); sha_ack_in = 0;
            // HASHOP
            wait (sha_arb_req); @(posedge clk); sha_arb_grant = 1;
            @(posedge clk); sha_arb_grant = 0;
            #30; @(posedge clk); sha_ack_in = 3'b101;
            @(posedge clk); sha_ack_in = 0;
            // MEMWR
            wait (sha_arb_req); @(posedge clk); sha_arb_grant = 1;
            @(posedge clk); sha_arb_grant = 0;
            #30; @(posedge clk); sha_ack_in = 3'b100;
            @(posedge clk); sha_ack_in = 0;
            // COMPLETE
            #10; @(posedge clk); sha_compq_ready_in = 1;
            @(posedge clk); sha_compq_ready_in = 0;
        end
    endtask

    // task: clean reset
    task do_reset;
        begin
            rst_n = 0; valid_in = 0;
            aes_arb_grant = 0; aes_ack_in = 0; aes_compq_ready_in = 0;
            sha_arb_grant = 0; sha_ack_in = 0; sha_compq_ready_in = 0;
            opcode = 0; key_addr = 0; text_addr = 0; dest_addr = 0;
            #20 rst_n = 1;
            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        clk                = 0;
        rst_n              = 0;
        valid_in           = 0;
        opcode             = 0;
        key_addr           = 0;
        text_addr          = 0;
        dest_addr          = 0;
        aes_arb_grant      = 0;
        aes_ack_in         = 0;
        aes_compq_ready_in = 0;
        sha_arb_grant      = 0;
        sha_ack_in         = 0;
        sha_compq_ready_in = 0;

        #20 rst_n          = 1;


        
        //  AES TESTS (opcode[0] = 0)
  


        // =============================================
        // AES TEST 1: simultaneous enqueue + complete
        // =============================================
        @(posedge clk);
        valid_in  = 1; opcode = 2'b00;
        key_addr  = 24'h01_0001; text_addr = 24'h02_0001; dest_addr = 24'h03_0001;
        @(posedge clk);
        valid_in  = 0;

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
        #10; @(posedge clk);
        aes_compq_ready_in = 1;
        valid_in           = 1;
        key_addr  = 24'h01_0002; text_addr = 24'h02_0002; dest_addr = 24'h03_0002;
        @(posedge clk);
        aes_compq_ready_in = 0;
        valid_in           = 0;

        repeat (5) @(posedge clk);
        run_aes_cycle;
        repeat (5) @(posedge clk);

        do_reset;

        // =============================================
        // AES TEST 2: full queue enqueue + dequeue collision
        // =============================================
        @(posedge clk);
        valid_in = 1; opcode = 2'b00;
        key_addr = 24'hF0_0001; text_addr = 24'hF1_0001; dest_addr = 24'hF2_0001;
        @(posedge clk);
        key_addr = 24'hF0_0002; text_addr = 24'hF1_0002; dest_addr = 24'hF2_0002;
        @(posedge clk);
        key_addr = 24'hF0_0003; text_addr = 24'hF1_0003; dest_addr = 24'hF2_0003;
        @(posedge clk);
        key_addr = 24'hF0_0004; text_addr = 24'hF1_0004; dest_addr = 24'hF2_0004;
        @(posedge clk);
        valid_in = 0;

        repeat (3) @(posedge clk);
        run_aes_cycle;
        @(posedge clk);
        valid_in  = 1;
        key_addr  = 24'hF0_0005; text_addr = 24'hF1_0005; dest_addr = 24'hF2_0005;
        @(posedge clk);
        valid_in  = 0;

        repeat (5) @(posedge clk);

        do_reset;

        // =============================================
        // AES TEST 3: single enqueue, empty queue, FSM in READY
        // =============================================
        repeat (5) @(posedge clk);
        @(posedge clk);
        valid_in  = 1; opcode = 2'b00;
        key_addr  = 24'hDD_0001; text_addr = 24'hEE_0001; dest_addr = 24'hFF_0001;
        @(posedge clk);
        valid_in  = 0;

        run_aes_cycle;
        repeat (5) @(posedge clk);

        do_reset;

        // =============================================
        // AES TEST 4: back-to-back completions, sequential drain
        // =============================================
        @(posedge clk);
        valid_in = 1; opcode = 2'b00;
        key_addr = 24'hA0_0001; text_addr = 24'hA1_0001; dest_addr = 24'hA2_0001;
        @(posedge clk);
        key_addr = 24'hA0_0002; text_addr = 24'hA1_0002; dest_addr = 24'hA2_0002;
        @(posedge clk);
        key_addr = 24'hA0_0003; text_addr = 24'hA1_0003; dest_addr = 24'hA2_0003;
        @(posedge clk);
        key_addr = 24'hA0_0004; text_addr = 24'hA1_0004; dest_addr = 24'hA2_0004;
        @(posedge clk);
        valid_in = 0;

        run_aes_cycle;
        run_aes_cycle;
        run_aes_cycle;
        run_aes_cycle;

        repeat (10) @(posedge clk);

        do_reset;

        // =============================================
        // AES TEST 5: full queue rejection, overflow blocked
        // =============================================
        @(posedge clk);
        valid_in = 1; opcode = 2'b00;
        key_addr = 24'hB0_0001; text_addr = 24'hB1_0001; dest_addr = 24'hB2_0001;
        @(posedge clk);
        key_addr = 24'hB0_0002; text_addr = 24'hB1_0002; dest_addr = 24'hB2_0002;
        @(posedge clk);
        key_addr = 24'hB0_0003; text_addr = 24'hB1_0003; dest_addr = 24'hB2_0003;
        @(posedge clk);
        key_addr = 24'hB0_0004; text_addr = 24'hB1_0004; dest_addr = 24'hB2_0004;
        @(posedge clk);
        key_addr = 24'hB0_0005; text_addr = 24'hB1_0005; dest_addr = 24'hB2_0005;
        @(posedge clk);
        key_addr = 24'hB0_0006; text_addr = 24'hB1_0006; dest_addr = 24'hB2_0006;
        @(posedge clk);
        key_addr = 24'hB0_0007; text_addr = 24'hB1_0007; dest_addr = 24'hB2_0007;
        @(posedge clk);
        key_addr = 24'hB0_0008; text_addr = 24'hB1_0008; dest_addr = 24'hB2_0008;
        @(posedge clk);
        key_addr = 24'hB0_0009; text_addr = 24'hB1_0009; dest_addr = 24'hB2_0009;
        @(posedge clk);
        key_addr = 24'hB0_000A; text_addr = 24'hB1_000A; dest_addr = 24'hB2_000A;
        @(posedge clk);
        key_addr = 24'hB0_000B; text_addr = 24'hB1_000B; dest_addr = 24'hB2_000B;
        @(posedge clk);
        key_addr = 24'hB0_000C; text_addr = 24'hB1_000C; dest_addr = 24'hB2_000C;
        @(posedge clk);
        key_addr = 24'hB0_000D; text_addr = 24'hB1_000D; dest_addr = 24'hB2_000D;
        @(posedge clk);
        key_addr = 24'hB0_000E; text_addr = 24'hB1_000E; dest_addr = 24'hB2_000E;
        @(posedge clk);
        key_addr = 24'hB0_000F; text_addr = 24'hB1_000F; dest_addr = 24'hB2_000F;
        @(posedge clk);
        key_addr = 24'hB0_0010; text_addr = 24'hB1_0010; dest_addr = 24'hB2_0010;
        @(posedge clk);
        // 17th — should be rejected
        key_addr = 24'hFF_FFFF; text_addr = 24'hFF_FFFF; dest_addr = 24'hFF_FFFF;
        @(posedge clk);
        valid_in = 0;

        repeat (5) @(posedge clk);

        do_reset;

        // =============================================
        // AES TEST 6: reset mid-operation, clean recovery
        // =============================================
        @(posedge clk);
        valid_in  = 1; opcode = 2'b00;
        key_addr  = 24'hC0_0001; text_addr = 24'hC1_0001; dest_addr = 24'hC2_0001;
        @(posedge clk);
        key_addr  = 24'hC0_0002; text_addr = 24'hC1_0002; dest_addr = 24'hC2_0002;
        @(posedge clk);
        valid_in  = 0;

        wait (aes_arb_req); @(posedge clk); aes_arb_grant = 1;
        @(posedge clk); aes_arb_grant = 0;
        #30; @(posedge clk); aes_ack_in = 3'b100;
        @(posedge clk); aes_ack_in = 0;
        wait (aes_arb_req); @(posedge clk); aes_arb_grant = 1;
        @(posedge clk); aes_arb_grant = 0;
        #30; @(posedge clk); aes_ack_in = 3'b100;
        @(posedge clk); aes_ack_in = 0;

        repeat (2) @(posedge clk);
        do_reset;

        @(posedge clk);
        valid_in  = 1; opcode = 2'b00;
        key_addr  = 24'hC0_00AA; text_addr = 24'hC1_00AA; dest_addr = 24'hC2_00AA;
        @(posedge clk);
        valid_in  = 0;

        run_aes_cycle;
        repeat (5) @(posedge clk);

        do_reset;


        // =============================================================
        //  SHA TESTS (opcode[0] = 1)
        // =============================================================


        // =============================================
        // SHA TEST 1: simultaneous enqueue + complete
        // =============================================
        @(posedge clk);
        valid_in  = 1; opcode = 2'b01;
        text_addr = 24'h02_0001; dest_addr = 24'h03_0001;
        @(posedge clk);
        valid_in  = 0;

        wait (sha_arb_req); @(posedge clk); sha_arb_grant = 1;
        @(posedge clk); sha_arb_grant = 0;
        #30; @(posedge clk); sha_ack_in = 3'b100;
        @(posedge clk); sha_ack_in = 0;
        wait (sha_arb_req); @(posedge clk); sha_arb_grant = 1;
        @(posedge clk); sha_arb_grant = 0;
        #30; @(posedge clk); sha_ack_in = 3'b101;
        @(posedge clk); sha_ack_in = 0;
        wait (sha_arb_req); @(posedge clk); sha_arb_grant = 1;
        @(posedge clk); sha_arb_grant = 0;
        #30; @(posedge clk); sha_ack_in = 3'b100;
        @(posedge clk); sha_ack_in = 0;
        #10; @(posedge clk);
        sha_compq_ready_in = 1;
        valid_in           = 1; opcode = 2'b01;
        text_addr = 24'h02_0002; dest_addr = 24'h03_0002;
        @(posedge clk);
        sha_compq_ready_in = 0;
        valid_in           = 0;

        repeat (5) @(posedge clk);
        run_sha_cycle;
        repeat (5) @(posedge clk);

        do_reset;

        // =============================================
        // SHA TEST 2: full queue enqueue + dequeue collision
        // =============================================
        @(posedge clk);
        valid_in = 1; opcode = 2'b01;
        text_addr = 24'hF1_0001; dest_addr = 24'hF2_0001;
        @(posedge clk);
        text_addr = 24'hF1_0002; dest_addr = 24'hF2_0002;
        @(posedge clk);
        text_addr = 24'hF1_0003; dest_addr = 24'hF2_0003;
        @(posedge clk);
        text_addr = 24'hF1_0004; dest_addr = 24'hF2_0004;
        @(posedge clk);
        valid_in = 0;

        repeat (3) @(posedge clk);
        run_sha_cycle;
        @(posedge clk);
        valid_in   = 1; opcode = 2'b01;
        text_addr  = 24'hF1_0005; dest_addr = 24'hF2_0005;
        @(posedge clk);
        valid_in   = 0;

        repeat (5) @(posedge clk);

        do_reset;

        // =============================================
        // SHA TEST 3: single enqueue, empty queue, FSM in READY
        // =============================================
        repeat (5) @(posedge clk);
        @(posedge clk);
        valid_in  = 1; opcode = 2'b01;
        text_addr = 24'hEE_0001; dest_addr = 24'hFF_0001;
        @(posedge clk);
        valid_in  = 0;

        run_sha_cycle;
        repeat (5) @(posedge clk);

        do_reset;

        // =============================================
        // SHA TEST 4: back-to-back completions, sequential drain
        // =============================================
        @(posedge clk);
        valid_in = 1; opcode = 2'b01;
        text_addr = 24'hA1_0001; dest_addr = 24'hA2_0001;
        @(posedge clk);
        text_addr = 24'hA1_0002; dest_addr = 24'hA2_0002;
        @(posedge clk);
        text_addr = 24'hA1_0003; dest_addr = 24'hA2_0003;
        @(posedge clk);
        text_addr = 24'hA1_0004; dest_addr = 24'hA2_0004;
        @(posedge clk);
        valid_in = 0;

        run_sha_cycle;
        run_sha_cycle;
        run_sha_cycle;
        run_sha_cycle;

        repeat (10) @(posedge clk);

        do_reset;

        // =============================================
        // SHA TEST 5: full queue rejection, overflow blocked
        // =============================================
        @(posedge clk);
        valid_in = 1; opcode = 2'b01;
        text_addr = 24'hB1_0001; dest_addr = 24'hB2_0001;
        @(posedge clk);
        text_addr = 24'hB1_0002; dest_addr = 24'hB2_0002;
        @(posedge clk);
        text_addr = 24'hB1_0003; dest_addr = 24'hB2_0003;
        @(posedge clk);
        text_addr = 24'hB1_0004; dest_addr = 24'hB2_0004;
        @(posedge clk);
        text_addr = 24'hB1_0005; dest_addr = 24'hB2_0005;
        @(posedge clk);
        text_addr = 24'hB1_0006; dest_addr = 24'hB2_0006;
        @(posedge clk);
        text_addr = 24'hB1_0007; dest_addr = 24'hB2_0007;
        @(posedge clk);
        text_addr = 24'hB1_0008; dest_addr = 24'hB2_0008;
        @(posedge clk);
        text_addr = 24'hB1_0009; dest_addr = 24'hB2_0009;
        @(posedge clk);
        text_addr = 24'hB1_000A; dest_addr = 24'hB2_000A;
        @(posedge clk);
        text_addr = 24'hB1_000B; dest_addr = 24'hB2_000B;
        @(posedge clk);
        text_addr = 24'hB1_000C; dest_addr = 24'hB2_000C;
        @(posedge clk);
        text_addr = 24'hB1_000D; dest_addr = 24'hB2_000D;
        @(posedge clk);
        text_addr = 24'hB1_000E; dest_addr = 24'hB2_000E;
        @(posedge clk);
        text_addr = 24'hB1_000F; dest_addr = 24'hB2_000F;
        @(posedge clk);
        text_addr = 24'hB1_0010; dest_addr = 24'hB2_0010;
        @(posedge clk);
        // 17th — should be rejected
        text_addr = 24'hFF_FFFF; dest_addr = 24'hFF_FFFF;
        @(posedge clk);
        valid_in = 0;

        repeat (5) @(posedge clk);

        do_reset;

        // =============================================
        // SHA TEST 6: reset mid-operation, clean recovery
        // =============================================
        @(posedge clk);
        valid_in  = 1; opcode = 2'b01;
        text_addr = 24'hC1_0001; dest_addr = 24'hC2_0001;
        @(posedge clk);
        text_addr = 24'hC1_0002; dest_addr = 24'hC2_0002;
        @(posedge clk);
        valid_in  = 0;

        wait (sha_arb_req); @(posedge clk); sha_arb_grant = 1;
        @(posedge clk); sha_arb_grant = 0;
        #30; @(posedge clk); sha_ack_in = 3'b100;
        @(posedge clk); sha_ack_in = 0;

        repeat (2) @(posedge clk);
        do_reset;

        @(posedge clk);
        valid_in  = 1; opcode = 2'b01;
        text_addr = 24'hC1_00AA; dest_addr = 24'hC2_00AA;
        @(posedge clk);
        valid_in  = 0;

        run_sha_cycle;
        repeat (5) @(posedge clk);

        $finish;
    end

endmodule