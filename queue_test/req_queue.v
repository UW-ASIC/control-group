module req_queue #(
    parameter ADDRW = 8,
    parameter OPCODEW = 2,
    parameter QLENGTH = 16
) (
    input wire clk,
    input wire rst_n,
    input wire valid_in,
    input wire ready_in_aes,
    input wire ready_in_sha,

    input wire [OPCODEW - 1:0] opcode,
    input wire [ADDRW - 1:0] key_addr,
    input wire [ADDRW - 1:0] text_addr,

    output reg [2 * ADDRW + OPCODEW - 1:0] instr,
    output reg valid_out,
    output reg ready_out
);

    localparam integer INSTRW = 2 * ADDRW + OPCODEW;
    localparam integer QUEUEW = INSTRW * QLENGTH;

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
            instr <= {INSTRW{1'b0}};
            valid_out <= 0;
            ready_out <= 0;
        end else begin
            // TODO
        end
    end

endmodule


// Request queue
// Inputs: opcode[1:0], key_addr[ADDRW-1:0], text_addr[ADDRW-1:0], valid_in, ready_in_aes, ready_in_sha
// Outputs: instr[2*ADDRW+1:0], valid_out, ready_out
// Description: A big FIFO queue of depth QLENGTH. Valid_in is asserted by deserializer once it has the full instruction from xtal CPU.
// ready_in signals come from FSMs when they are ready to begin a new operation. Assert valid_out when a queue entry is ready to be sent to an FSM,
// and remove the request from queue when both valid_out and ready_in are asserted. Deassert ready_out when the queue is full and do not take in
// further requests from Deserializer. 