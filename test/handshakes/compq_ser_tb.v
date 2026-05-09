`timescale 1ns/1ps

module compq_ser_tb;

    parameter ADDRW  = 24;
    parameter QDEPTH = 32;

    reg clk, rst_n;
    reg spi_clk, n_cs;

    reg                 valid_in_aes;
    reg  [ADDRW-1:0]    dest_addr_aes;

    wire [ADDRW-1:0]    compq_data_out;
    wire                compq_valid_out;
    wire                ser_ready_out;
    wire                compq_ready_aes;
    wire                compq_ready_sha;

    wire                miso;
    wire                ser_err;


    comp_queue #(
        .ADDRW(ADDRW), .QDEPTH(QDEPTH)
    ) compq_inst (
        .clk(clk), .rst_n(rst_n),
        .valid_in_aes(valid_in_aes), .valid_in_sha(1'b0),
        .dest_addr_aes(dest_addr_aes), .dest_addr_sha({ADDRW{1'b0}}),
        .ready_out_aes(compq_ready_aes), .ready_out_sha(compq_ready_sha),
        .data_out(compq_data_out), .valid_out(compq_valid_out),
        .ready_in(ser_ready_out)
    );

    serializer #(
        .ADDRW(ADDRW)
    ) ser_inst (
        .clk(clk), .rst_n(rst_n),
        .n_cs(n_cs), .spi_clk(spi_clk),
        .valid_in(compq_valid_out), .addr(compq_data_out),
        .miso(miso), .ready_out(ser_ready_out), .err(ser_err)
    );

    always #5 clk = ~clk;
    always #25 spi_clk = ~spi_clk;

    initial begin
        $dumpfile("compq_ser_tb.vcd");
        $dumpvars(0, compq_ser_tb);
    end

    task do_reset;
        begin
            rst_n = 0; n_cs = 1;
            valid_in_aes = 0; dest_addr_aes = 0;
            #20 rst_n = 1;
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; spi_clk = 0; n_cs = 1;
        valid_in_aes = 0; dest_addr_aes = 0;
        #20 rst_n = 1; #50;

        // =============================================
        // TEST 1: single entry, serializer loads immediately
        // =============================================
        n_cs = 0;
        #500;

        @(posedge clk);
        valid_in_aes  = 1;
        dest_addr_aes = 24'hAA_0001;
        @(posedge clk);
        valid_in_aes  = 0;

        repeat (300) @(posedge clk);

        do_reset;

        // =============================================
        // TEST 2: back-to-back entries, second loads after first
        // =============================================
        n_cs = 0;
        #500;

        @(posedge clk);
        valid_in_aes  = 1;
        dest_addr_aes = 24'hBB_0001;
        @(posedge clk);
        dest_addr_aes = 24'hBB_0002;
        @(posedge clk);
        valid_in_aes  = 0;

        repeat (700) @(posedge clk);

        do_reset;

        // =============================================
        // TEST 3: n_cs yanked mid-shift
        // =============================================
        n_cs = 0;
        #500;

        @(posedge clk);
        valid_in_aes  = 1;
        dest_addr_aes = 24'hCC_0001;
        @(posedge clk);
        valid_in_aes  = 0;

        repeat (80) @(posedge clk);
        n_cs = 1;

        repeat (30) @(posedge clk);

        do_reset;

        // =============================================
        // TEST 4: three entries drain sequentially
        // =============================================
        n_cs = 0;
        #500;

        @(posedge clk);
        valid_in_aes  = 1;
        dest_addr_aes = 24'hDD_0001;
        @(posedge clk);
        dest_addr_aes = 24'hDD_0002;
        @(posedge clk);
        dest_addr_aes = 24'hDD_0003;
        @(posedge clk);
        valid_in_aes  = 0;

        repeat (1000) @(posedge clk);

        do_reset;

        // =============================================
        // TEST 5: data integrity — capture miso bits
        // =============================================
        n_cs = 0;
        #500;

        @(posedge clk);
        valid_in_aes  = 1;
        dest_addr_aes = 24'hDE_ADBE;
        @(posedge clk);
        valid_in_aes  = 0;

        repeat (400) @(posedge clk);

        $finish;
    end

endmodule