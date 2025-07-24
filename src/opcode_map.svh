`ifndef OPCODE_MAP_SVH
`define OPCODE_MAP_SVH

`ifndef OPCODE_W
  `error "OPCODE_W must be defined before including OpcodeMap.svh"
`endif

// Opcode definitions using localparams
localparam logic [OPCODE_W-1:0] MEM_OPCODE_READ           = 'd0;
localparam logic [OPCODE_W-1:0] MEM_OPCODE_WRITE_ADDR     = 'd0;
localparam logic [OPCODE_W-1:0] ACCEL_OPCODE_WRITE_DATA   = 'd0;
localparam logic [OPCODE_W-1:0] ACCEL_OPCODE_SHA_DEC      = 'd1;
localparam logic [OPCODE_W-1:0] ACCEL_OPCODE_AES_ENC      = 'd2;
localparam logic [OPCODE_W-1:0] ACCEL_OPCODE_AES_DEC      = 'd3;
localparam logic [OPCODE_W-1:0] ACCEL_OPCODE_SHA_ENC      = 'd4;

`endif
