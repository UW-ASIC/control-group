`default_nettype none
`timescale 1ns/1ps

module bus_arbiter_tb #(
    parameter ADDRW = 24
);

    // Clock and reset
    reg clk;
    reg rst_n;

    // Inputs to DUT
    reg sha_req;
    reg aes_req;
    reg [ADDRW+7:0] sha_data_in;
    reg [ADDRW+7:0] aes_data_in;
    reg bus_ready;

    // Outputs from DUT
    wire [7:0] data_out;
    wire valid_out;
    wire aes_grant;
    wire sha_grant;

    // Instantiate the DUT
    bus_arbiter #(
        .ADDRW(ADDRW)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .sha_req(sha_req),
        .aes_req(aes_req),
        .sha_data_in(sha_data_in),
        .aes_data_in(aes_data_in),
        .bus_ready(bus_ready),
        .data_out(data_out),
        .valid_out(valid_out),
        .aes_grant(aes_grant),
        .sha_grant(sha_grant)
    );

    // Clock generation (10ns period = 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Dump waves
    initial begin
        $dumpfile("bus_arbiter_tb.vcd");
        $dumpvars(0, bus_arbiter_tb);
    end

endmodule
