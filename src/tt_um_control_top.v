/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module control_top #(
  parameter ADDRW = 24,
  parameter OPCODEW = 2,
  parameter REQ_QDEPTH = 4,
  parameter COMP_QDEPTH = 4
  ) (
    output  wire       miso,
    input wire       mosi,
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       spi_clk,
    input  wire       rst_n,    // reset_n - low to reset
    input  wire       cs_n,
    input  wire [2:0] ack_in,
    input  wire       bus_ready,

    output reg [7:0]  data_bus_out,
    output reg        data_bus_valid
);

  localparam AES_INSTRW = 3*ADDRW + OPCODEW;
  localparam SHA_INSTRW = 2*ADDRW + OPCODEW;

  wire valid;
  wire [OPCODEW-1:0] opcode;
  wire [ADDRW-1:0] key_addr;
  wire [ADDRW-1:0] text_addr;
  wire [ADDRW-1:0] dest_addr;
  wire req_q_valid;
  deserializer #(.ADDRW(ADDRW), .OPCODEW(OPCODEW)) deserializer_inst(.clk(clk), .rst_n(rst_n), .spi_clk(spi_clk), .mosi(mosi), .cs_n(cs_n), .aes_ready_in(aes_queue_ready), .sha_ready_in(sha_queue_ready), .valid(valid), .opcode(opcode), .key_addr(key_addr), .text_addr(text_addr), .dest_addr(dest_addr), .valid_out(req_q_valid));

  wire aes_fsm_ready, sha_fsm_ready;
  wire [AES_INSTRW] instr_aes;
  wire [SHA_INSTRW] instr_sha;
  wire valid_out_aes, valid_out_sha;
  wire aes_queue_ready, sha_queue_ready;
  // May need to change deserializer so that it holds instruction until req_queue is ready for aes or sha
  req_queue #(.ADDRW(ADDRW) .OPCODEW(OPCODEW), .QDEPTH(REQ_QDEPTH)) req_queue_inst(.clk(clk), .rst_n(rst_n), .valid_in(req_q_valid), .ready_in_aes(aes_fsm_ready), .ready_in_sha(sha_fsm_ready), .opcode(opcode), .key_addr(key_addr), .text_addr(text_addr), .dest_addr(dest_addr), .instr_aes(instr_aes), .valid_out_aes(valid_out_aes), .ready_out_aes(aes_queue_ready), .instr_sha(instr_sha), .valid_out_sha(valid_out_sha), .ready_out_sha(sha_queue_ready));

  wire compq_ready_aes, compq_ready_sha;
  wire [ADDRW-1:0] compq_aes_data, compq_sha_data;
  wire compq_aes_valid, compq_sha_valid;
  aes_fsm #(.ADDRW(ADDRW)) aes_fsm_inst (.clk(clk), .rst_n(rst_n), .req_valid(valid_out_aes), .req_data(instr_aes), .ready_req_out(aes_fsm_ready), .compq_ready_in(compq_ready_aes), .compq_data_out(compq_aes_data), .valid_compq_out(compq_aes_valid), .arb_req(aes_arb_req), .arb_grant(aes_arb_grant), .ack_in(ack_in), .data_out(aes_fsm_data));
  sha_fsm #(.ADDRW(ADDRW)) sha_fsm_inst (.clk(clk), .rst_n(rst_n), .req_valid(valid_out_sha), .req_data(instr_sha), .ready_req_out(sha_fsm_ready), .compq_ready_in(compq_ready_sha), .compq_data_out(compq_sha_data), .valid_compq_out(compq_sha_valid), .arb_req(sha_arb_req), .arb_grant(sha_arb_grant), .ack_in(ack_in), .data_out(sha_fsm_data));

  wire aes_arb_req, sha_arb_req;
  wire [7:0] aes_fsm_data, sha_fsm_data;
  wire aes_arb_grant, sha_arb_grant;
  bus_arbiter #(.ADDRW(ADDRW)) bus_arbiter_inst (.clk(clk), .rst_n(rst_n), .sha_req(sha_arb_req), .aes_req(aes_arb_req), .sha_data_in(sha_fsm_data), .aes_data_in(aes_fsm_data), .bus_ready(bus_ready), .data_out(data_bus_out), .valid_out(data_bus_valid), .aes_grant(aes_arb_grant), .sha_grant(sha_arb_grant));

  wire [ADDRW-1:0] compq_data;
  wire compq_valid_out;
  wire compq_ready_in;
  comp_queue #(.ADDRW(ADDRW), .QDEPTH(COMP_QDEPTH)) comp_queue_inst (.clk(clk), .rst_n(rst_n), .valid_in_aes(compq_aes_valid), .valid_in_sha(compq_sha_valid), .dest_addr_aes(compq_aes_data), .dest_addr_sha(compq_sha_data), .ready_out_aes(compq_ready_aes), .ready_out_sha(compq_ready_sha), .data_out(compq_data), .valid_out(compq_valid_out), .ready_in(compq_ready_in));

  serializer #(.ADDRW(ADDRW)) serializer_inst(.clk(clk), .rst_n(rst_n), .n_cs(cs_n), .spi_clk(spi_clk), .valid_in(compq_valid_out), .addr(compq_data), .miso(miso), .ready_out(compq_ready_in), .err());
endmodule
