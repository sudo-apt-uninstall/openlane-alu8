
module tb_alu8;

    logic [7:0] a, b;
    logic [2:0] op;
    logic [7:0] result;
    logic zero, carry;

    integer errors = 0;

    alu8 dut (
        .a(a), .b(b), .op(op),
        .result(result), .zero(zero), .carry(carry)
    );

    task automatic check(
        input logic [2:0] test_op,
        input logic [7:0] x,
        input logic [7:0] y,
        input logic [7:0] expected_result,
        input logic expected_carry
    );
        begin
            op = test_op;
            a  = x;
            b  = y;
            #1;

            if (result !== expected_result ||
                carry  !== expected_carry ||
                zero   !== (expected_result == 8'h00)) begin
                $display("FAIL op=%b a=%h b=%h result=%h carry=%b zero=%b",
                         op, a, b, result, carry, zero);
                errors = errors + 1;
            end else begin
                $display("PASS op=%b a=%h b=%h result=%h",
                         op, a, b, result);
            end
        end
    endtask

    initial begin
        check(3'b000, 8'd10,  8'd20, 8'd30, 1'b0);
        check(3'b000, 8'd250, 8'd10, 8'd4,  1'b1);
        check(3'b001, 8'd20,  8'd10, 8'd10, 1'b1);
        check(3'b001, 8'd5,   8'd10, 8'hFB, 1'b0);
        check(3'b010, 8'hF0,  8'h0F, 8'h00, 1'b0);
        check(3'b011, 8'hF0,  8'h0F, 8'hFF, 1'b0);
        check(3'b100, 8'hAA,  8'hFF, 8'h55, 1'b0);
        check(3'b101, 8'h01,  8'd3,  8'h08, 1'b0);
        check(3'b110, 8'h80,  8'd3,  8'h10, 1'b0);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d errors", errors);

        $finish;
    end

endmodule
