`default_nettype none
`timescale 1ns/1ps

module comp_queue_tb #(
    parameter ADDRW  = 24,
    parameter QDEPTH = 32
);

    reg clk;
    reg rst_n;

    // Inputs from AES and SHA FSMs
    reg                 valid_in_aes;
    reg                 valid_in_sha;
    reg  [ADDRW-1:0]    dest_addr_aes;
    reg  [ADDRW-1:0]    dest_addr_sha;

    // Backpressure from serializer
    reg                 ready_in;

    // Outputs to FSMs (backpressure)
    wire                ready_out_aes;
    wire                ready_out_sha;

    // Output to serializer
    wire [ADDRW-1:0]    data_out;
    wire                valid_out;

    comp_queue #(
        .ADDRW (ADDRW),
        .QDEPTH(QDEPTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .valid_in_aes (valid_in_aes),
        .valid_in_sha (valid_in_sha),
        .dest_addr_aes(dest_addr_aes),
        .dest_addr_sha(dest_addr_sha),
        .ready_in     (ready_in),
        .ready_out_aes(ready_out_aes),
        .ready_out_sha(ready_out_sha),
        .data_out     (data_out),
        .valid_out    (valid_out)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("comp_queue_tb.vcd");
        $dumpvars(0, comp_queue_tb);
    end

endmodule
