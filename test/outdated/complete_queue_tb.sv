`timescale 1ns/1ps

module comp_queue_tb;

  // Parameters (mirror DUT)
  parameter ADDRW   = 24;
  parameter QDEPTH  = 32;

  // DUT I/O
  reg                     clk, rst_n;
  
  // AES completion input
  reg                     valid_in_aes;
  reg [ADDRW-1:0]         dest_addr_aes;
  wire                    ready_out_aes;
  
  // SHA completion input
  reg                     valid_in_sha;
  reg [ADDRW-1:0]         dest_addr_sha;
  wire                    ready_out_sha;
  
  // Merged output
  wire [ADDRW-1:0]        data_out;
  wire                    valid_out;
  reg                     ready_in;

  // Instantiate DUT
  comp_queue #(
    .ADDRW(ADDRW),
    .QDEPTH(QDEPTH)
  ) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .valid_in_aes   (valid_in_aes),
    .valid_in_sha   (valid_in_sha),
    .dest_addr_aes  (dest_addr_aes),
    .dest_addr_sha  (dest_addr_sha),
    .ready_out_aes  (ready_out_aes),
    .ready_out_sha  (ready_out_sha),
    .data_out       (data_out),
    .valid_out      (valid_out),
    .ready_in       (ready_in)
  );

  // Clock generation
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Scoreboard - track expected outputs in order
  reg [ADDRW-1:0] expected_q [0:1023];
  integer wr_ptr, rd_ptr;
  integer pass_count;
  integer fail_count;

  // Push expected output
  task push_expected;
    input [ADDRW-1:0] addr;
    begin
      expected_q[wr_ptr] = addr;
      wr_ptr = wr_ptr + 1;
    end
  endtask

  // Self-checking monitor
  always @(posedge clk) begin
    if (rst_n && valid_out && ready_in) begin
      if (rd_ptr >= wr_ptr) begin
        $error("[%0t] ERROR: Unexpected valid_out (no expected output)", $time);
        fail_count = fail_count + 1;
      end else begin
        if (data_out !== expected_q[rd_ptr]) begin
          $error("[%0t] DATA mismatch: got %0h exp %0h", $time, data_out, expected_q[rd_ptr]);
          fail_count = fail_count + 1;
        end else begin
          $display("[%0t] PASS #%0d: data_out=%0h", $time, pass_count, data_out);
          pass_count = pass_count + 1;
        end
        rd_ptr = rd_ptr + 1;
      end
    end
  end

  // Test tasks
  task reset_dut;
    begin
      rst_n = 1'b0;
      valid_in_aes = 1'b0;
      valid_in_sha = 1'b0;
      dest_addr_aes = {ADDRW{1'b0}};
      dest_addr_sha = {ADDRW{1'b0}};
      ready_in = 1'b0;
      repeat(5) @(posedge clk);
      rst_n = 1'b1;
      repeat(2) @(posedge clk);
      $display("[%0t] Reset complete", $time);
    end
  endtask

  task send_aes_completion;
    input [ADDRW-1:0] dest;
    input expect_accept;
    begin
      @(posedge clk);
      if (expect_accept && !ready_out_aes) begin
        $error("[%0t] AES queue not ready when expected", $time);
        fail_count = fail_count + 1;
      end
      
      dest_addr_aes = dest;
      valid_in_aes = 1'b1;
      @(posedge clk);
      valid_in_aes = 1'b0;
      
      if (expect_accept) begin
        push_expected(dest);
        $display("[%0t] Sent AES completion: dest=%0h", $time, dest);
      end
    end
  endtask

  task send_sha_completion;
    input [ADDRW-1:0] dest;
    input expect_accept;
    begin
      @(posedge clk);
      if (expect_accept && !ready_out_sha) begin
        $error("[%0t] SHA queue not ready when expected", $time);
        fail_count = fail_count + 1;
      end
      
      dest_addr_sha = dest;
      valid_in_sha = 1'b1;
      @(posedge clk);
      valid_in_sha = 1'b0;
      
      if (expect_accept) begin
        push_expected(dest);
        $display("[%0t] Sent SHA completion: dest=%0h", $time, dest);
      end
    end
  endtask

  task wait_for_output;
    input integer timeout_cycles;
    integer cycles;
    begin
      cycles = 0;
      while (!valid_out && cycles < timeout_cycles) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      if (cycles >= timeout_cycles) begin
        $error("[%0t] Timeout waiting for valid_out", $time);
        fail_count = fail_count + 1;
      end
    end
  endtask

  // Main test sequence
  integer i, cycle;
  reg [1:0] choice;
  reg [ADDRW-1:0] rand_dest;
  
  initial begin
    // VCD dump
    $dumpfile("comp_queue_tb.vcd");
    $dumpvars(0, comp_queue_tb);

    // Initialize
    clk = 0;
    rst_n = 0;
    valid_in_aes = 0;
    valid_in_sha = 0;
    dest_addr_aes = 0;
    dest_addr_sha = 0;
    ready_in = 0;
    wr_ptr = 0;
    rd_ptr = 0;
    pass_count = 0;
    fail_count = 0;

    // ========================================================================
    // TEST 1: Basic reset behavior
    // ========================================================================
    $display("\n========== TEST 1: Reset behavior ==========");
    reset_dut();
    
    @(posedge clk);
    if (valid_out !== 1'b0) begin
      $error("[%0t] valid_out should be 0 after reset", $time);
      fail_count = fail_count + 1;
    end
    if (ready_out_aes !== 1'b1 || ready_out_sha !== 1'b1) begin
      $error("[%0t] Queues should be ready after reset", $time);
      fail_count = fail_count + 1;
    end
    repeat(10) @(posedge clk);

    // ========================================================================
    // TEST 2: Single AES completion
    // ========================================================================
    $display("\n========== TEST 2: Single AES completion ==========");
    ready_in = 1'b1;
    send_aes_completion(24'h000001, 1'b1);
    wait_for_output(100);
    repeat(5) @(posedge clk);

    // ========================================================================
    // TEST 3: Single SHA completion
    // ========================================================================
    $display("\n========== TEST 3: Single SHA completion ==========");
    send_sha_completion(24'hABCDEF, 1'b1);
    wait_for_output(100);
    repeat(5) @(posedge clk);

    // ========================================================================
    // TEST 4: Round-robin arbitration with simultaneous arrivals
    // ========================================================================
    $display("\n========== TEST 4: Round-robin arbitration ==========");
    
    // When both valids are asserted simultaneously, only ONE will be accepted per cycle
    // Round-robin starts with rr_select=0, so AES should be accepted first
    
    // First simultaneous arrival - AES should win (rr_select=0)
    dest_addr_aes = 24'h100;
    dest_addr_sha = 24'h200;
    valid_in_aes = 1'b1;
    valid_in_sha = 1'b1;
    push_expected(24'h100);  // Only AES will be accepted
    
    @(posedge clk);
    $display("[%0t] Sent both AES=100 and SHA=200 simultaneously (AES should win)", $time);
    valid_in_aes = 1'b0;
    valid_in_sha = 1'b0;
    
    // Wait a cycle, then send SHA again (it should be accepted now)
    @(posedge clk);
    send_sha_completion(24'h200, 1'b1);
    
    // Test second simultaneous arrival - SHA should win this time (rr_select toggled)
    dest_addr_aes = 24'h300;
    dest_addr_sha = 24'h400;
    valid_in_aes = 1'b1;
    valid_in_sha = 1'b1;
    push_expected(24'h400);  // SHA should win this time
    
    @(posedge clk);
    $display("[%0t] Sent both AES=300 and SHA=400 simultaneously (SHA should win)", $time);
    valid_in_aes = 1'b0;
    valid_in_sha = 1'b0;
    
    // Send AES again
    @(posedge clk);
    send_aes_completion(24'h300, 1'b1);
    
    // Keep ready_in high to drain items
    ready_in = 1'b1;
    repeat(15) @(posedge clk);

    // ========================================================================
    // TEST 5: Interleaved AES and SHA completions
    // ========================================================================
    $display("\n========== TEST 5: Interleaved AES/SHA completions ==========");
    ready_in = 1'b1;
    send_aes_completion(24'h111, 1'b1);
    send_sha_completion(24'h222, 1'b1);
    send_aes_completion(24'h333, 1'b1);
    send_sha_completion(24'h444, 1'b1);
    
    // Give enough time for all 4 items to be consumed
    repeat(30) @(posedge clk);

    // ========================================================================
    // TEST 6: Backpressure (ready_in = 0)
    // ========================================================================
    $display("\n========== TEST 6: Backpressure test ==========");
    ready_in = 1'b0;
    send_aes_completion(24'hDEAD, 1'b1);
    repeat(10) @(posedge clk);
    
    if (valid_out) begin
      $display("[%0t] valid_out high during backpressure (expected)", $time);
    end
    
    $display("[%0t] Releasing backpressure", $time);
    ready_in = 1'b1;
    repeat(10) @(posedge clk);
    
    // Make sure queue is fully drained before next test
    ready_in = 1'b1;  // Keep ready high to drain
    repeat(10) @(posedge clk);
    
    // Verify queue is empty - if not, force drain
    if (wr_ptr != rd_ptr) begin
      $display("[%0t] WARNING: Draining %0d remaining items before TEST 7", $time, wr_ptr - rd_ptr);
      // Force drain by waiting enough cycles
      repeat(QDEPTH) @(posedge clk);
    end

    // ========================================================================
    // TEST 7: Fill queue to capacity
    // ========================================================================
    $display("\n========== TEST 7: Fill queue to capacity ==========");
    ready_in = 1'b0; // Hold output
    
    // Fill with AES completions
    for (i = 0; i < QDEPTH; i = i + 1) begin
      send_aes_completion(i[23:0], 1'b1);
    end
    
    @(posedge clk);
    if (ready_out_aes !== 1'b0) begin
      $error("[%0t] AES queue should be full", $time);
      fail_count = fail_count + 1;
    end
    
    // Try to overflow (should be rejected)
    $display("[%0t] Attempting overflow...", $time);
    send_aes_completion(24'hBAD, 1'b0);
    
    // Drain the queue
    $display("[%0t] Draining queue...", $time);
    ready_in = 1'b1;
    repeat(QDEPTH + 10) @(posedge clk);

    // ========================================================================
    // TEST 8: Reset during operation
    // ========================================================================
    $display("\n========== TEST 8: Reset during operation ==========");
    ready_in = 1'b0;
    
    // Fill partially
    for (i = 0; i < 5; i = i + 1) begin
      send_aes_completion(i[23:0], 1'b1);
    end
    
    // Clear expected queue since reset will clear the DUT
    wr_ptr = 0;
    rd_ptr = 0;
    
    // Assert reset
    $display("[%0t] Asserting reset with pending items", $time);
    rst_n = 1'b0;
    repeat(3) @(posedge clk);
    
    if (valid_out !== 1'b0) begin
      $error("[%0t] valid_out should be 0 during reset", $time);
      fail_count = fail_count + 1;
    end
    
    // Release reset
    rst_n = 1'b1;
    ready_in = 1'b1;
    repeat(5) @(posedge clk);
    
    if (valid_out !== 1'b0) begin
      $error("[%0t] valid_out should be 0 after reset", $time);
      fail_count = fail_count + 1;
    end

    // ========================================================================
    // TEST 9: Wraparound stress test
    // ========================================================================
    $display("\n========== TEST 9: Wraparound stress test ==========");
    ready_in = 1'b1;
    
    for (cycle = 0; cycle < 3; cycle = cycle + 1) begin
      $display("[%0t] Wraparound cycle %0d/3", $time, cycle+1);
      
      // Fill to capacity
      for (i = 0; i < QDEPTH; i = i + 1) begin
        send_aes_completion((cycle*QDEPTH + i) & 24'hFFFFFF, 1'b1);
      end
      
      // Partial drain
      repeat(10) @(posedge clk);
      
      // Refill
      for (i = 0; i < 6; i = i + 1) begin
        send_sha_completion((1000 + cycle*10 + i) & 24'hFFFFFF, 1'b1);
      end
      
      // Full drain
      repeat(QDEPTH + 10) @(posedge clk);
    end

    // ========================================================================
    // TEST 10: Random stress test
    // ========================================================================
    $display("\n========== TEST 10: Random stress test ==========");
    ready_in = 1'b1;
    
    for (i = 0; i < 50; i = i + 1) begin
      choice = $random % 3;
      rand_dest = $random & 24'hFFFFFF;
      
      case (choice)
        2'b00: send_aes_completion(rand_dest, 1'b1);
        2'b01: send_sha_completion(rand_dest, 1'b1);
        2'b10: begin
          ready_in = 1'b0;
          repeat(($random % 5) + 1) @(posedge clk);
          ready_in = 1'b1;
        end
        default: send_aes_completion(rand_dest, 1'b1);
      endcase
      
      repeat(($random % 3) + 1) @(posedge clk);
    end
    
    // Drain any remaining
    repeat(QDEPTH + 20) @(posedge clk);

    // ========================================================================
    // Test completion
    // ========================================================================
    repeat(20) @(posedge clk);
    
    if (rd_ptr < wr_ptr) begin
      $error("[%0t] Test ended with %0d unmatched expected outputs", 
             $time, wr_ptr - rd_ptr);
      fail_count = fail_count + 1;
    end
    
    $display("\n========================================");
    $display("TEST SUMMARY");
    $display("========================================");
    $display("PASS: %0d", pass_count);
    $display("FAIL: %0d", fail_count);
    
    if (fail_count == 0) begin
      $display("ALL TESTS PASSED!");
    end else begin
      $display("TESTS FAILED!");
    end
    $display("========================================\n");
    
    $finish;
  end

  // Timeout watchdog
  initial begin
    #1000000; // 1ms timeout
    $error("TIMEOUT: Test did not complete in time");
    $finish;
  end

endmodule