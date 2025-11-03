module req_queue #(
    parameter ADDRW = 24,
    parameter OPCODEW = 2,
    parameter QDEPTH = 16
) (
    input wire clk,
    input wire rst_n,
    input wire valid_in,
    input wire ready_in_aes,
    input wire ready_in_sha,

    input wire [OPCODEW - 1:0] opcode,
    input wire [ADDRW - 1:0] key_addr,
    input wire [ADDRW - 1:0] text_addr,
    input wire [ADDRW - 1:0] dest_addr,

    output reg [3 * ADDRW + OPCODEW - 1:0] instr_aes,
    output reg valid_out_aes,
    output reg ready_out_aes,
    output reg [3 * ADDRW + OPCODEW - 1:0] instr_sha,
    output reg valid_out_sha,
    output reg ready_out_sha
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

    localparam integer INSTRW = 3 * ADDRW + OPCODEW;
    localparam integer QUEUEW = INSTRW * QDEPTH;
    localparam integer IDXW = clog2(QUEUEW);

    reg [QUEUEW - 1:0] aesQueue;
    reg [IDXW - 1:0] aesReadIdx;
    reg [IDXW - 1:0] aesWriteIdx;
    reg aesFull;
    reg [QUEUEW - 1:0] shaQueue;
    reg [IDXW - 1:0] shaReadIdx;
    reg [IDXW - 1:0] shaWriteIdx;
    reg shaFull;

    reg readyOutAesInternal;
    reg readyOutShaInternal;

    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            aesQueue <= {QUEUEW{1'b0}};
            aesReadIdx <= {IDXW{1'b0}};
            aesWriteIdx <= {IDXW{1'b0}};
            aesFull <= 0;
            shaQueue <= {QUEUEW{1'b0}};
            shaReadIdx <= {IDXW{1'b0}};
            shaWriteIdx <= {IDXW{1'b0}};
            shaFull <= 0;
            instr_aes <= {INSTRW{1'b0}};
            valid_out_aes <= 0;
            ready_out_aes <= 0;
            instr_sha <= {INSTRW{1'b0}};
            valid_out_sha <= 0;
            ready_out_sha <= 0;
        end else begin
            if (valid_in) begin
                if (readyOutAesInternal) begin
                    if (opcode[0] == 0) begin
                        aesQueue <= aesQueue ^ ((((aesQueue >> aesWriteIdx) ^ {opcode, key_addr, text_addr, dest_addr}) & ((1 << INSTRW) - 1)) << aesWriteIdx);
                        aesWriteIdx <= (aesWriteIdx + INSTRW) % QUEUEW;
                        if (aesWriteIdx == aesReadIdx) begin
                            aesFull <= 1;
                        end
                    end 
                end
                if (readyOutShaInternal) begin
                    if (opcode[0] == 1) begin
                        shaQueue <= shaQueue ^ ((((shaQueue >> shaWriteIdx) ^ {opcode, key_addr, text_addr, dest_addr}) & ((1 << INSTRW) - 1)) << shaWriteIdx);
                        shaWriteIdx <= (shaWriteIdx + INSTRW) % QUEUEW;
                        if (shaWriteIdx == shaReadIdx) begin
                            shaFull <= 1;
                        end
                    end
                end
            end
            if (ready_in_aes) begin
                if (valid_out_aes) begin
                    aesReadIdx <= (aesReadIdx + INSTRW) % QUEUEW;
                    valid_out_aes <= 0;
                    aesFull <= 0;
                    ready_out_aes <= 1;
                end else begin
                    instr_aes <= (aesQueue & (((1 << INSTRW) - 1) << aesReadIdx)) >> aesReadIdx;
                    valid_out_aes <= 1;
                end
            end else begin
                ready_out_aes <= readyOutAesInternal;
            end
            if (ready_in_sha) begin
                if (valid_out_sha) begin
                    shaReadIdx <= (shaReadIdx + INSTRW) % QUEUEW;
                    valid_out_sha <= 0;
                    shaFull <= 0;
                    ready_out_sha <= 1;
                end else begin
                    instr_sha <= (shaQueue & (((1 << INSTRW) - 1) << shaReadIdx)) >> shaReadIdx;
                    valid_out_sha <= 1;
                end
            end else begin
                ready_out_sha <= readyOutShaInternal;
            end
        end
    end

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            readyOutAesInternal <= 0;
            readyOutShaInternal <= 0;
        end else begin
            readyOutAesInternal <= (aesReadIdx != aesWriteIdx || !aesFull);
            readyOutShaInternal <= (shaReadIdx != shaWriteIdx || !shaFull);
        end
    end

endmodule
