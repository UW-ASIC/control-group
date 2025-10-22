module serializer #(
    parameter ADDRW = 8,
    parameter OPCODEW = 2
) (
    input wire clk,
    input wire rst_n, //must be held between a valid in and a ready_out
    input wire n_cs,
    input wire spi_clk,
    input wire valid_in,

    input wire [OPCODEW-1:0] opcode,
    input wire [ADDRW-1:0] addr,

    output reg miso,
    output reg ready_out
);
    function integer clog2;
        input integer value;
        integer v, i;
        begin
            v = value - 1;
            for (i = 0; v > 0; i = i + 1) v = v >> 1;
            clog2 = (value <= 1) ? 1 : i;
        end
    endfunction

    localparam integer SHIFT_W  = ADDRW + OPCODEW;
    localparam integer CW       = clog2(SHIFT_W + 1);     //addrw + opcode width 

    reg [CW-1:0] cnt;                           //count reg
    reg [SHIFT_W-1:0] PISOreg;                  //ASSUMES [opcode][ADDRW], left shift
    reg [1:0] clkstat;                          //clock for spi
    wire negedgeSPI = (clkstat == 2'b10);       //detect posedge of spi

    //posedge SPIclk, fSPIclk < fclk
    //posedge {01}, hi {11}, lo {00}, negedge {10}
    always @(posedge clk or negedge rst_n) begin 
        if (~rst_n) begin
            clkstat <=0;
        end else begin
            clkstat <= {clkstat[0], spi_clk};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin 
            ready_out   <= 1;
            cnt         <= (SHIFT_W-1);
            PISOreg     <= 0;
            miso        <= 1'b0;
        end
        else if (~n_cs) begin
            if (valid_in && ready_out == 1 && negedgeSPI) begin
                PISOreg     <= {opcode , addr};
                ready_out   <= 0;
                cnt         <= (SHIFT_W-1);
                miso        <= opcode[OPCODEW-1]; 

            end else if (negedgeSPI && !ready_out) begin
                miso        <= PISOreg[SHIFT_W-2];
                PISOreg     <= {PISOreg[SHIFT_W-2:0], 1'b0};

                if (cnt != 0) begin
                    cnt <= cnt - 1;
                end else begin 
                    ready_out <= 1;
                end
            end
        end
    end
    
endmodule


// Serializer
// Inputs: clk, rst_n, spi_clk, valid_in, opcode[1:0], addr[ADDRW-1:0]
// Outputs: miso, ready_out
// Description: When valid_in is asserted by complete queue, 
// takes in opcode and addr and loads into a shift register. 
// Set ready bit low so that request queue does not push another 
// instruction into the module and begin transmission to xtal CPU. 
// We are using a fast clk for the chip (registers run on this clk) and a separate, 
// slower spi_clk for data transmission (to correctly implement you'll need to detect if 
// a spi_clk negedge occurred at every chip clk posedge and shift out data to miso - 
// if you get stuck here ask me). 