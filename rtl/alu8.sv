
module alu8 (
    input  logic [7:0] a,
    input  logic [7:0] b,
    input  logic [2:0] op,
    output logic [7:0] result,
    output logic       zero,
    output logic       carry
);

    logic [8:0] temp;

    always_comb begin
        result = 8'h00;
        carry  = 1'b0;
        temp   = 9'h000;

        case (op)
            3'b000: begin // ADD
                temp   = {1'b0, a} + {1'b0, b};
                result = temp[7:0];
                carry  = temp[8];
            end

            3'b001: begin // SUB; carry means no borrow
                temp   = {1'b0, a} - {1'b0, b};
                result = temp[7:0];
                carry  = (a >= b);
            end

            3'b010: result = a & b;
            3'b011: result = a | b;
            3'b100: result = a ^ b;
            3'b101: result = a << b[2:0];
            3'b110: result = a >> b[2:0];

            default: begin
                result = 8'h00;
                carry  = 1'b0;
            end
        endcase

        zero = (result == 8'h00);
    end

endmodule
