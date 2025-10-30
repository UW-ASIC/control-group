module req_queue #(
    parameter ADDRW = 8,
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

    output reg [2 * ADDRW + OPCODEW - 1:0] instr_aes,
    output reg valid_out_aes,
    output reg ready_out_aes,
    output reg [2 * ADDRW + OPCODEW - 1:0] instr_sha,
    output reg valid_out_sha,
    output reg ready_out_sha
);

    localparam integer INSTRW = 2 * ADDRW + OPCODEW;
    localparam integer QUEUEW = INSTRW * QDEPTH;

    reg [QUEUEW - 1:0] aesQueue;
    reg aesReadIdx;
    reg aesWriteIdx;
    reg [QUEUEW - 1:0] shaQueue;
    reg shaReadIdx;
    reg shaWriteIdx;

    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            aesQueue <= {QUEUEW{1'b0}};
            aesReadIdx <= 0;
            aesWriteIdx <= 0;
            shaQueue <= {QUEUEW{1'b0}};
            shaReadIdx <= 0;
            shaWriteIdx <= 0;
            instr_aes <= {INSTRW{1'b0}};
            valid_out_aes <= 0;
            ready_out_aes <= 0;
            instr_sha <= {INSTRW{1'b0}};
            valid_out_sha <= 0;
            ready_out_sha <= 0;
        end else begin
            ready_out_aes <= (aesReadIdx != aesWriteIdx);
            ready_out_sha <= (shaReadIdx != shaWriteIdx);
            if (valid_in) begin
                if (ready_out_aes) begin
                    if (opcode[0] == 0) begin
                        aesQueue <= aesQueue ^ ((((aesQueue >> aesWriteIdx) ^ {opcode, key_addr, text_addr}) & ((1 << INSTRW) - 1)) << aesWriteIdx);
                        aesWriteIdx <= (aesWriteIdx + INSTRW) % QUEUEW;
                    end 
                end
                if (ready_out_sha) begin
                    if (opcode[0] == 1) begin
                        shaQueue <= shaQueue ^ ((((shaQueue >> shaWriteIdx) ^ {opcode, key_addr, text_addr}) & ((1 << INSTRW) - 1)) << shaWriteIdx);
                        shaWriteIdx <= (shaWriteIdx + INSTRW) % QUEUEW;
                    end
                end
            end
            if (ready_in_aes) begin
                if (valid_out_aes) begin
                    aesReadIdx <= (aesReadIdx + INSTRW) % QUEUEW;
                    valid_out_aes <= 0;
                end else begin
                    instr_aes <= aesQueue & (((1 << INSTRW) - 1) << aesReadIdx);
                    valid_out_aes <= 1;
                end
            end
            if (ready_in_sha) begin
                if (valid_out_sha) begin
                    shaReadIdx <= (shaReadIdx + INSTRW) % QUEUEW;
                    valid_out_sha <= 0;
                end else begin
                    instr_sha <= shaQueue & (((1 << INSTRW) - 1) << shaReadIdx);
                    valid_out_sha <= 1;
                end
            end
        end
    end

endmodule


// Request queue
// Inputs: opcode[1:0], key_addr[ADDRW-1:0], text_addr[ADDRW-1:0], valid_in, ready_in_aes, ready_in_sha
// Outputs: instr_aes[2*ADDRW+1:0], valid_out_aes, ready_out_aes, instr_sha[2*ADDRW+1:0], valid_out_sha, ready_out_sha
// Description: A big FIFO queue of depth QDEPTH. Valid_in is asserted by deserializer once it has the full instruction from xtal CPU.
// ready_in signals come from FSMs when they are ready to begin a new operation. Assert valid_out when a queue entry is ready to be sent to an FSM,
// and remove the request from queue when both valid_out and ready_in are asserted. Deassert ready_out when the queue is full and do not take in
// further requests from Deserializer. 

// There is an underlying assumption of an OOKKKKKKKKTTTTTTTT instruction, where the least significant bit denotes AES/SHA.