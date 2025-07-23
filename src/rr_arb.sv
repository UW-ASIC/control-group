`default_nettype none

module moduleName #(
    parameter int N = 2 // num requestors
) (
    input clk,
    input rst_n,
    input logic [N-1:0] req,
    output logic [N-1:0] grant_OH, //One-hot representation to return to things we're arbitrating for
    output logic [$clog2(N)-1:0] grant //not-OH output for use in indexing which request to pass through 
);
/* DOCSTRING
implements a work-conserving round-robin arbiter which takes in N requests and returns both a vector of N grant signals (with a maxmimum of one being high)
and the index of the winning request.
*/
    logic [N-1:0] last_grant;

    logic [2*N-1:0] double_req; //{req,req&mask}
    logic [2*N-1:0] grant_OH2;

    function automatic logic [2*N-1:0] leftOR(input logic [2*N-1:0] in); // (0100_1100) -> (1111_1100)
        logic [2*N-1:0] out;
        logic or_accum;
        begin
            or_accum = 0;
            for (int i = 0; i < 2*N; i++) begin
                or_accum |= in[i];
                out[i] = or_accum;
            end
            return out;
        end
    endfunction

    function automatic logic [$clog2(N)-1:0] OHToUInt(input logic [N-1:0] in); // from one-hot encoding to the associated unsigned integer
        for (int i = 0; i < N; i++)
            if (in[i])
                return i[$clog2(N)-1:0];
        return 0;
    endfunction

    always_comb begin // do our actual arbitrating
        double_req = {req, req & last_grant};
        grant_OH2 = (~(leftOR(double_req) << 1) & double_req); // take the single lowest highest priority request (lowest in bit order) 

    end

    assign grant_OH = grant_OH2[2*N-1:N] | grant_OH2[N-1:0]; // collapse back down

    assign grant = OHToUInt(grant_OH);

    always_ff @(posedge clk) begin
        if (!rst_n)
            last_grant <= '0;
        else if (|grant_OH)
            last_grant <= grant_OH;
        //consider extending this for multibeat transfers to the serializer or smth to save internal wires, idk??
    end
    
endmodule