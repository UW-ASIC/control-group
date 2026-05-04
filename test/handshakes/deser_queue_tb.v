`timescale 1ns/1ps

module deser_queue_tb;

    parameter ADDRW   = 24;
    parameter OPCODEW =  2;
    parameter QDEPTH  =  4;

    reg clk, rst_n;
    reg spi_clk, mosi, cs_n;
    reg ready_in_aes, ready_in_sha;

    wire                     deser_valid_out;
    wire [OPCODEW-1:0]       deser_opcode;
    wire [ADDRW-1:0]         deser_key_addr, deser_text_addr, deser_dest_addr;
    wire                     deser_valid;

    wire [3*ADDRW+OPCODEW-1:0] instr_aes;
    wire [2*ADDRW+OPCODEW-1:0] instr_sha;
    wire valid_out_aes, ready_out_aes;
    wire valid_out_sha, ready_out_sha;


    deserializer #(.ADDRW(ADDRW), .OPCODEW(OPCODEW)) deser_inst (
        .clk(clk), .rst_n(rst_n), .spi_clk(spi_clk), .mosi(mosi), .cs_n(cs_n),
        .aes_ready_in(ready_out_aes), .sha_ready_in(ready_out_sha),
        .valid(deser_valid), .opcode(deser_opcode),
        .key_addr(deser_key_addr), .text_addr(deser_text_addr), .dest_addr(deser_dest_addr),
        .valid_out(deser_valid_out)
    );

    req_queue #(.ADDRW(ADDRW), .OPCODEW(OPCODEW), .QDEPTH(QDEPTH)) queue_inst (
        .clk(clk), .rst_n(rst_n), .valid_in(deser_valid_out),
        .ready_in_aes(ready_in_aes), .ready_in_sha(ready_in_sha),
        .opcode(deser_opcode), .key_addr(deser_key_addr),
        .text_addr(deser_text_addr), .dest_addr(deser_dest_addr),
        .instr_aes(instr_aes), .valid_out_aes(valid_out_aes), .ready_out_aes(ready_out_aes),
        .instr_sha(instr_sha), .valid_out_sha(valid_out_sha), .ready_out_sha(ready_out_sha)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("deser_queue_tb.vcd");
        $dumpvars(0, deser_queue_tb);
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
            // wait for cs debounce WITHOUT clocking spi
            // just hold spi_clk low while cs settles
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

    task do_reset;
        begin
            rst_n = 0; cs_n = 1; mosi = 0; spi_clk = 0;
            ready_in_aes = 0; ready_in_sha = 0;
            #20 rst_n = 1;
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; spi_clk = 0; mosi = 0; cs_n = 1;
        ready_in_aes = 0; ready_in_sha = 0;
        #20 rst_n = 1; #50;

        // TEST 1: AES request, data integrity
        spi_frame(1, 0, 0, 24'hAA_0001, 24'hBB_0001, 24'hCC_0001);
        repeat (10) @(posedge clk);
        do_reset;

        // TEST 2: SHA request, correct routing
        spi_frame(1, 0, 1, 24'hAA_0002, 24'hBB_0002, 24'hCC_0002);
        repeat (10) @(posedge clk);
        do_reset;

        // TEST 3: backpressure: fill queue, 5th held
        repeat (4)
            spi_frame(1, 0, 0, 24'hAA_0003, 24'hBB_0003, 24'hCC_0003);
        spi_frame(1, 0, 0, 24'hFF_FFFF, 24'hFF_FFFF, 24'hFF_FFFF);
        repeat (20) @(posedge clk);
        ready_in_aes = 1;
        repeat (5) @(posedge clk);
        ready_in_aes = 0;
        repeat (20) @(posedge clk);
        do_reset;

        // TEST 4: back-to-back AES + SHA
        spi_frame(1, 0, 0, 24'hAA_0004, 24'hBB_0004, 24'hCC_0004);
        spi_frame(1, 0, 1, 24'hAA_0005, 24'hBB_0005, 24'hCC_0005);
        repeat (20) @(posedge clk);

        $finish;
    end

endmodule

