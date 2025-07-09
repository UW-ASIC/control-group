interface cpu_to_control_req_if #(
    parameter ADDR_W = 10,
    parameter ADDR_W_ENCODING_W = 3,
    parameter CPU_OPCODE_W = 2
);
    logic [ADDR_W-1:0] text_addr;
    logic [ADDR_W_ENCODING_W-1:0] text_width;
    logic [ADDR_W-1:0] key_addr;
    logic [CPU_OPCODE_W-1:0] opcode;
    logic valid;
endinterface //cpu_to_control_req_if

interface internal_req_if #( //contains shared request information.
    parameter ADDR_W = 10,
    parameter OPCODE_W = 2,
    parameter ADDR_W_ENCODING_W = 4,
    parameter SRC_ID_W = 3
);
    logic [ADDR_W-1:0] addr;
    logic [ADDR_W_ENCODING_W-1:0] width;
    logic [SRC_ID_W-1:0] dest;
    logic [SRC_ID_W-1:0] source_id;
    logic [OPCODE_W-1:0] opcode; 
    logic valid;
endinterface //internal_req_if 