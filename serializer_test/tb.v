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
  localparam integer VALIDW     = 1;
  localparam integer ADDRW_TB   = 23;
  // Wire up the inputs and outputs:
  wire clk;
  wire rst_n;
  wire n_cs;
  wire spi_clk;
  wire valid_in;

  // wire [VALIDW-1:0] valid;
  wire [ADDRW_TB-1:0] addr;

  reg miso;
  reg ready_out;
  reg err;

  // Replace tt_um_example with your module name:
  serializer #(.ADDRW(ADDRW_TB), .VALIDW(VALIDW)) serializerDUT  (
      .clk(clk),
      .rst_n(rst_n),
      .n_cs(n_cs),
      .spi_clk(spi_clk),
      .valid_in(valid_in),
      .addr(addr),
      .miso(miso),
      .ready_out(ready_out),
      .err(err)
  );


endmodule
