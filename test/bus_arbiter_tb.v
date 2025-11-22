`timescale 1ns/1ps
`default_nettype none

module bus_arbiter_tb;
  parameter ADDRW = 24;

  reg clk, rst_n;
  reg sha_req, aes_req;
  reg [ADDRW+7:0] sha_data_in, aes_data_in;
  reg bus_ready;
  wire [7:0] data_out;
  wire valid_out;
  wire aes_grant, sha_grant;
  wire [1:0] curr_mode_top;
  wire [1:0] counter_top;

  bus_arbiter #(.ADDRW(ADDRW)) dut (
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
    .sha_grant(sha_grant),
    .curr_mode_top(curr_mode_top),
    .counter_top(counter_top)
  );

  initial begin
    $dumpfile("bus_arbiter_tb.vcd");
    $dumpvars(0, bus_arbiter_tb);
end

  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100 MHz clock
  end

endmodule
