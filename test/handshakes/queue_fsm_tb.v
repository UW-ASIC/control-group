
module handshake_queue_fsm_tb;

    parameter ADDRW   = 24;
    parameter OPCODEW =  2;
    parameter QDEPTH  =  16;

    reg clk, rst_n;

    // deserializer
    
    reg              valid_in;
    reg [OPCODEW-1 :0] opcode;
    reg [ADDRW-1   :0] key_addr, text_addr, dest_addr;

    // aes_fsm bus/ack side; we drive these to push the FSM through its states
    reg      arb_grant;
    reg   [2:0] ack_in;
    reg compq_ready_in;

    // queue <-> fsm wires
    
    wire [3*ADDRW+OPCODEW-1:0] instr_aes;
    wire    valid_out_aes, ready_out_aes;
    wire [2*ADDRW+OPCODEW-1:0] instr_sha;
    wire    valid_out_sha, ready_out_sha;
    wire                   aes_fsm_ready;
    wire                     aes_arb_req;
    wire      [ADDRW+7:0]   aes_data_out;
    wire      [ADDRW-1:0] compq_aes_data;
    wire                 compq_aes_valid;




    req_queue #(
    
        .ADDRW                 (ADDRW),
        .OPCODEW             (OPCODEW),
        .QDEPTH               (QDEPTH)
        
    ) queue_inst (
    
        .clk                     (clk),
        .rst_n                 (rst_n),
        .valid_in           (valid_in),
        .ready_in_aes  (aes_fsm_ready),
        .ready_in_sha           (1'b0),
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
        
    ) fsm_inst (
    
        .clk                         (clk),
        .rst_n                     (rst_n),
        .req_valid         (valid_out_aes),
        .req_data              (instr_aes),
        .ready_req_out     (aes_fsm_ready),
        .compq_ready_in   (compq_ready_in),
        .compq_data_out   (compq_aes_data),
        .valid_compq_out (compq_aes_valid),
        .arb_req             (aes_arb_req),
        .arb_grant             (arb_grant),
        .ack_in                   (ack_in),
        .data_out           (aes_data_out)
    );

    always #5 clk = ~clk;

    initial begin
    
        $dumpfile("handshake_tb.vcd");
        $dumpvars( 0,  handshake_queue_fsm_tb );
        
    end

    initial begin
        clk            = 0;
        rst_n          = 0;
        valid_in       = 0;
        opcode         = 0;
        key_addr       = 0;
        text_addr      = 0;
        dest_addr      = 0;
        arb_grant      = 0;
        ack_in         = 0;
        compq_ready_in = 0;

        #20 rst_n      = 1;

        // enqueue request 1
        @(posedge clk);
        valid_in  = 1; opcode = 2'b00;
        key_addr  = 24'hAA_0001; text_addr = 24'hBB_0001; dest_addr = 24'hCC_0001;
        @(posedge clk);
        valid_in  = 0;

        // enqueue request 2
        @(posedge clk);
        valid_in  = 1;
        key_addr  = 24'hAA_0002; text_addr = 24'hBB_0002; dest_addr = 24'hCC_0002;
        @(posedge clk);
        valid_in  = 0;

        // RDKEY: grant bus
        wait (aes_arb_req); @(posedge clk); arb_grant = 1;
        @(posedge clk); arb_grant = 0;
        // WAIT_RDKEY: ack from memory
        #30; @(posedge clk); ack_in = 3'b100;
        @(posedge clk); ack_in = 0;

        // RDTEXT: grant bus
        wait (aes_arb_req); @(posedge clk); arb_grant = 1;
        @(posedge clk); arb_grant = 0;
        // WAIT_RDTXT: ack from memory
        #30; @(posedge clk); ack_in = 3'b100;
        @(posedge clk); ack_in = 0;

        // HASHOP: grant bus
        wait (aes_arb_req); @(posedge clk); arb_grant = 1;
        @(posedge clk); arb_grant = 0;
        // WAIT_HASHOP: ack from accelerator (ACCEL_ID = 2'b10)
        #30; @(posedge clk); ack_in = 3'b110;
        @(posedge clk); ack_in = 0;

        // MEMWR: grant bus
        wait (aes_arb_req); @(posedge clk); arb_grant = 1;
        @(posedge clk); arb_grant = 0;
        // WAIT_MEMWR: ack from memory
        #30; @(posedge clk); ack_in = 3'b100;
        @(posedge clk); ack_in = 0;

        // COMPLETE: let it finish
        #10; @(posedge clk); compq_ready_in = 1;
        @(posedge clk); compq_ready_in = 0;

        // FSM back in READY-  does it pick up request 2?
        repeat (20) @(posedge clk);

        $finish;
    end

endmodule

