`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a VCD file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end
  localparam integer ADDRW_TB   = 8;
  localparam integer OPCODEW_TB = 2;
  localparam integer QLENGTH_TB = 16;
  // Wire up the inputs and outputs:
  wire clk;
  wire rst_n;
  wire valid_in;
  wire ready_in_aes;
  wire ready_in_sha;

  wire [OPCODEW_TB-1:0] opcode;
  wire [ADDRW_TB-1:0] key_addr;
  wire [ADDRW_TB-1:0] text_addr;

  reg [2*ADDRW_TB+OPCODEW_TB-1:0] instr;
  reg valid_out;
  reg ready_out;

  // Replace tt_um_example with your module name:
  req_queue #(.ADDRW(ADDRW_TB), .OPCODEW(OPCODEW_TB), .QLENGTH(QLENGTH_TB)) req_queue (
      .clk(clk),
      .rst_n(rst_n),
      .valid_in(valid_in),
      .ready_in_aes(ready_in_aes),
      .ready_in_sha(ready_in_sha),
      .opcode(opcode),
      .key_addr(key_addr),
      .text_addr(text_addr),
      .instr(instr),
      .valid_out(valid_out),
      .ready_out(ready_out)
  );


endmodule
