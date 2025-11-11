`default_nettype none
module bus_arbiter #(
    parameter ADDRW = 24
    ) (
    input wire clk,
    input wire rst_n,
    input wire sha_req,
    input wire aes_req,
    input wire [ADDRW+7:0] sha_data_in,
    input wire [ADDRW+7:0] aes_data_in,

    output reg [7:0] data_out,
    output wire aes_grant,
    output wire sha_grant
);


reg last_serviced; // RR to choose a FSM to service if both simultaneously req bus
reg [1:0] curr_mode; // 00: Inactive, 01: AES, 10: SHA
reg [1:0] counter;
reg [ADDRW+7:0] data_in;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        last_serviced <= 1'b0;
        curr_mode <= 2'b00;
        counter <= 2'b00;
    end else begin
        if (curr_mode == 2'b00) begin
            if (sha_req && aes_req) begin
                if (last_serviced) begin
                    // Service SHA 
                    curr_mode <= 2'b10;
                    data_in <= sha_data_in;
                end else begin
                    // Service AES
                    curr_mode <= 2'b01;
                    data_in <= aes_data_in;
                end
            end else if (aes_req) begin 
                curr_mode <= 2'b01;
                data_in <= aes_data_in;
            end else if (sha_req) begin
                curr_mode <= 2'b10;
                data_in <= sha_data_in;
            end
            counter <= 2'b00;
        end else if (curr_mode == 2'b01) begin
            if (counter == 2'b00) begin
                data_out <= data_in[7:0];
            end else if (counter == 2'b01) begin
                data_out <= data_in[15:8];
            end else if (counter == 2'b10) begin
                data_out <= data_in[23:16];
            end else begin
                data_out <= data_in[31:24];
                if (sha_req) curr_mode <= 2'b10;
                else begin
                    curr_mode <= 2'b00;
                    last_serviced <= 1'b1;
                end
            end
            counter <= counter + 1;
        end else if (curr_mode == 2'b10) begin
            if (counter == 2'b00) begin
                data_out <= data_in[7:0];
            end else if (counter == 2'b01) begin
                data_out <= data_in[15:8];
            end else if (counter == 2'b10) begin
                data_out <= data_in[23:16];
            end else begin
                data_out <= data_in[31:24];
                last_serviced <= 1'b0;
            end
            counter <= counter + 1;
        end
    end
end

assign aes_grant = (curr_mode == 2'b01);
assign sha_grant = (curr_mode == 2'b10);


endmodule