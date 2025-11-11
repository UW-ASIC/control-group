`timescale 1ns/1ps

module deserializer_tb;

  // ------------------------------------------------
  // Parameters
  // ------------------------------------------------
  localparam int ADDRW    = 8;
  localparam int OPCODEW  = 2;
  localparam int SHIFT_W  = OPCODEW + 2*ADDRW; // stream is {opcode, key_addr, text_addr} MSB-first

  // ------------------------------------------------
  // DUT I/O
  // ------------------------------------------------
  logic                   clk;
  logic                   rst_n;
  logic                   spi_clk;
  logic                   mosi;
  logic                   cs_n;
  logic                   ready_in;

  wire  [OPCODEW-1:0]     opcode;
  wire  [ADDRW-1:0]       key_addr;
  wire  [ADDRW-1:0]       text_addr;
  wire                    valid_out;

  // ------------------------------------------------
  // Instantiate DUT (updated name & ports)
  // ------------------------------------------------
  deserializer #(
    .ADDRW(ADDRW),
    .OPCODEW(OPCODEW)
  ) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .spi_clk   (spi_clk),
    .mosi      (mosi),
    .cs_n      (cs_n),
    .ready_in  (ready_in),
    .opcode    (opcode),
    .key_addr  (key_addr),
    .text_addr (text_addr),
    .valid_out (valid_out)
  );

  // ------------------------------------------------
  // Clocks
  // ------------------------------------------------
  // Fast system clock ~100 MHz => 10 ns period
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // spi_clk will be driven by tasks (slower than clk)
  initial spi_clk = 1'b0;

  // ------------------------------------------------
  // Helpers: SPI driving
  // ------------------------------------------------
  // Single SPI clock pulse (posedge is sampling edge in DUT)
  task automatic spi_clk_pulse();
    #30 spi_clk = 1'b1;  // rising edge (DUT should sample MOSI here)
    #30 spi_clk = 1'b0;  // falling edge
  endtask

  // Pack fields into MSB-first word: {opcode, key, text}
  function automatic logic [SHIFT_W-1:0] pack_instr(
      input logic [OPCODEW-1:0] opc,
      input logic [ADDRW-1:0]   key,
      input logic [ADDRW-1:0]   txt
  );
    return {opc, key, txt};
  endfunction

  // Send a full MSB-first instruction while CS is low
  task automatic send_instruction(input logic [SHIFT_W-1:0] instr);
    int i;
    begin
      cs_n = 1'b0;  // select
      #20;
      for (i = SHIFT_W-1; i >= 0; i--) begin
        mosi = instr[i];
        spi_clk_pulse();
      end
      #20;
      cs_n = 1'b1;  // deassert
      #80;
    end
  endtask

  // Send only top N bits (MSB-first), then abort by raising CS
  task automatic send_partial_then_abort(
      input logic [SHIFT_W-1:0] instr,
      input int bits_to_send_msb_first    // 1..SHIFT_W
  );
    int i;
    begin
      cs_n = 1'b0;
      #20;
      for (i = SHIFT_W-1; i >= SHIFT_W - bits_to_send_msb_first; i--) begin
        mosi = instr[i];
        spi_clk_pulse();
      end
      cs_n = 1'b1; // abort
      #100;
    end
  endtask

  // ------------------------------------------------
  // Simple scoreboard / expected queue
  // ------------------------------------------------
  logic [SHIFT_W-1:0] expected_q [0:31];
  int wr_ptr, rd_ptr;

  task automatic push_exp(input logic [SHIFT_W-1:0] instr);
    expected_q[wr_ptr] = instr;
    wr_ptr++;
  endtask

  // Extractors (must match DUT slicing)
  function automatic logic [OPCODEW-1:0] get_opcode(input logic [SHIFT_W-1:0] w);
    return w[SHIFT_W-1 : SHIFT_W-OPCODEW];
  endfunction

  function automatic logic [ADDRW-1:0] get_key(input logic [SHIFT_W-1:0] w);
    return w[SHIFT_W-OPCODEW-1 : SHIFT_W-OPCODEW-ADDRW];
  endfunction

  function automatic logic [ADDRW-1:0] get_text(input logic [SHIFT_W-1:0] w);
    return w[ADDRW-1 : 0];
  endfunction

  // Self-check on valid_out
  always @(posedge clk) begin
    if (valid_out) begin
      if (rd_ptr >= wr_ptr) begin
        $error("[%0t] Checker underflow: valid_out with no expected item (rd=%0d wr=%0d)",
               $time, rd_ptr, wr_ptr);
        $fatal;
      end

      if (opcode   !== get_opcode(expected_q[rd_ptr])) begin
        $error("[%0t] OPCODE mismatch: got %0b exp %0b (rd=%0d wr=%0d)",
               $time, opcode, get_opcode(expected_q[rd_ptr]), rd_ptr, wr_ptr);
        $fatal;
      end
      if (key_addr !== get_key(expected_q[rd_ptr])) begin
        $error("[%0t] KEY mismatch: got %0h exp %0h (rd=%0d wr=%0d)",
               $time, key_addr, get_key(expected_q[rd_ptr]), rd_ptr, wr_ptr);
        $fatal;
      end
      if (text_addr !== get_text(expected_q[rd_ptr])) begin
        $error("[%0t] TEXT mismatch: got %0h exp %0h (rd=%0d wr=%0d)",
               $time, text_addr, get_text(expected_q[rd_ptr]), rd_ptr, wr_ptr);
        $fatal;
      end

      $display("[%0t] PASS #%0d  opcode=%0b key=%0h text=%0h",
               $time, rd_ptr, opcode, key_addr, text_addr);
      rd_ptr <= rd_ptr + 1;
    end
  end

  // ------------------------------------------------
  // Test sequence
  // ------------------------------------------------
  logic [OPCODEW-1:0] opA, opB, opC;
  logic [ADDRW-1:0]   keyA, keyB, keyC;
  logic [ADDRW-1:0]   txtA, txtB, txtC;
  logic [SHIFT_W-1:0] instrA, instrB, instrC;

  initial begin
    // defaults
    clk      = 1'b0;
    rst_n    = 1'b0;
    spi_clk  = 1'b0;
    mosi     = 1'b0;
    cs_n     = 1'b1;
    ready_in = 1'b0;
    wr_ptr   = 0;
    rd_ptr   = 0;

    // VCD
    $dumpfile("deserializer_tb.vcd");
    $dumpvars(0, deserializer_tb);

    // vectors
    opA  = 2'b01; keyA = 8'hAA; txtA = 8'h55;
    opB  = 2'b10; keyB = 8'h0F; txtB = 8'hF0;
    opC  = 2'b11; keyC = 8'h5A; txtC = 8'hC3;

    instrA = pack_instr(opA, keyA, txtA);
    instrB = pack_instr(opB, keyB, txtB);
    instrC = pack_instr(opC, keyC, txtC);

    // Release reset
    #120; rst_n = 1'b1; #50;

    // TEST 1: Normal transfer, consumer ready
    $display("[%0t] TEST1: normal transfer, ready_in=1", $time);
    ready_in = 1'b1;
    push_exp(instrA);
    send_instruction(instrA);
    #400;

    // TEST 2: Abort mid-transfer (expect no output)
    $display("[%0t] TEST2: abort mid-transfer (no output expected)", $time);
    ready_in = 1'b1;
    send_partial_then_abort(instrB, SHIFT_W/2);
    #400;

    // TEST 3: Backpressure (hold result until ready)
    $display("[%0t] TEST3: backpressure; ready_in=0 during/after receive", $time);
    ready_in = 1'b0;
    push_exp(instrB);
    send_instruction(instrB);
    #600;
    $display("[%0t] Releasing backpressure (ready_in=1): expect valid_out now", $time);
    ready_in = 1'b1;
    #400;

    // TEST 4: Overrun attempt while one word is pending
    $display("[%0t] TEST4: overrun attempt while pending", $time);
    ready_in = 1'b0;
    push_exp(instrC);
    send_instruction(instrC); // should become pending
    // try to send another immediately; should be ignored while busy
    send_instruction(instrA);
    #400;
    $display("[%0t] Releasing backpressure (ready_in=1): expect single valid_out for instrC", $time);
    ready_in = 1'b1;
    #600;

    $display("[%0t] ALL TESTS COMPLETED OK", $time);
    $finish;
  end

endmodule
