`timescale 1ns/1ps

module deserializer_tb;

  // Parameters (mirror DUT)
  localparam int ADDRW   = 8;
  localparam int OPCODEW = 2;
  localparam int SHIFT_W = OPCODEW + 2*ADDRW;

  // DUT I/O
  logic                   clk, rst_n;
  logic                   spi_clk, mosi, cs_n;
  logic                   ready_in;

  wire [OPCODEW-1:0]      opcode;
  wire [ADDRW-1:0]        key_addr, text_addr;
  wire                    valid_out;

  // Instantiate DUT
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

  // System clock (fast)
  initial clk = 1'b0;
  always  #5 clk = ~clk;

  // spi_clk is driven by tasks
  initial spi_clk = 1'b0;

  // SPI helpers
  task automatic spi_clk_pulse();
    #30 spi_clk = 1'b1;  // posedge
    #30 spi_clk = 1'b0;  // negedge
  endtask

  // MSB first stream for SPI
  function automatic logic [SHIFT_W-1:0] pack_instr
  (
    input logic [OPCODEW-1:0] opc,
    input logic [ADDRW-1:0]   key,
    input logic [ADDRW-1:0]   txt
  );
    return {opc, key, txt};
  endfunction

  // Send full frame (MSB-first)
  task automatic send_instruction(input logic [SHIFT_W-1:0] instr);
    int i;
    begin
      cs_n = 1'b0; #20;                 // select
      for (i = SHIFT_W-1; i >= 0; i--) begin
        mosi = instr[i];
        spi_clk_pulse();                // sample on posedge
      end
      #20; cs_n = 1'b1; #80;            // deassert + inter-frame gap
    end
  endtask

  // Send only top N bits
  task automatic send_partial_then_abort
  (
    input logic [SHIFT_W-1:0] instr,
    input int                 nbits_msb_first
  );
    int i;
    begin
      cs_n = 1'b0; #20;
      for (i = SHIFT_W-1; i >= SHIFT_W - nbits_msb_first; i--) begin
        mosi = instr[i];
        spi_clk_pulse();
      end
      cs_n = 1'b1; #100;                // abort
    end
  endtask

  // Scoreboard
  logic [SHIFT_W-1:0] expected_q [0:63];
  int wr_ptr, rd_ptr;

  task automatic push_exp(input logic [SHIFT_W-1:0] w);
    expected_q[wr_ptr] = w;
    wr_ptr++;
  endtask

  // Field extractors (match DUT slicing)
  function automatic logic [OPCODEW-1:0] get_opcode(input logic [SHIFT_W-1:0] w);
    return w[SHIFT_W-1 : SHIFT_W-OPCODEW];
  endfunction
  function automatic logic [ADDRW-1:0] get_key(input logic [SHIFT_W-1:0] w);
    // NOTE: this must match your RTL slice
    return w[SHIFT_W-OPCODEW-1 : SHIFT_W-OPCODEW-ADDRW];
  endfunction
  function automatic logic [ADDRW-1:0] get_text(input logic [SHIFT_W-1:0] w);
    return w[ADDRW-1 : 0];
  endfunction

  // Self-check on valid_out in clk domain
  always @(posedge clk) begin
    if (valid_out) begin
      if (rd_ptr >= wr_ptr) begin
        $error("[%0t] Underflow: valid_out but no expected item (rd=%0d wr=%0d)",
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

  // Test vectors + sequence
  logic [OPCODEW-1:0] opA, opB, opC;
  logic [ADDRW-1:0]   keyA, keyB, keyC;
  logic [ADDRW-1:0]   txtA, txtB, txtC;
  logic [SHIFT_W-1:0] instrA, instrB, instrC;
  logic [OPCODEW-1:0] random_opcode;
  logic [ADDRW-1:0] random_key, random_text;
  logic [SHIFT_W-1:0] random_instr;

  initial begin
    // defaults
    clk=0; rst_n=0; spi_clk=0; mosi=0; cs_n=1; ready_in=0;
    wr_ptr=0; rd_ptr=0;

    // VCD for GTKWave
    $dumpfile("deserializer_tb.vcd");
    $dumpvars(0, deserializer_tb);

    // test vectors
    opA=2'b01; keyA=8'hAA; txtA=8'h55;
    opB=2'b10; keyB=8'h0F; txtB=8'hF0;
    opC=2'b11; keyC=8'h5A; txtC=8'hC3;

    instrA = pack_instr(opA, keyA, txtA);
    instrB = pack_instr(opB, keyB, txtB);
    instrC = pack_instr(opC, keyC, txtC);

    // release reset
    #120; rst_n = 1'b1; #50;

    // 1) Normal transfer (ready=1)
    $display("[%0t] TEST1: normal transfer, ready_in=1", $time);
    ready_in = 1'b1;
    push_exp(instrA);
    send_instruction(instrA);
    #400;

    // 2) Abort mid-transfer (no output expected)
    $display("[%0t] TEST2: abort mid-transfer (no output expected)", $time);
    ready_in = 1'b1;
    send_partial_then_abort(instrB, SHIFT_W/2);
    #400;

    // 3) Backpressure: hold until ready
    $display("[%0t] TEST3: backpressure; ready_in=0 during/after receive", $time);
    ready_in = 1'b0;
    push_exp(instrB);
    send_instruction(instrB);
    #600;
    $display("[%0t] Releasing backpressure (ready_in=1): expect valid_out now", $time);
    ready_in = 1'b1;
    #400;

    // 4) Overrun attempt while pending
    $display("[%0t] TEST4: overrun attempt while pending", $time);
    ready_in = 1'b0;
    push_exp(instrC);
    send_instruction(instrC); // should become pending (busy=1)
    send_instruction(instrA); // should be ignored while busy
    #400;
    $display("[%0t] Releasing backpressure (ready_in=1): expect single valid_out for instrC", $time);
    ready_in = 1'b1;
    #600;

    // 5) CS_n change mid-transfer (discard partial data)
    $display("[%0t] TEST5: CS_n change mid-transfer, no valid output expected", $time);
    ready_in = 1'b1;
    send_partial_then_abort(instrA, SHIFT_W/2); // Send half of instrA
    #40; // Ensure the system doesn't assert valid_out yet
    cs_n = 1'b1; // Deassert cs_n during transfer
    #400;

    // 6) Partial word reset (cs_n high mid-transfer)
    $display("[%0t] TEST6: Partial word reset; cs_n deasserted", $time);
    send_partial_then_abort(instrB, SHIFT_W/2); // Send half of instrB
    #400;

    // 7) Randomized instruction test
    $display("[%0t] TEST7: Randomized instruction test", $time);

    repeat (10) begin // Repeat 10 times with different random instructions
        random_opcode = $random;
        random_key = $random;
        random_text = $random;
        random_instr = pack_instr(random_opcode, random_key, random_text);
        push_exp(random_instr);
        send_instruction(random_instr);
        #400;
    end

    $display("[%0t] ALL TESTS COMPLETED OK", $time);
    $finish;
  end

endmodule
