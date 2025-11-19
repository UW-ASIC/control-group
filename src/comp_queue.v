module comp_queue #(
    parameter ADDRW  = 24,
    parameter QDEPTH = 32
)(
    input  wire clk,
    input  wire rst_n,

    input  wire                 valid_in_aes,
    input  wire                 valid_in_sha,
    input  wire [ADDRW-1:0]     dest_addr_aes,
    input  wire [ADDRW-1:0]     dest_addr_sha,
    output reg                  ready_out_aes,
    output reg                  ready_out_sha,

    output reg [ADDRW-1:0]      data_out,
    output reg                  valid_out,
    input  wire                 ready_in
);

    initial begin
        integer i;
        $dumpfile("tb.vcd");
        for (i = 0; i < QDEPTH; i = i + 1) $dumpvars(0, queue[i]);
        for (i = 0; i < QDEPTH; i = i + 1) $dumpvars(0, shaQueue[i]);
    end

    reg [ADDRW-1:0] mem [0:QDEPTH-1];
    reg [$clog2(QDEPTH)-1:0] head, tail;
    reg [$clog2(QDEPTH+1)-1:0] count;

    wire full  = (count == QDEPTH);
    wire empty = (count == 0);

    reg rr_select; // 0: Service AES, 1: Service SHA
    wire both_valid = valid_in_aes && valid_in_sha;
    wire aes_sel    = (both_valid && !rr_select) || (valid_in_aes && !valid_in_sha);
    wire sha_sel    = (both_valid && rr_select)  || (valid_in_sha && !valid_in_aes);

    wire enq_valid = (aes_sel && valid_in_aes) || (sha_sel && valid_in_sha);
    wire [ADDRW-1:0] enq_data =
        aes_sel ? dest_addr_aes :
        sha_sel ? dest_addr_sha :
        {ADDRW{1'b0}};

    wire enq_ready = !full;

    always @(*) begin
        ready_out_aes = enq_ready && aes_sel;
        ready_out_sha = enq_ready && sha_sel;
    end

    wire deq_valid = !empty;
    wire deq_ready = ready_in && valid_out;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= 0;
            tail <= 0;
            count <= 0;
            rr_select <= 0;
            valid_out <= 0;
            data_out <= 0;
        end else begin
            if (enq_valid && enq_ready) begin
                mem[tail] <= enq_data;
                tail <= (tail + 1) % QDEPTH;
                count <= count + 1;

                if (both_valid)
                    rr_select <= ~rr_select;
            end

            if (deq_valid && ready_in) begin
                data_out <= mem[head];
                head <= (head + 1) % QDEPTH;
                count <= count - 1;
            end

            valid_out <= !empty;
        end
    end

endmodule
