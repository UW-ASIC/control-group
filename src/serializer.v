module serializer #(
    parameter ADDRW = 24
) (
    input wire clk,
    input wire rst_n,       
    input wire n_cs,        //must be held between a valid in and a ready_out
    input wire spi_clk,
    input wire valid_in,

    input wire [ADDRW-1:0]      addr,

    output reg  miso,
    output reg  ready_out,
    output reg  err          //Error flag. Deserializer must reject collected data within txn 
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

    localparam integer SHIFT_W  = ADDRW;
    localparam integer CW       = clog2(SHIFT_W + 1);     //addrw + valid width 

    reg [CW-1:0] cnt;                               //count reg
    reg [SHIFT_W-1:0] PISOreg;                      //ASSUMES 25 -> [VALID][ADDRW] -> 0, left shift 
    reg [1:0] clkstat;                              //clock for spi
    wire negedgeSPI = (clkstat == 2'b10);           //detect edge
    
    reg [1:0] sync_n_cs;                       //sync reg
    reg [1:0] hist;                            //similar to clockstat, used to detect held values. 
    reg valid_ncs;                             //clean ncs 

    ////////////////////////////////////
    //fSPIclk < fclk
    //posedge {01}, hi {11}, lo {00}, negedge {10}
    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            clkstat <=0;
        end else begin
            clkstat <= {clkstat[0], spi_clk};
        end
    end

    ////////////////////////////////////
    //n_cs "debounce"
    //note, this can also be debounced to the sysclk instead, but then you have some cases where you have an extra
    //spi clock edge, and other cases you dont. Just making it on spi clock edge makes it consistent. Technically it is possible
    //for a rare glitch which manages to occur on two negedges of spi to trigger a false exit/entry, 
    //but 1. if you have glitches that long, there are probably bigger problems, and 2. any fast clock based sampling gets really complicated if you want
    //to harden to any fclk >= fspi_clk and im still assuming we are lacking a bit on floorspace. 

    //synchronize n_cs to sysclk
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_n_cs <= 2'b11;                     //default ncs is high
        end else begin
            sync_n_cs <= {sync_n_cs[0], n_cs};      //SAFE DATA IS ON sync_n_cs[1]
        end
    end

    //"debounce"
    always@(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin //reset counters
            hist            <= 2'b11;
            valid_ncs       <= 1'b1;                      //default ncs is high
        end else begin
            if (negedgeSPI) begin
                hist <= {hist[0], sync_n_cs[1]};          //shift reg effectively allows 1 spi clock delay as it takes 1 clock cycle to update reg to both be equal
                if (hist[1] == hist[0]) begin
                    valid_ncs <= hist[1]; 
                end
            end
        end
    end

    ////////////////////////////////////
    //actual shift reg and sending of data
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            ready_out   <= 1;
            cnt         <= (SHIFT_W-1);
            PISOreg     <= 0;
            miso        <= 1'b0;
            err         <= 1'b0;
        end
        else if (~valid_ncs) begin
            if (valid_in && ready_out == 1 && negedgeSPI) begin
                PISOreg     <= {1'b1 , addr};
                ready_out   <= 0;
                cnt         <= (SHIFT_W-1);
                miso        <= 1'b1;
            end else if (negedgeSPI && !ready_out) begin
                miso        <= PISOreg[SHIFT_W-1];
                PISOreg     <= {PISOreg[SHIFT_W-1:0], 1'b0};

                if (cnt != 1) begin
                    cnt <= cnt - 1;
                end else begin 
                    ready_out <= 1;
                end
            end

        ////////////////////////////////////
        //Error handling
        end else if (valid_ncs && !ready_out) begin //ncs goes high while ready_out still ongoing, clear error state and raise flag
            err         <= 1'b1;
            ready_out   <= 1;
            cnt         <= (SHIFT_W-1);
            PISOreg     <= 0;
            miso        <= 1'b0;
        end else begin
            err <= 1'b0;
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

 //No longer needed because the shifter will always have one off error. 
                                                    //Alternatively can replace and then force deseralizer to discard last bit.
                                                    //Leaving like this means deseralizer can discard first bit instead. Easier just keep shifting
                                                    //and naturally throw away the first bit.
