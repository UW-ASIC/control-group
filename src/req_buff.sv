`default_nettype none
`include "common.sv"

module req_buf_1deep #(
    parameter ADDR_W = 10,
    parameter ADDR_W_ENCODING_W = 3,
    parameter CPU_OPCODE_W = 2
)(
    input logic clk,
    input logic rst_n,

    input cpu_to_control_req_if in_if,
    output logic in_ready,

    output cpu_to_control_req_if out_if,

    input logic free_aes,
    input logic free_sha
);
    `include "cpu_opcode_map.svh" //depends on cpu_opcode_w being instantiated

    logic [ADDR_W-1:0] text_addr;
    logic [ADDR_W_ENCODING_W-1:0] text_width;
    logic [ADDR_W-1:0] key_addr;
    logic [CPU_OPCODE_W-1:0] opcode;
    logic valid;

    always_comb begin //ready depends on the state of the buffer + 
        in_ready = !valid || ((opcode == CPU_OPCODE_AES_ENC || opcode == CPU_OPCODE_AES_DEC) && free_aes) || ((opcode == CPU_OPCODE_SHA_ENC || opcode == CPU_OPCODE_SHA_DEC) && free_sha);
    end

    always_ff @( clk ) begin //yum, buffer
        if (~rst_n) begin
            text_addr <= '0;
            text_width <= '0;
            key_addr <= '0;
            opcode <= '0;
            valid <= '0;
        end else begin
            if (in_ready && valid) begin
                text_addr <= in_if.text_addr;
                text_width <= in_if.text_width;
                key_addr <= in_if.key_addr;
                opcode <= in_if.opcode;
                valid <= in_if.opcode;
            end
            if (ready && valid) begin //pass msg to accel -- IT IS THE RESPONSIBILITY OF THE TOP MODULE TO PASS IT TO THE CORRECT FSM!!!
                out_if.text_addr <= text_addr;
                out_if.text_width <= text_width;
                out_if.key_addr <= key_addr;
                out_if.opcode <= opcode;
                out_if.valid <= valid;
            end
        end
    end

endmodule