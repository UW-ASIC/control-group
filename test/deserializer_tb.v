`default_nettype none
`timescale 1ns/1ps

module deserializer_tb #(
    parameter ADDRW   = 24,
    parameter OPCODEW = 2
);

    reg clk;
    reg rst_n;

    // SPI interface
    reg spi_clk;
    reg mosi;
    reg cs_n;

    // Backpressure from req_queue
    reg aes_ready_in;
    reg sha_ready_in;

    // Decoded outputs
    wire valid;
    wire [OPCODEW-1:0] opcode;
    wire [ADDRW-1:0]   key_addr;
    wire [ADDRW-1:0]   text_addr;
    wire [ADDRW-1:0]   dest_addr;
    wire               valid_out;

    deserializer #(
        .ADDRW(ADDRW),
        .OPCODEW(OPCODEW)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .spi_clk      (spi_clk),
        .mosi         (mosi),
        .cs_n         (cs_n),
        .aes_ready_in (aes_ready_in),
        .sha_ready_in (sha_ready_in),
        .valid        (valid),
        .opcode       (opcode),
        .key_addr     (key_addr),
        .text_addr    (text_addr),
        .dest_addr    (dest_addr),
        .valid_out    (valid_out)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("deserializer_tb.vcd");
        $dumpvars(0, deserializer_tb);
    end

endmodule
