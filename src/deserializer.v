`default_nettype none

module deserializer # (
    parameter ADDRW = 8,    
)(
    //INPUTS: clk, rst_n, spi_clk, mosi, cs_n, ready_in
    input wire clk, 
    input wire rst_n, 
    input wire spi_clk, 
    input wire mosi,
    input wire cs_n,
    input wire ready_in,
    //OUTPUTS: opcode[1:0], key_addr[ADDRW-1:0], text_addr[ADDRW-1:0], valid_out
    output reg [1:0] opcode,
    output reg [ADDRW-1:0] key_addr,
    output reg [ADDRW-1:0] text_addr,
    output reg valid_out
);

/*Takes data received by xtal CPU via SPI, 
stores in shift register, 
then outputs full instruction in output ports 
and valid bit after shift register is populated, assuming request queue has room (is ready). 
We are using a fast clk for the chip (registers run on this clk) 
and a separate, slower spi_clk for data transmission 
(to correctly implement detect if a spi_clk posedge occurred at every chip clk posedge 
and shift in data to regs - if you get stuck here ask me). 
**Consider edge cases such as CS_n changing mid transmission
*/

/*STEP 1: Use SPI to retrieve data from xtal*/

/*STEP 2: Shift Register*/

/*STEP 3: After shift-reg population, output full instruction to OUTPUT PORT*/



endmodule