`default_nettype none

// --------------
// New Inputs:
// --------------
// req_valid: indicates an instruction is available in the request queue
// req_data[2*ADDRW+1:0]: the instruction itself
// bus_grant: from arbiter (FSM can use the bus now)
// ack_in[2:0]: ACKs for read/write/hash complete

// --------------
// New Outputs:
// --------------
// ready_req_out: signals completion (dequeue signal to request queue)
// bus_req: request access to bus
// data_in[7:0]: to data bus
// valid_in: data valid when sending

// -------------
// Notes:
// -------------
// req_valid / ready_req_out form a handshake with the request queue:
// FSM only starts when req_valid is asserted.
// FSM asserts ready_req_out for one cycle after completing all operations.
// bus_req / bus_grant form a handshake with the bus arbiter:
// FSM requests bus ownership when it needs to access memory or data bus.
// FSM only drives valid_in and data_in when bus_grant is asserted.
// ACK signals (ack_in) are event triggers for completion of each operation (read, hash, write).

module sha_fsm #(
    parameter ADDRW = 24,
    parameter ACCEL_ID = 2'b11
)(
    input  wire              clk,
    input  wire              rst_n,

    // Request queue interface
    input  wire              req_valid,
    input  wire [3*ADDRW+1:0] req_data,
    output reg               ready_req_out,  // tells input req queue to release
    output reg               valid_compq_out, // tells complete queue to accept current req 

    // Bus arbiter interface
    output reg               bus_req,
    input  wire              bus_grant,

    // ACKs from memory / accelerator
    input  wire [2:0]        ack_in,

    // Data bus interface
    output reg [ADDRW+7:0]   data_out
);

    localparam MEM_ID = 2'b00;

    // FSM states
    typedef enum logic [3:0] {
        READY      = 4'd0,
        REQ_BUS    = 4'd1,
        READKEY    = 4'd2,
        WAIT_RDKEY = 4'd3,
        READTEXT   = 4'd4,
        WAIT_RDTXT = 4'd5,
        HASHOP     = 4'd6,
        WAIT_HASH  = 4'd7,
        MEMWRITE   = 4'd8,
        WAIT_WRITE = 4'd9,
        COMPLETE   = 4'd10
    } state_t;

    state_t state, next_state;

    //---------------------------------
    // State Register
    //---------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= READY;
        else
            state <= next_state;
    end

    //---------------------------------
    // Next-State Logic
    //---------------------------------
    always @(*) begin
        next_state = state;
        bus_req = 1'b0;
        ready_req_out = 1'b0;
        valid_compq_out = 1'b0;
        data_out = 'b0;

        case (state)
            READY: begin
                ready_req_out = 1'b1;
                if (req_valid) begin
                    next_state = REQ_BUS;
                    bus_req = 1'b1;
                    data_out = {req_data[3*ADDRW-1:2*ADDRW], 2'b00, ACCEL_ID, MEM_ID, 2'b00};
                end
            end

            REQ_BUS: begin
                bus_req = 1'b1;
                if (bus_grant)
                    next_state = READKEY;
            end

            READKEY: begin
                valid_in = 1'b1;
                // issue read command
                next_state = WAIT_RDKEY;
            end

            WAIT_RDKEY: begin
                if (ack_in[0])  // READ COMPLETE
                    next_state = READTEXT;
            end

            READTEXT: begin
                valid_in = 1'b1;
                next_state = WAIT_RDTXT;
            end

            WAIT_RDTXT: begin
                if (ack_in[1])
                    next_state = HASHOP;
            end

            HASHOP: begin
                // issue hash start command
                next_state = WAIT_HASH;
            end

            WAIT_HASH: begin
                if (ack_in[2]) // hash done
                    next_state = MEMWRITE;
            end

            MEMWRITE: begin
                valid_in = 1'b1;
                next_state = WAIT_WRITE;
            end

            WAIT_WRITE: begin
                if (ack_in[0])
                    next_state = COMPLETE;
            end

            COMPLETE: begin
                ready_req_out = 1'b1;  // signal request queue
                next_state = READY;
            end

            default: next_state = READY;
        endcase
    end

endmodule
