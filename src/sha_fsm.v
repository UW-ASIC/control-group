`default_nettype none

// --------------
// New Inputs:
// --------------
// req_valid: indicates an instruction is available in the request queue
// req_data[2*ADDRW+1:0]: the instruction itself
// arb_grant: from arbiter (FSM can use the bus now)
// ack_in[2:0]: ACKs for read/write/hash complete
// --------------
// New Outputs:
// --------------
// ready_req_out: signals completion (dequeue signal to request queue)
// arb_req: request access to bus
// data_in[7:0]: to data bus
// valid_in: data valid when sending

// -------------
// Notes:
// -------------
// req_valid / ready_req_out form a handshake with the request queue:
// FSM only starts when req_valid is asserted.
// FSM asserts ready_req_out for one cycle after completing all operations.
// arb_req / arb_grant form a handshake with the bus arbiter:
// FSM requests bus ownership when it needs to access memory or data bus.
// FSM only drives valid_in and data_in when arb_grant is asserted.
// ACK signals (ack_in) are event triggers for completion of each operation (read, hash, write).

module sha_fsm #(
    parameter ADDRW = 24,
    parameter ACCEL_ID = 2'b01
)(
    input  wire              clk,
    input  wire              rst_n,

    // Request queue interface
    input  wire              req_valid,
    input  wire [2*ADDRW+1:0] req_data,
    output reg               ready_req_out,     // tells input req queue to release

    input wire               compq_ready_in,
    output reg [ADDRW-1:0]   compq_data_out,    // send output to xtal CPU to complete queue
    output reg               valid_compq_out,   // tells complete queue to accept current req 

    // Bus arbiter interface
    output reg               arb_req,
    input  wire              arb_grant,

    // ACKs from memory / accelerator
    input  wire [2:0]        ack_in,

    // Data bus interface
    output reg [ADDRW+7:0]   data_out
);

    localparam MEM_ID = 2'b00;

    // FSM states
    localparam READY        = 4'b0000;
    localparam RDTEXT       = 4'b0001;
    localparam WAIT_RDTXT   = 4'b0010;
    localparam HASHOP       = 4'b0011;
    localparam WAIT_HASHOP  = 4'b0100;
    localparam MEMWR        = 4'b0101;
    localparam WAIT_MEMWR   = 4'b0110;
    localparam COMPLETE     = 4'b0111;

    reg [3:0] state, next_state;

    // Request buffer
    reg [2*ADDRW+1:0] r_req_data;

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
        case (state)
            READY: begin
                if (req_valid) next_state = RDTEXT;
            end

            RDTEXT: begin
                if (arb_grant) next_state = WAIT_RDTXT;
            end

            WAIT_RDTXT: begin
                if (ack_in == {1'b1, MEM_ID}) next_state = HASHOP;
            end

            HASHOP: begin
                if (arb_grant) next_state = WAIT_HASHOP;
            end

            WAIT_HASHOP: begin
                if (ack_in == {1'b1, ACCEL_ID}) next_state = MEMWR;
            end

            MEMWR: begin
                if (arb_grant) next_state = WAIT_MEMWR;
            end

            WAIT_MEMWR: begin
                if (ack_in == {1'b1, MEM_ID}) next_state = COMPLETE;
            end

            COMPLETE: begin
                if (compq_ready_in) next_state = READY;
            end

            default: next_state = READY;
        endcase
    end

    //---------------------------------
    // Output Logic
    //---------------------------------
    always @(*) begin
        arb_req = 1'b0;
        ready_req_out = 1'b0;
        valid_compq_out = 1'b0;
        data_out = 'b0;
        compq_data_out = 'b0;
        case (state) 
            READY: begin
                ready_req_out = 1'b1;
            end

            RDTEXT: begin
                arb_req = 1'b1;
                data_out = {r_req_data[2*ADDRW-1:ADDRW], 2'b00, ACCEL_ID, MEM_ID, 2'b01};
            end

            WAIT_RDTXT: begin
                data_out = {r_req_data[2*ADDRW-1:ADDRW], 2'b00, ACCEL_ID, MEM_ID, 2'b01};
            end

            HASHOP: begin
                arb_req = 1'b1;
                data_out = {24'b0, r_req_data[73], 1'b0, ACCEL_ID, 4'b0011};
            end

            WAIT_HASHOP: begin
                data_out = {24'b0, r_req_data[73], 1'b0, ACCEL_ID, 4'b0011};
            end

            MEMWR: begin
                arb_req = 1'b1;
                data_out = {r_req_data[ADDRW-1:0], 2'b00, MEM_ID, ACCEL_ID, 2'b10};
            end

            WAIT_MEMWR: begin
                data_out = {r_req_data[ADDRW-1:0], 2'b00, MEM_ID, ACCEL_ID, 2'b10};
            end

            COMPLETE: begin
                compq_data_out = {r_req_data[ADDRW-1:0]};
                valid_compq_out = 1'b1;
            end

            default: begin
                // already zeroed above
            end
        endcase
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_req_data <= '0;
        end else if (req_valid && state == READY) begin
            r_req_data <= req_data;
        end
    end

endmodule
