`default_nettype none

module deserializer # (
    parameter ADDRW = 8,    
    parameter OPCODEW = 2
)(
    //INPUTS: clk, rst_n, spi_clk, mosi, cs_n, ready_in
    input wire clk, 
    input wire rst_n, 
    input wire spi_clk, 
    input wire mosi,
    input wire cs_n,
    input wire ready_in,
    //OUTPUTS: opcode[1:0], key_addr[ADDRW-1:0], text_addr[ADDRW-1:0], valid_out
    output reg  [1:0]       opcode,
    output reg  [ADDRW-1:0] key_addr,
    output reg  [ADDRW-1:0] text_addr,
    output reg              valid_out
);


    function integer clog2;
        input integer value;
        integer v, n;  // <-- declare n
        begin
            if (value <= 1) begin
                clog2 = 1;
            end else begin
                v = value - 1;
                n = 0;
                while (v > 0) begin
                    v = v >> 1;
                    n = n + 1;
                end
                clog2 = n;
            end
        end
    endfunction
    localparam integer SHIFT_W  = OPCODEW + (2*ADDRW);
    localparam integer CW       = clog2(SHIFT_W + 1); //counting width

    // CDC and edge detect logic, similar to the serializer style

    reg [1:0] clkstat;
    wire posedgeSPI = (clkstat == 2'b01);   // detected posedge of spi_clk (0->1)
    wire negedgeSPI = (clkstat == 2'b10);   // detected negedge of spi_clk (1->0)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clkstat <= 2'b00;
        end else begin
            clkstat <= {clkstat[0], spi_clk};
        end
    end

    // Synchronize cs_n to clk, then debounce it using SPI edges

// --- keep this simple 2-flop sync ---
reg [1:0] sync_n_cs;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sync_n_cs <= 2'b11;
    else        sync_n_cs <= {sync_n_cs[0], cs_n};
end

wire cs_n_s     = sync_n_cs[1];
wire ncs_active = ~cs_n_s;   // LOW = selected
// wire ncs_inactive = cs_n_s; // (unused)

// REMOVE hist/valid_ncs block entirely
// (delete: reg [1:0] hist; reg valid_ncs; the always @ for negedgeSPI)

    // In the main always @(posedge clk):
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ... existing resets ...
        end else begin
            valid_out <= 1'b0;

            // Immediate abort on CS high: drop partial word
            if (cs_n_s) begin
                cnt     <= {CW{1'b0}};
                SIPOreg <= {SHIFT_W{1'b0}};
            end else begin
                // normal shifting only when CS is low and no pending word
                if (posedgeSPI && !pending_valid) begin
                    SIPOreg <= { SIPOreg[SHIFT_W-2:0], mosi_s };
                    if (cnt == (SHIFT_W-1)) begin
                        pending_word  <= { SIPOreg[SHIFT_W-2:0], mosi_s };
                        pending_valid <= 1'b1;
                        cnt           <= {CW{1'b0}};
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
            end

            // Handshake stays as you had it
            if (pending_valid && ready_in) begin
                opcode    <= pending_word[SHIFT_W-1 : SHIFT_W-OPCODEW];
                key_addr  <= pending_word[SHIFT_W-OPCODEW-1 : SHIFT_W-OPCODEW-ADDRW];
                text_addr <= pending_word[ADDRW-1 : 0];
                valid_out <= 1'b1;
                pending_valid <= 1'b0;
            end
        end
    end

    // now synchronize MOSI into clk domain

    reg [1:0]   mosi_sync;
    wire        mosi_s = mosi_sync[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mosi_sync <= 2'b00;
        end else begin
            mosi_sync <= {mosi_sync[0], mosi};
        end
    end

    // Shift register and counter

    reg [CW-1:0]        cnt;        // how many bits of current word have been collected
    reg [SHIFT_W-1:0]   SIPOreg;    

    reg [SHIFT_W-1:0]   pending_word;   // once full instruction recieved, store and assert pending valid = 1
    reg                 pending_valid;  // when pending_valid == 1, ignore new incoming bits

    // handshake logic
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt             <= {CW{1'b0}};
            SIPOreg         <= {SHIFT_W{1'b0}};

            pending_word    <= {SHIFT_W{1'b0}};
            pending_valid   <= 1'b0;

            opcode          <= {OPCODEW{1'b0}};
            key_addr        <= {ADDRW{1'b0}};
            text_addr       <= {ADDRW{1'b0}};
            valid_out       <= 1'b0;
        end
        else begin
            valid_out <= 1'b0;

            // if we already have a completed word (pending valid) and downstream is ready, consume it
            if (pending_valid && ready_in) begin

                opcode          <= pending_word[SHIFT_W-1 : SHIFT_W-OPCODEW];
                key_addr        <= pending_word[SHIFT_W-OPCODEW-1 : SHIFT_W-OPCODEW-ADDRW];
                text_addr       <= pending_word[ADDRW-1 : 0];

                valid_out       <= 1'b1;    // 1cycle pause
                pending_valid   <= 1'b0;    // free 
            end

        // shift incoming bits from MOSI
        if (ncs_active) begin
            if (posedgeSPI && !pending_valid) begin

                SIPOreg <= { SIPOreg[SHIFT_W-2:0], mosi_s};

                if (cnt == (SHIFT_W-1)) begin
                    pending_word    <= {SIPOreg[SHIFT_W-2:0], mosi_s};
                    pending_valid   <= 1'b1;

                    //reset counter
                    cnt             <= {CW{1'b0}};
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end

        // if CS_n is inactive, dont use partial word and reset.
            else begin // ncs_inactive == 1

                cnt     <= {CW{1'b0}};
                SIPOreg <= {SHIFT_W{1'b0}};
            end
        end
    end


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