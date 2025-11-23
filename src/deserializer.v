`default_nettype none

module deserializer #(
    parameter ADDRW   = 24,
    parameter OPCODEW = 2
) (
    //INPUTS: clk, rst_n, spi_clk, mosi, cs_n, aes_ready_in, sha_ready_in
    input  wire               clk,
    input  wire               rst_n,
    input  wire               spi_clk,
    input  wire               mosi,
    input  wire               cs_n,
    input  wire               aes_ready_in,
    input  wire               sha_ready_in,
    //OUTPUTS: opcode[1:0], key_addr[ADDRW-1:0], text_addr[ADDRW-1:0], valid_out
    output reg                valid, 
    output reg  [OPCODEW-1:0] opcode,     
    output reg  [ADDRW-1:0]   key_addr,
    output reg  [ADDRW-1:0]   text_addr,
    output reg  [ADDRW-1:0]   dest_addr,
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
    localparam integer SHIFT_W = 1 + OPCODEW + (3 * ADDRW); 
    localparam integer CW = clog2(SHIFT_W + 1);  

    //Synchronize
    reg [1:0] r_clk;
    reg [1:0] r_cs_n;
    reg [1:0] r_mosi;    

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin       // Changed to active-low reset
            r_clk <= 2'b00;     // Changed from 3'b00
            r_cs_n <= 2'b11;
            r_mosi <= 2'b00;
        end else begin
            r_clk <= {r_clk[0], spi_clk};
            r_cs_n <= {r_cs_n[0], cs_n};
            r_mosi <= {r_mosi[0], mosi};
        end
    end

    //Shift Data
    wire clk_posedge = (r_clk == 2'b01);  // detected posedge of spi_clk (0->1)
    wire cs_active  = ~r_cs_n[1];   // active-low CS
    wire mosi_s = r_mosi[1];

    reg [CW-1:0] cnt;  // how many bits of current word have been collected
    reg [SHIFT_W-1:0] shift_reg;
    reg busy;  // when pending_valid == 1, ignore new incoming bits
    
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin   // Active-low reset
            cnt        <= {CW{1'b0}};
            shift_reg  <= {SHIFT_W{1'b0}};
            busy       <= 1'b0;
            valid      <= 1'b0;
            opcode     <= {OPCODEW{1'b0}};
            key_addr   <= {ADDRW{1'b0}};
            text_addr  <= {ADDRW{1'b0}};
            dest_addr  <= {ADDRW{1'B0}}; 
            valid_out  <= 1'b0;
        end else begin
            valid_out <= 1'b0;  // one-cycle pulse default

            // shift register
            if (~r_cs_n[1]) begin                     // FIX: r_cs_n (synced CS), not r_cs
                if (clk_posedge && !busy) begin
                    // shift in data
                    shift_reg <= {shift_reg[SHIFT_W-2:0], r_mosi[1]};
                    if (cnt == (SHIFT_W-1)) begin
                        busy <= 1'b1;                 // full word captured
                        cnt  <= {CW{1'b0}};
                    end else begin
                        cnt <= cnt + 1'b1;            // increment count
                    end
                end
            end else begin
                // on de-assertion, clear partial word
                if (!busy) begin
                    cnt       <= {CW{1'b0}};
                    shift_reg <= {SHIFT_W{1'b0}};
                end
            end

            // decode shift-register output
            if (shift_reg[3*ADDRW]) begin
                // SHA
                if (busy && sha_ready_in) begin
                    valid     <= shift_reg[SHIFT_W-1];
                    opcode    <= shift_reg[SHIFT_W-2 : 3*ADDRW];
                    key_addr  <= shift_reg[3*ADDRW-1 : 2*ADDRW]; 
                    text_addr <= shift_reg[2*ADDRW-1 : ADDRW];
                    dest_addr <= shift_reg[ADDRW-1 : 0];
                    valid_out <= 1'b1;   
                    busy      <= 1'b0;
                end
            end else begin
                // AES
                if (busy && aes_ready_in) begin
                    valid     <= shift_reg[SHIFT_W-1];
                    opcode    <= shift_reg[SHIFT_W-2 : 3*ADDRW];
                    key_addr  <= shift_reg[3*ADDRW-1 : 2*ADDRW]; 
                    text_addr <= shift_reg[2*ADDRW-1 : ADDRW];
                    dest_addr <= shift_reg[ADDRW-1 : 0];
                    valid_out <= 1'b1;   
                    busy      <= 1'b0;
                end
            end
            
        end
    end
endmodule