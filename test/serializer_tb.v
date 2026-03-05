`default_nettype none
`timescale 1ns/1ps

module serializer_tb #(
    parameter ADDRW = 24
);

    reg clk;
    reg rst_n;

    // SPI interface
    reg n_cs;
    reg spi_clk;

    // Input from comp_queue
    reg              valid_in;
    reg [ADDRW-1:0]  addr;

    // Outputs
    wire miso;
    wire ready_out;
    wire err;

    serializer #(
        .ADDRW(ADDRW)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .n_cs     (n_cs),
        .spi_clk  (spi_clk),
        .valid_in (valid_in),
        .addr     (addr),
        .miso     (miso),
        .ready_out(ready_out),
        .err      (err)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("serializer_tb.vcd");
        $dumpvars(0, serializer_tb);
    end

endmodule
