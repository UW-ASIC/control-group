`ifndef CPU_OPCODE_MAP_SVH
`define CPU_OPCODE_MAP_SVH

`ifndef CPU_OPCODE_W
  `error "CPU_OPCODE_W must be defined before including OpcodeMap.svh"
`endif

// Opcode definitions using localparams
localparam logic [CPU_OPCODE_W-1:0] CPU_OPCODE_SHA_ENC          = 'd0;
localparam logic [CPU_OPCODE_W-1:0] CPU_OPCODE_SHA_DEC          = 'd1;
localparam logic [CPU_OPCODE_W-1:0] CPU_OPCODE_AES_ENC          = 'd2;
localparam logic [CPU_OPCODE_W-1:0] CPU_OPCODE_AES_DEC          = 'd3;
localparam logic [CPU_OPCODE_W-1:0] CPU_OPCODE_EXPLODE_THE_MOON = 'd4;

`endif
