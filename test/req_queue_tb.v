`default_nettype none
`timescale 1ns/1ps

module req_queue_tb #(
    parameter ADDRW   = 24,
    parameter OPCODEW = 2,
    parameter QDEPTH  = 16
);

    reg clk;
    reg rst_n;

    // Input from deserializer
    reg                          valid_in;
    reg  [OPCODEW-1:0]           opcode;
    reg  [ADDRW-1:0]             key_addr;
    reg  [ADDRW-1:0]             text_addr;
    reg  [ADDRW-1:0]             dest_addr;

    // Backpressure from FSMs
    reg                          ready_in_aes;
    reg                          ready_in_sha;

    // Outputs to AES FSM
    wire [3*ADDRW+OPCODEW-1:0]   instr_aes;
    wire                         valid_out_aes;
    wire                         ready_out_aes;

    // Outputs to SHA FSM
    wire [2*ADDRW+OPCODEW-1:0]   instr_sha;
    wire                         valid_out_sha;
    wire                         ready_out_sha;

    req_queue #(
        .ADDRW  (ADDRW),
        .OPCODEW(OPCODEW),
        .QDEPTH (QDEPTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .valid_in     (valid_in),
        .opcode       (opcode),
        .key_addr     (key_addr),
        .text_addr    (text_addr),
        .dest_addr    (dest_addr),
        .ready_in_aes (ready_in_aes),
        .ready_in_sha (ready_in_sha),
        .instr_aes    (instr_aes),
        .valid_out_aes(valid_out_aes),
        .ready_out_aes(ready_out_aes),
        .instr_sha    (instr_sha),
        .valid_out_sha(valid_out_sha),
        .ready_out_sha(ready_out_sha)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("req_queue_tb.vcd");
        $dumpvars(0, req_queue_tb);
    end

endmodule
