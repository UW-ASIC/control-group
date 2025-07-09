`include "common.sv"

module fsm_sketch #(
    parameter ADDR_W = 10,
    parameter CPU_OPCODE_W = 2,
    parameter OPCODE_W = 2,
    parameter ADDR_W_ENCODING_W = 3,
    parameter SRC_ID_W = 4,
    parameter OUR_SRC_ID = 0
) (
    input wire clk, //from top
    input wire rst_n, //asume negative reset for now

    input cpu_to_control_req_if cpu_req, //from req queue

    output logic ready_for_req, //to req queue

    input wire accel_ready, //from scoreboard
    input wire mem_ready,

    input wire ack, //from arbiter/sourceID matcher/idk yet
    input wire arb_won,

    output internal_req_if req, //to arbiter, not every field always used! more work to do later :))))
    output logic is_mem_req, //1 if 1 mem req, 0 if accel req

    output logic req_complete_valid, //to serializer
    output logic req_complete_address,
    output logic req_complete_source_id, //this routes through the serializer arbiter into the scoreboard to clear resources

    input wire serializer_arb_won //from serializer
    //I'm foreseeing an issue here where we can win the serializer when another FSM wins the noc arbiter and both will want the scoreboard, so the noc arbiter will depend on nothing winning the serializer arbiter ig LMAO
);
    typedef enum logic[2:0] { //state machine enum
        IDLE = 3'h0,
        READ_KEY = 3'h1,
        READ_TEXT = 3'h2,
        EXECUTE = 3'h3,
        ADDR2MEM = 3'h4,
        DATA2MEM = 3'h5,
        COMPLETE = 3'h6
    } state_t;

    state_t state, next_state;

    always_comb begin //combinational logic for state transitions
        next_state = state;

        case (state)
            IDLE: if (cpu_req.valid) next_state = READ_KEY;
            READ_KEY: if (ack) next_state = READ_TEXT;
            READ_TEXT: if (ack) next_state = EXECUTE;
            EXECUTE: if (ack) next_state = ADDR2MEM;
            ADDR2MEM: if (ack) next_state = DATA2MEM; //let these 2 packets go in parallel and fight it out :)), but needs a way to track 2 acks
            DATA2MEM: if (ack) next_state = COMPLETE;
            COMPLETE: if (serializer_arb_won) next_state = IDLE;
            default: ;
        endcase
    end

    logic [ADDR_W-1:0] cpu_req_text_addr;
    logic [ADDR_W_ENCODING_W-1:0] cpu_req_text_width;
    logic [ADDR_W-1:0] cpu_req_key_addr;
    logic [CPU_OPCODE_W-1:0] cpu_req_opcode;

    always_ff @( posedge clk ) begin //clock in request on idle -> not transition
        if(!rst_n) begin
            cpu_req_text_addr <= 0;
            cpu_req_text_width <= 0;
            cpu_req_key_addr <= 0;
            cpu_req_opcode <= 0;
        end else begin
            if (state == IDLE & cpu_req.valid) begin
                cpu_req_text_addr <= cpu_req.text_addr;
                cpu_req_text_width <= cpu_req.text_width;
                cpu_req_key_addr <= cpu_req.key_addr;
                cpu_req_opcode <= cpu_req.opcode; 
            end
        end
    end

    assign ready_for_req = (state == IDLE) | (state == IDLE & serializer_arb_won); //some optimization on ready for new req

    reg waiting_for_ack;

    always_ff @( posedge clk ) begin //to arbiter (req)
        if(!rst_n) begin
            req.addr <= 0;
            req.width <= 0;
            req.dest <= 0;
            req.source_id <= 0;
            req.opcode <= 0;
            req.valid <= 0;
            is_mem_req <= 0;
            waiting_for_ack <= 0;
        end else begin
            if (ack) waiting_for_ack <= 0;
            req.valid <= 0;
            case (state)
                READ_KEY: begin
                    if(!waiting_for_ack & mem_ready & accel_ready & !arb_won) begin
                        req.addr <= cpu_req_key_addr;
                        req.width <= TODO; //whatever encoding is our key encoding
                        //let scoreboard fill in our dest maybe? :eyes:
                        req.source_id <= OUR_SRC_ID;
                        req.opcode <= MEM_OPCODE_READ; //idk get some big declaration global table in here :)
                        req.valid <= 1;
                        is_mem_req <= 1;
                    end
                    if(arb_won) waiting_for_ack <= 1;
                end
                READ_TEXT: begin
                    if(!waiting_for_ack & mem_ready & !arb_won) begin //we've now claimed an accelerator, remove it from our list
                        req.addr <= cpu_req_text_addr;
                        req.width <= cpu_req_text_width; //whatever encoding is our key encoding
                        //let scoreboard fill in our dest maybe? :eyes:
                        req.source_id <= OUR_SRC_ID;
                        req.opcode <= MEM_OPCODE_READ; //idk get some big declaration global table in here :)
                        req.valid <= 1;
                        is_mem_req <= 1;
                    end
                    if(arb_won) waiting_for_ack <= 1;
                end
                EXECUTE: begin
                    if(!waiting_for_ack & !arb_won) begin
                        req.source_id <= OUR_SRC_ID;
                        req.opcode <= $cpu_opcode2accel_opcode(cpu_req_opcode); //idk get some big declaration global table in here :)
                        req.valid <= 1;
                        is_mem_req <= 0;
                    end
                    if(arb_won) waiting_for_ack <= 1;
                end
                ADDR2MEM: begin
                    if(!waiting_for_ack & mem_ready & !arb_won) begin
                        req.addr <= cpu_req_text_addr;
                        //let scoreboard fill in our dest maybe? :eyes:
                        req.source_id <= OUR_SRC_ID;
                        req.opcode <= MEM_OPCODE_WRITE_ADDR; //idk get some big declaration global table in here :)
                        req.valid <= 1;
                        is_mem_req <= 1;
                    end
                    if(arb_won) waiting_for_ack <= 1;
                end
                DATA2MEM: begin
                    if(!waiting_for_ack & !arb_won) begin //does not depend on mem_ready as we hold the memory resource from prev.
                        //let scoreboard fill in our dest maybe? :eyes:
                        //let dest field in this req be the memory ID
                        req.source_id <= OUR_SRC_ID;
                        req.opcode <= ACCEL_OPCODE_WRITE_DATA; //idk get some big declaration global table in here :)
                        req.valid <= 1;
                        is_mem_req <= 0;
                    end
                    if(arb_won) waiting_for_ack <= 1;
                end
                COMPLETE: begin
                    //don't need to worry about any difficult logic as there's no ack to wait on, once it's sent we're done B)
                    req_complete_valid <= 1;
                    req_complete_address <= cpu_req_text_addr;
                    req_complete_source_id <= OUR_SRC_ID;
                end
                default: ;
            endcase
        end
    end

    always_ff @( posedge clk ) begin //increment state machine
        if(!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
endmodule