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

    // VCD dump for simulation
`ifndef SYNTHESIS
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, comp_queue);
    end
`endif

    // Internal FIFO
    reg [ADDRW-1:0] mem [0:QDEPTH-1];
    // Calculate index and count widths based on QDEPTH 
    // Handles edge cases like QDEPTH <= 1, force min width to be 1
    localparam integer IDXW = (QDEPTH <= 1) ? 1 : $clog2(QDEPTH);
    localparam integer COUNTW = (QDEPTH <= 1) ? 1 : $clog2(QDEPTH + 1);
    function [IDXW-1:0] idx_const;
        input integer value;
        begin
            idx_const = value[IDXW-1:0];
        end
    endfunction
    localparam [IDXW-1:0] LAST_IDX = idx_const(QDEPTH - 1);
    localparam [COUNTW-1:0] COUNT_MAX = QDEPTH;
    
    reg [IDXW-1:0] head, tail;
    reg [COUNTW-1:0] count;

    wire full  = (count == COUNT_MAX);
    wire empty = (count == {COUNTW{1'b0}}); // zero width

    // Round-robin selector: 0 = AES, 1 = SHA
    reg rr_select;
    wire both_valid = valid_in_aes && valid_in_sha;

    wire aes_sel = (both_valid && !rr_select) || (valid_in_aes && !valid_in_sha);
    wire sha_sel = (both_valid && rr_select)  || (valid_in_sha && !valid_in_aes);

    wire enq_valid = (aes_sel && valid_in_aes) || (sha_sel && valid_in_sha);
    wire [ADDRW-1:0] enq_data =
        aes_sel ? dest_addr_aes :
        sha_sel ? dest_addr_sha :
        {ADDRW{1'b0}};

    wire enq_ready = !full;

    // Ready signals reflect queue capacity
    always @(*) begin
        ready_out_aes = !full;
        ready_out_sha = !full;
    end

    wire deq_valid = !empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= {IDXW{1'b0}};
            tail <= {IDXW{1'b0}};
            count <= {COUNTW{1'b0}};
            rr_select <= 0;
            valid_out <= 0;
            data_out <= 0;
        end else begin
            // Debug output around failing cycle (simulation only)
`ifndef SYNTHESIS
            if ($time >= 2250000 && $time <= 2290000) begin
                $display("[%0t] rr_select=%0b | valid_in_aes=%b valid_in_sha=%b | aes_sel=%b sha_sel=%b | enq_valid=%b enq_ready=%b | count=%0d | tail=%0d",
                    $time, rr_select, valid_in_aes, valid_in_sha, aes_sel, sha_sel, enq_valid, enq_ready, count, tail);
            end
`endif

            // Enqueue logic
            if (enq_valid && enq_ready) begin
                mem[tail] <= enq_data;
                // avoid modulo on mixed widths to prevent WIDTHTRUNC warnings
                if (tail == LAST_IDX) tail <= {IDXW{1'b0}};
                else tail <= tail + 1;
                count <= count + 1;
            end

            // Toggle round-robin if both inputs are valid — regardless of enqueue
            if (both_valid)
                rr_select <= ~rr_select;

            // Dequeue logic
            if (deq_valid && ready_in) begin
                data_out <= mem[head];
                if (head == LAST_IDX)       // (head + 1) % QDEPTH
                    head <= {IDXW{1'b0}};
                else 
                    head <= head + 1;
                count <= count - 1;
            end

            // Update valid_out
            valid_out <= !empty;
        end
    end

endmodule
