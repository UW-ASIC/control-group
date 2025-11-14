`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a VCD file. You can view it with gtkwave or surfer.

  localparam integer ADDRW_TB  = 24;
  localparam integer OPCODEW_TB = 2;
  localparam integer QDEPTH_TB = 16;
  // Wire up the inputs and outputs:
  wire clk;
  wire rst_n;
  wire valid_in;
  wire ready_in_aes;
  wire ready_in_sha;

  wire [OPCODEW_TB-1:0] opcode;
  wire [ADDRW_TB-1:0] key_addr;
  wire [ADDRW_TB-1:0] text_addr;
  wire [ADDRW_TB-1:0] dest_addr;

  wire [3*ADDRW_TB+OPCODEW_TB-1:0] instr_aes;
  wire valid_out_aes;
  wire ready_out_aes;
  wire [3*ADDRW_TB+OPCODEW_TB-1:0] instr_sha;
  wire valid_out_sha;
  wire ready_out_sha;

  // Replace tt_um_example with your module name:
  req_queue #(
    .ADDRW(ADDRW_TB), 
    .OPCODEW(OPCODEW_TB), 
    .QDEPTH(QDEPTH_TB)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .valid_in(valid_in),
      .ready_in_aes(ready_in_aes),
      .ready_in_sha(ready_in_sha),
      .opcode(opcode),
      .key_addr(key_addr),
      .text_addr(text_addr),
      .dest_addr(dest_addr),
      .instr_aes(instr_aes),
      .valid_out_aes(valid_out_aes),
      .ready_out_aes(ready_out_aes),
      .instr_sha(instr_sha),
      .valid_out_sha(valid_out_sha),
      .ready_out_sha(ready_out_sha)
  );

  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

endmodule

`default_nettype  wire