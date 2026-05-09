`timescale 1ns/1ps

module control_top_tb;

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
        $dumpfile("control_top_tb.vcd");
        $dumpvars(0, control_top_tb);
    end

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

    task arb_transaction(input [2:0] ack_val);
        begin
            wait (dut.bus_arbiter_inst.curr_mode != 2'b00);
            wait (dut.bus_arbiter_inst.counter == 2'b11);
            @(posedge clk);
            wait (dut.bus_arbiter_inst.curr_mode == 2'b00);
            @(posedge clk);
            ack_in = ack_val;
            @(posedge clk);
            ack_in = 0;
            repeat (2) @(posedge clk);
        end
    endtask

    task drive_aes_full;
        begin
            arb_transaction(3'b100);
            arb_transaction(3'b100);
            arb_transaction(3'b110);
            arb_transaction(3'b100);
        end
    endtask

    task do_reset;
        begin
            rst_n = 0; cs_n = 1; mosi = 0; spi_clk = 0;
            ack_in = 0; bus_ready = 0;
            #20 rst_n = 1;
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; spi_clk = 0; mosi = 0; cs_n = 1;
        ack_in = 0; bus_ready = 0; ena = 1;
        #20 rst_n = 1; #50;

        // =============================================
        // TEST 1: single AES end-to-end
        // =============================================
        spi_frame(1, 0, 0, 24'hAA_0001, 24'hBB_0001, 24'hCC_0001);

        bus_ready = 1;
        drive_aes_full;

        repeat (10) @(posedge clk);

        // read SPI output
        cs_n = 0; #500;
        repeat (300) @(posedge clk);
        cs_n = 1; #100;

        repeat (20) @(posedge clk);

        do_reset;

        // =============================================
        // TEST 2: back-to-back AES requests
        // =============================================
        spi_frame(1, 0, 0, 24'hAA_0002, 24'hBB_0002, 24'hCC_0002);
        spi_frame(1, 0, 0, 24'hAA_0003, 24'hBB_0003, 24'hCC_0003);

        bus_ready = 1;
        drive_aes_full;
        drive_aes_full;

        repeat (10) @(posedge clk);

        cs_n = 0; #500;
        repeat (700) @(posedge clk);
        cs_n = 1; #100;

        repeat (20) @(posedge clk);

        do_reset;

        // =============================================
        // TEST 3: pipeline stress — 4 AES requests
        // =============================================
        spi_frame(1, 0, 0, 24'hAA_0010, 24'hBB_0010, 24'hCC_0010);
        spi_frame(1, 0, 0, 24'hAA_0020, 24'hBB_0020, 24'hCC_0020);
        spi_frame(1, 0, 0, 24'hAA_0030, 24'hBB_0030, 24'hCC_0030);
        spi_frame(1, 0, 0, 24'hAA_0040, 24'hBB_0040, 24'hCC_0040);

        bus_ready = 1;
        drive_aes_full;
        drive_aes_full;
        drive_aes_full;
        drive_aes_full;

        repeat (10) @(posedge clk);

        cs_n = 0; #500;
        repeat (1500) @(posedge clk);
        cs_n = 1; #100;

        repeat (20) @(posedge clk);

        $finish;
    end

endmodule
