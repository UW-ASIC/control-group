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
    // initial begin
    //     $dumpfile("tb.vcd");
    //     $dumpvars(0, comp_queue);
    // end

    // Internal FIFO
    reg [ADDRW-1:0] mem [0:QDEPTH-1];
    // Calculate index and count widths based on QDEPTH 
    // Handles edge cases like QDEPTH <= 1, force min width to be 1
    localparam integer IDXW = (QDEPTH <= 1) ? 1 : $clog2(QDEPTH);
    localparam integer COUNTW = (QDEPTH <= 1) ? 1 : $clog2(QDEPTH + 1);
    localparam [IDXW-1:0] LAST_IDX = IDXW'(QDEPTH - 1);
    localparam [COUNTW-1:0] COUNT_MAX = QDEPTH;

    function [IDXW-1:0] increment_ptr;
        input [IDXW-1:0] val;
        increment_ptr = (val == LAST_IDX) ? {IDXW{1'b0}} : val + 1'b1;
    endfunction
    
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

    wire do_enq = enq_valid && enq_ready;
    wire do_deq = valid_out && ready_in;

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
            if (do_enq) begin
                mem[tail] <= enq_data;
                tail <= increment_ptr(tail);
            end

            // Toggle round-robin if both inputs are valid — regardless of enqueue
            if (both_valid)
                rr_select <= ~rr_select;

            // Present next entry
            if (!empty && !valid_out) begin
                data_out <= mem[head];
                valid_out <= 1;
            end

            // Dequeue on handshake
            if (do_deq) begin
                head <= increment_ptr(head);
                valid_out <= 0;
            end

            // Count — handle simultaneous case explicitly
            if (do_enq && do_deq)
                count <= count;
            else if (do_enq)
                count <= count + 1;
            else if (do_deq)
                count <= count - 1;
        end
    end

endmodule
