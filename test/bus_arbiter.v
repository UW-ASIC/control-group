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
    input wire bus_ready,

    output reg [7:0] data_out,
    output reg valid_out, 
    output wire aes_grant,
    output wire sha_grant,
    output wire [1:0] curr_mode_top,
    output wire [1:0] counter_top
);

localparam AES = 2'b01;
localparam SHA = 2'b10;

assign curr_mode_top = curr_mode;
assign counter_top = counter;

reg last_serviced; // RR to choose a FSM to service if both simultaneously req bus
reg [1:0] curr_mode; // 00: Inactive, 01: AES, 10: SHA
reg [1:0] counter;

always @(*) begin
    if (counter == 2'b00) begin
        if (curr_mode == AES) begin
            data_out = aes_data_in[7:0];
            valid_out = 1'b1;
        end else if (curr_mode == SHA) begin
            data_out = sha_data_in[7:0];
            valid_out = 1'b1;
        end else begin
            data_out = 8'b0; // Don't care
            valid_out = 1'b0;
        end
    end else if (counter == 2'b01) begin
        if (curr_mode == AES) begin
            data_out = aes_data_in[15:8];
            valid_out = 1'b1;
        end else if (curr_mode == SHA) begin
            data_out = sha_data_in[15:8];
            valid_out = 1'b1;
        end else begin
            data_out = 8'b0; // Don't care
            valid_out = 1'b0;
        end
    end else if (counter == 2'b10) begin
        if (curr_mode == AES) begin
            data_out = aes_data_in[23:16];
            valid_out = 1'b1;
        end else if (curr_mode == SHA) begin
            data_out = sha_data_in[23:16];
            valid_out = 1'b1;
        end else begin
            data_out = 8'b0; // Don't care
            valid_out = 1'b0;
        end
    end else begin
        if (curr_mode == AES) begin
            data_out = aes_data_in[31:24];
            valid_out = 1'b1;
        end else if (curr_mode == SHA) begin
            data_out = sha_data_in[31:24];
            valid_out = 1'b1;
        end else begin
            data_out = 8'b0; // Don't care
            valid_out = 1'b0;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        last_serviced <= 1'b0;
        curr_mode <= 2'b00;
        counter <= 2'b00;
    end else begin
        if (curr_mode != 2'b00) begin
            if (bus_ready) counter <= counter + 1;
        end else begin
            // Counter should always be 0 when curr_mode == 2'b00
            if (sha_req && aes_req) begin 
                curr_mode <= last_serviced ? 2'b10 : 2'b01;
            end else if (aes_req) begin 
                curr_mode <= 2'b01;
            end else if (sha_req) begin
                curr_mode <= 2'b10;
            end else begin
                curr_mode <= 2'b00;
                counter <= 2'b00;
            end
        end

        if (counter == 2'b11) begin
            if (curr_mode == AES) curr_mode <= (sha_req) ? SHA : 2'b00;
            else if (curr_mode == SHA) curr_mode <= (aes_req) ? AES : 2'b00;
        end

        if (curr_mode == AES) last_serviced <= 1'b1;
        else if (curr_mode == SHA) last_serviced <= 1'b0;
    end
end

assign aes_grant = (curr_mode == AES);
assign sha_grant = (curr_mode == SHA);


endmodule