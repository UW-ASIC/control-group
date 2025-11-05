`default_nettype none

module deserializer #(
    parameter ADDRW   = 8,
    parameter OPCODEW = 2
) (
    //INPUTS: clk, rst_n, spi_clk, mosi, cs_n, ready_in
    input  wire               clk,
    input  wire               rst_n,
    input  wire               spi_clk,
    input  wire               mosi,
    input  wire               cs_n,
    input  wire               ready_in,
    //OUTPUTS: opcode[1:0], key_addr[ADDRW-1:0], text_addr[ADDRW-1:0], valid_out
    output reg  [OPCODEW-1:0] opcode,     // width from OPCODEW
    output reg  [  ADDRW-1:0] key_addr,
    output reg  [  ADDRW-1:0] text_addr,
    output reg                valid_out
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
    localparam integer SHIFT_W = OPCODEW + (2 * ADDRW);
    localparam integer CW = clog2(SHIFT_W + 1);  //counting width

    // CDC and edge detect logic, similar to the serializer style

    reg [1:0] clkstat;
    reg [1:0] sync_n_cs;
    reg [1:0] mosi_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clkstat   <= 2'b00;
            sync_n_cs <= 2'b11;
            mosi_sync <= 2'b00;
        end else begin
            clkstat   <= {clkstat[0], spi_clk};
            sync_n_cs <= {sync_n_cs[0], cs_n};
            mosi_sync <= {mosi_sync[0], mosi};
        end
    end

    wire posedgeSPI = (clkstat == 2'b01);  // detected posedge of spi_clk (0->1)
    wire cs_n_s = sync_n_cs[1];
    wire ncs_active = ~cs_n_s;  // LOW = selected
    wire mosi_s = mosi_sync[1];


    // shift/handshake

    reg [CW-1:0] cnt;  // how many bits of current word have been collected
    reg [SHIFT_W-1:0] SIPOreg;

    reg pending_valid;  // when pending_valid == 1, ignore new incoming bits

    // Shift register and counter

    // sole shift/handshake block

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt           <= {CW{1'b0}};
            SIPOreg       <= {SHIFT_W{1'b0}};

            pending_valid <= 1'b0;

            opcode        <= {OPCODEW{1'b0}};
            key_addr      <= {ADDRW{1'b0}};
            text_addr     <= {ADDRW{1'b0}};
            valid_out     <= 1'b0;
        end else begin
            valid_out <= 1'b0;

            // if we already have a completed word (pending valid) and downstream is ready, consume it
            if (pending_valid && ready_in) begin

                opcode        <= SIPOreg[SHIFT_W-1 : SHIFT_W-OPCODEW];  // decode from shift reg
                key_addr      <= SIPOreg[SHIFT_W-OPCODEW-1 : SHIFT_W-OPCODEW-ADDRW];
                text_addr     <= SIPOreg[ADDRW-1 : 0];

                valid_out     <= 1'b1;  // 1cycle pause
                pending_valid <= 1'b0;  // free
            end

            // shift incoming bits from MOSI
            if (ncs_active) begin
                if (posedgeSPI && !pending_valid) begin

                    SIPOreg <= {SIPOreg[SHIFT_W-2:0], mosi_s};

                    if (cnt == (SHIFT_W - 1)) begin
                        // full word captured in SIPOreg
                        pending_valid <= 1'b1;

                        //reset counter
                        cnt           <= {CW{1'b0}};
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
            end  // if CS_n is inactive, dont use partial word and reset.
            else begin  // ncs_inactive == 1

                if (!pending_valid) begin  // keep completed word under backpressure
                    cnt     <= {CW{1'b0}};
                    SIPOreg <= {SHIFT_W{1'b0}};
                end
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
