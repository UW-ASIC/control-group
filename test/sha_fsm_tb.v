`default_nettype none
`timescale 1ns/1ps

module sha_fsm_tb #(
    parameter ADDRW = 24,
    parameter ACCEL_ID = 2'b01
);

    // Clock and reset
    reg clk;
    reg rst_n;

    // Request queue interface
    reg req_valid;
    reg [2*ADDRW+1:0] req_data;
    wire ready_req_out;

    // Completion queue interface
    reg comq_ready_in;
    wire [ADDRW-1:0] compq_data_out;
    wire valid_compq_out;

    // Bus arbiter interface
    wire arb_req;
    reg arb_grant;

    // ACKs from memory / accelerator
    reg [2:0] ack_in;

    // Data bus interface
    wire [ADDRW+7:0] data_out;

    // Instantiate the DUT
    sha_fsm #(
        .ADDRW(ADDRW),
        .ACCEL_ID(ACCEL_ID)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid),
        .req_data(req_data),
        .ready_req_out(ready_req_out),
        .comq_ready_in(comq_ready_in),
        .compq_data_out(compq_data_out),
        .valid_compq_out(valid_compq_out),
        .arb_req(arb_req),
        .arb_grant(arb_grant),
        .ack_in(ack_in),
        .data_out(data_out)
    );

    // Clock generation (10ns period = 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Dump waves
    initial begin
        $dumpfile("sha_fsm_tb.vcd");
        $dumpvars(0, sha_fsm_tb);
    end

endmodule
