`default_nettype none
`include "common.sv"

module scoreboard #(
    parameter SRC_ID_W = 4,
    parameter NUM_SHA = 1,
    parameter NUM_AES = 1,
    parameter NUM_MEM = 1,
    parameter OPCODE_W = 2,
    //FSM source IDs
    parameter logic [SRC_ID_W*NUM_SHA-1:0] SHA_FSM_SRC_IDS = 0, //just pack'em together :))
    parameter logic [SRC_ID_W*NUM_AES-1:0] AES_FSM_SRC_IDS = 0,
    //Resourece source IDs
    parameter logic [SRC_ID_W*NUM_SHA-1:0] SHA_RES_SRC_IDS = 0, //just pack'em together :))
    parameter logic [SRC_ID_W*NUM_AES-1:0] AES_RES_SRC_IDS = 0,
    parameter logic [SRC_ID_W*NUM_SHA-1:0] MEM_RES_SRC_IDS = 0
) (
    input wire clk,
    input wire rst_n,

    input wire req_valid,
    input wire [SRC_ID_W-1:0] req_src_id,
    input wire [OPCODE_W-1:0] req_opcode,

    input wire ack_valid,
    input wire [SRC_ID_W-1:0] ack_src_id, //this ack is the address of the source of the ack, not the fsm it's acking -- idk we can change this later I'm iffy on it

    output logic out_valid,
    output logic [SRC_ID_W-1:0] out_mem_id,
    output logic [SRC_ID_W-1:0] out_accel_id,

    output logic mem_ready
);
    //we can have NUM_SHA + NUM_AES live requests in the system. Assign each FSM statically to an accelerator and share the memory. (idk you can probably optimize this :))
    typedef struct packed {
        logic [SRC_ID_W-1:0] resource_id;
        logic [SRC_ID_W-1:0] req_id;
    } scoreboard_accel_bundle; //and hence, no valid bit needed

    typedef struct packed {
        logic [SRC_ID_W-1:0] resource_id;
        logic [SRC_ID_W-1:0] req_id;
        logic [SRC_ID_W-1:0] accel_id; //I hate adding this soz
        logic valid;        
    } scoreboard_mem_bundle;

    scoreboard_accel_bundle [NUM_AES - 1:0] aes_array;
    scoreboard_accel_bundle [NUM_SHA - 1:0] sha_array;
    scoreboard_mem_bundle [NUM_MEM - 1:0] mem_array;

    logic free_mem_found;
    logic mem_match; //for ack matching
    logic [safe_clog2(NUM_MEM)-1:0] free_mem_idx;
    logic [safe_clog2(NUM_AES)-1:0] mem_match_idx;
    

    always_comb begin //get free memory index so we only claim 1 memory bank at a time :)
        free_mem_found = 1'b0;
        mem_match = 1'b0;
        free_mem_idx = '0;
        mem_match_idx = '0;

        for (int i = 0; i < NUM_MEM; i = i + 1) begin
            if (!mem_array[i].valid && !free_mem_found) begin
            free_mem_found = 1'b1;
            free_mem_idx = i[safe_clog2(NUM_MEM)-1:0];
            end
            if (mem_array[i].resource_id == ack_src_id) begin //but also, we can get a memory matching index here !
                mem_match_idx = i[safe_clog2(NUM_MEM)-1:0];
            end
        end
    end

    logic [safe_clog2(NUM_AES)-1:0] aes_idx;
    logic [safe_clog2(NUM_SHA)-1:0] sha_idx;
    logic aes_match;
    logic sha_match;

    always_comb begin //tagmatch aes and sha, will only tagmatch one!
        aes_idx = '0;
        sha_idx = '0;
        aes_match = 1'b0;
        sha_match = 1'b0;
        for (int i = 0; i < NUM_AES; i = i +1) begin
            if (aes_array[i].req_id == req_src_id) begin
                aes_idx = i[NUM_AES-1:0];
                aes_match = 1'b1;
            end
        end
        for (int i = 0; i < NUM_SHA; i = i +1) begin
            if (sha_array[i].req_id == req_src_id) begin
                sha_idx = i[NUM_AES-1:0];
                sha_match = 1'b1;
            end
        end
    end

    assign mem_ready = free_mem_found;

    logic memory_needed = (req_opcode == MEM_OPCODE_READ) || (req_opcode == MEM_OPCODE_WRITE_ADDR); //implicitly hold mem on addr

    always_ff @( clk ) begin //array logic yum
        if (~rst_n) begin
            mem_array <= '0; //fills in valid bits
            out_mem_id  <= '0;
            out_accel_id <= '0;
            for (int i = 0 ; i < NUM_AES ; i = i + 1 ) begin
                aes_array[i].resource_id <= AES_RES_SRC_IDS[(i)*SRC_ID_W+:SRC_ID_W]; //set the resource bindings statically!
                aes_array[i].req_id <= AES_FSM_SRC_IDS[(i)*SRC_ID_W+:SRC_ID_W];
            end
            for (int i = 0 ; i < NUM_SHA ; i = i + 1 ) begin
                sha_array[i].resource_id <= SHA_RES_SRC_IDS[(i)*SRC_ID_W+:SRC_ID_W];
                sha_array[i].req_id <= SHA_FSM_SRC_IDS[(i)*SRC_ID_W+:SRC_ID_W];
            end
            for (int i = 0 ; i < NUM_MEM ; i = i + 1 ) begin
                mem_array[i].resource_id <= MEM_RES_SRC_IDS[(i)*SRC_ID_W+:SRC_ID_W];
            end
        end else begin //idea: for each scoreboard entry, if we match the request id (essentially tagmatch), claim it
            out_mem_id <= '0; //no latches in this house B)
            out_accel_id <= '0;

            if (ack_valid) begin
                if ((mem_array[mem_match_idx].resource_id == ack_src_id ^ mem_array[mem_match_idx].req_id == ack_src_id) && mem_match) begin //if this ack comes from a memory module and isn't currently locked by an fsm (for writeData)
                    mem_array[mem_match_idx].valid <= 1'b0;
                end else if (mem_match) begin
                    mem_array[mem_match_idx].req_id <= mem_array[mem_match_idx].accel_id; //so the next time the accel acks, it'll free the memory!
                end
            end

            if (req_valid) begin
                if (memory_needed) begin //we *should* only get this request if there is a free memory slot :eyes:
                    mem_array[free_mem_idx].valid <= 1'b1; //mark as in use
                    out_mem_id <= mem_array[free_mem_idx].resource_id;
                    if (req_opcode == MEM_OPCODE_WRITE_ADDR) begin
                        mem_array[free_mem_idx].req_id <= mem_array[free_mem_idx].resource_id; //lock the memory on write addr by doubling
                        mem_array[free_mem_idx].accel_id <= aes_match ? aes_array[aes_idx].resource_id : sha_array[sha_idx].resource_id; //lazy ternary mb
                    end else begin
                        mem_array[free_mem_idx].req_id <= req_src_id; //don't lock the memory
                    end
                end else begin
                    if (aes_match) begin
                        out_accel_id <= aes_array[aes_idx].resource_id;
                    end
                    if (sha_match) begin
                        out_accel_id <= sha_array[sha_idx].resource_id;
                    end
                end
            end
        end
    end
endmodule