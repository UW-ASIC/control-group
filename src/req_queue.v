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

    output wire [3 * ADDRW + OPCODEW - 1:0] instr_aes,
    output wire valid_out_aes,
    output wire ready_out_aes,
    output wire [2 * ADDRW + OPCODEW - 1:0] instr_sha,
    output wire valid_out_sha,
    output wire ready_out_sha
);

    integer i;

    initial begin
        $dumpfile("tb.vcd");
        for (i = 0; i < QDEPTH; i = i + 1) $dumpvars(0, aesQueue[i]);
        for (i = 0; i < QDEPTH; i = i + 1) $dumpvars(0, shaQueue[i]);
    end

    localparam integer SHA_INSTRW = 2 * ADDRW + OPCODEW;
    localparam integer AES_INSTRW = 3 * ADDRW + OPCODEW;
    localparam integer IDXW = (QDEPTH <= 1) ? 1 : $clog2(QDEPTH);
    localparam integer LAST_IDX = QDEPTH - 1;

    reg [AES_INSTRW - 1:0] aesQueue [QDEPTH - 1:0];
    reg [IDXW-1:0] aesReadIdx;
    reg [IDXW-1:0] aesWriteIdx;
    reg aesFull;
    reg [SHA_INSTRW - 1:0] shaQueue [QDEPTH - 1:0];
    reg [IDXW-1:0] shaReadIdx;
    reg [IDXW-1:0] shaWriteIdx;
    reg shaFull;

    assign ready_out_aes = (aesReadIdx != aesWriteIdx || !aesFull) && rst_n;
    assign ready_out_sha = (shaReadIdx != shaWriteIdx || !shaFull) && rst_n;
    assign valid_out_aes = (aesReadIdx != aesWriteIdx || aesFull) && rst_n;
    assign valid_out_sha = (shaReadIdx != shaWriteIdx || shaFull) && rst_n;
    assign instr_aes = aesQueue[aesReadIdx];
    assign instr_sha = shaQueue[shaReadIdx];

    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            for (i = 0; i < QDEPTH; i = i + 1) aesQueue[i] <= {AES_INSTRW{1'b0}};
            aesReadIdx <= {IDXW{1'b0}};
            aesWriteIdx <= {IDXW{1'b0}};
            aesFull <= 0;
            for (i = 0; i < QDEPTH; i = i + 1) shaQueue[i] <= {SHA_INSTRW{1'b0}};
            shaReadIdx <= {IDXW{1'b0}};
            shaWriteIdx <= {IDXW{1'b0}};
            shaFull <= 0;
        end else begin
            if (valid_in) begin
                if (ready_out_aes) begin
                    if (opcode[0] == 0) begin
                            aesQueue[aesWriteIdx] <= {opcode, key_addr, text_addr, dest_addr};
                            // compute next index without using % to avoid width warnings
                            if (aesWriteIdx == LAST_IDX) begin
                                if (aesReadIdx == {IDXW{1'b0}}) aesFull <= 1;
                                aesWriteIdx <= {IDXW{1'b0}};
                            end else begin
                                if (aesReadIdx == aesWriteIdx + 1) aesFull <= 1;
                                aesWriteIdx <= aesWriteIdx + 1;
                            end
                    end
                end
                if (ready_out_sha) begin
                    if (opcode[0] == 1) begin
                        shaQueue[shaWriteIdx] <= {opcode, text_addr, dest_addr};
                        if (shaWriteIdx == LAST_IDX) begin
                            if (shaReadIdx == {IDXW{1'b0}}) shaFull <= 1;
                            shaWriteIdx <= {IDXW{1'b0}};
                        end else begin
                            if (shaReadIdx == shaWriteIdx + 1) shaFull <= 1;
                            shaWriteIdx <= shaWriteIdx + 1;
                        end
                    end
                end
            end
            if (ready_in_aes) begin
                if (aesReadIdx == LAST_IDX) aesReadIdx <= {IDXW{1'b0}};
                else aesReadIdx <= aesReadIdx + 1;
                aesFull <= 0;
            end
            if (ready_in_sha) begin
                if (shaReadIdx == LAST_IDX) shaReadIdx <= {IDXW{1'b0}};
                else shaReadIdx <= shaReadIdx + 1;
                shaFull <= 0;
            end
        end
    end

endmodule


// Request queue
// Inputs: opcode[1:0], key_addr[ADDRW-1:0], text_addr[ADDRW-1:0], dest_addr[ADDRW-1:0], valid_in, ready_in_aes, ready_in_sha
// Outputs: instr_aes[2*ADDRW+1:0], valid_out_aes, ready_out_aes, instr_sha[2*ADDRW+1:0], valid_out_sha, ready_out_sha
// Description: A big FIFO queue of depth QDEPTH. Valid_in is asserted by deserializer once it has the full instruction from xtal CPU.
// ready_in signals come from FSMs when they are ready to begin a new operation. Assert valid_out when a queue entry is ready to be sent to an FSM,
// and remove the request from queue when ready_in is asserted. Deassert ready_out when the queue is full and do not take in
// further requests from Deserializer.
