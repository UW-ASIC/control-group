`timescale 1ns/1ps

module more_top_tb;

    parameter ADDRW      = 24;
    parameter OPCODEW    =  2;
    parameter REQ_QDEPTH =  4;
    parameter COMP_QDEPTH = 4;

    reg         clk, rst_n;
    reg         spi_clk, mosi, cs_n;
    reg   [2:0] ack_in;
    reg         bus_ready;
    reg         ena;

    wire        miso;
    wire  [7:0] data_bus_out;
    wire        data_bus_valid;

    control_top #(
        .ADDRW(ADDRW), .OPCODEW(OPCODEW),
        .REQ_QDEPTH(REQ_QDEPTH), .COMP_QDEPTH(COMP_QDEPTH)
    ) dut (
        .clk(clk), .rst_n(rst_n), .ena(ena),
        .spi_clk(spi_clk), .mosi(mosi), .cs_n(cs_n),
        .miso(miso),
        .ack_in(ack_in), .bus_ready(bus_ready),
        .data_bus_out(data_bus_out), .data_bus_valid(data_bus_valid)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("more_top_tb.vcd");
        $dumpvars(0, more_top_tb);
    end

    // =========================================
    // SPI tasks
    // =========================================
    task spi_bit(input b);
        begin
            mosi = b;
            spi_clk = 0; #25;
            spi_clk = 1; #25;
        end
    endtask

    task spi_frame(
        input v, input ed, input as,
        input [ADDRW-1:0] key,
        input [ADDRW-1:0] text,
        input [ADDRW-1:0] dest
    );
        integer i;
        begin
            cs_n = 0;
            #500;
            spi_bit(v); spi_bit(ed); spi_bit(as);
            for (i = ADDRW-1; i >= 0; i = i-1) spi_bit(key[i]);
            for (i = ADDRW-1; i >= 0; i = i-1) spi_bit(text[i]);
            for (i = ADDRW-1; i >= 0; i = i-1) spi_bit(dest[i]);
            spi_clk = 0;
            #50;
            cs_n = 1;
            #100;
        end
    endtask

    // =========================================
    // Wait for FSM to reach a specific WAIT_* state,
    // then send the appropriate ack.
    // FSM states:
    //   WAIT_RDKEY  = 0010 -> ack 3'b100 (mem read done)
    //   WAIT_RDTXT  = 0100 -> ack 3'b100 (mem read done)
    //   WAIT_HASHOP = 0110 -> ack 3'b110 (accel done)
    //   WAIT_MEMWR  = 1000 -> ack 3'b100 (mem write done)
    // =========================================
    task wait_and_ack(input [3:0] wait_state, input [2:0] ack_val);
        begin
            $display("[%0t] wait_and_ack: waiting for state=%0d", $time, wait_state);
            wait (dut.aes_fsm_inst.state == wait_state);
            $display("[%0t] wait_and_ack: state=%0d reached, sending ack=%b", $time, wait_state, ack_val);
            @(posedge clk);
            ack_in = ack_val;
            @(posedge clk);
            ack_in = 0;
            repeat (3) @(posedge clk);
            $display("[%0t] wait_and_ack: done, FSM now in state=%0d", $time, dut.aes_fsm_inst.state);
        end
    endtask

    task drive_aes_full;
        begin
            wait_and_ack(4'b0010, 3'b100);  // WAIT_RDKEY  -> mem ack
            wait_and_ack(4'b0100, 3'b100);  // WAIT_RDTXT  -> mem ack
            wait_and_ack(4'b0110, 3'b110);  // WAIT_HASHOP -> accel ack
            wait_and_ack(4'b1000, 3'b100);  // WAIT_MEMWR  -> mem ack
            // COMPLETE -> READY happens in 1 cycle (compq not full),
            // so by the time repeat(3) finishes, FSM is already back in READY.
        end
    endtask

    // =========================================
    // Main test
    // =========================================
    initial begin
        clk = 0; rst_n = 0; spi_clk = 0; mosi = 0; cs_n = 1;
        ack_in = 0; bus_ready = 0; ena = 1;
        #20 rst_n = 1; #50;

        // ---- PHASE 1: SPI input (bus_ready=0) ----
        // FSM may get granted by arbiter, but counter won't advance
        // and no acks will come, so FSM stalls in WAIT states.
        spi_frame(1, 0, 0, 24'hAA_0010, 24'hBB_0010, 24'hCC_0010);
        spi_frame(1, 0, 0, 24'hAA_0020, 24'hBB_0020, 24'hCC_0020);
        spi_frame(1, 0, 0, 24'hAA_0030, 24'hBB_0030, 24'hCC_0030);
        spi_frame(1, 0, 0, 24'hAA_0040, 24'hBB_0040, 24'hCC_0040);
        $display("[%0t] All 4 SPI frames sent", $time);

        // Let everything settle — cs_n is high, SPI done
        repeat (10) @(posedge clk);

        // ---- PHASE 2: FSM processing (cs_n stays high) ----
        // bus_ready=1 lets arbiter counter advance.
        // cs_n is high so compq_ready_in is gated — entries stay in comp_queue.
        bus_ready = 1;

        drive_aes_full;
        $display("[%0t] AES request 1 complete, comp_queue count=%0d", $time, dut.comp_queue_inst.count);
        drive_aes_full;
        $display("[%0t] AES request 2 complete, comp_queue count=%0d", $time, dut.comp_queue_inst.count);
        drive_aes_full;
        $display("[%0t] AES request 3 complete, comp_queue count=%0d", $time, dut.comp_queue_inst.count);
        drive_aes_full;
        $display("[%0t] AES request 4 complete, comp_queue count=%0d", $time, dut.comp_queue_inst.count);

        bus_ready = 0;
        repeat (10) @(posedge clk);

        // ---- PHASE 3: readout (cs_n low, spi_clk toggling) ----
        $display("[%0t] Starting readout, comp_queue count=%0d", $time, dut.comp_queue_inst.count);
        cs_n = 0;
        #500;
        // Toggle SPI clock so serializer can shift out data
        // and valid_ncs can update through the debounce logic.
        // 4 entries × 25 bits × 50ns/bit = 5000ns, add margin
        repeat (200) begin
            spi_clk = 0; #25;
            spi_clk = 1; #25;
        end
        spi_clk = 0;
        #50;
        cs_n = 1;
        #100;

        repeat (20) @(posedge clk);

        $display("[%0t] Done. comp_queue count=%0d", $time, dut.comp_queue_inst.count);
        $finish;
    end

    // Watchdog
    initial begin
        #10_000_000;
        $display("WATCHDOG TIMEOUT");
        $finish;
    end

endmodule

