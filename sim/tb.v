// ============================================================================
// tb.v - Autoteste do nucleo i8080
//
// Executa sw/test1.hex (MVI/ADD/STA/LXI/SHLD/PUSH/POP/CALL-RET/ADI/DAA/ACI/
// DCR/JNZ/DAD/LDAX/RRC/HLT) e confere os resultados gravados em 8000h..800Ah.
// ============================================================================
`timescale 1ns/1ps

module tb;

    reg clk = 0;
    reg rst = 1;

    always #10 clk = ~clk;   // 50 MHz simulado (irrelevante)

    // CPU
    wire [15:0] addr;
    wire [7:0]  dout;
    reg  [7:0]  din;
    wire mem_rd, mem_wr, io_rd, io_wr;
    wire m1, stat_stack, hlta, inte_o, t2, boundary;
    wire [15:0] pc_out;

    i8080 dut (
        .clk(clk), .rst(rst), .ce(1'b1),
        .addr(addr), .din(din), .dout(dout),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .io_rd(io_rd), .io_wr(io_wr),
        .m1(m1), .stat_stack(stat_stack),
        .hlta(hlta), .inte_o(inte_o), .t2(t2), .boundary(boundary),
        .pc_out(pc_out),
        .pc_load(1'b0), .pc_in(16'h0000)
    );

    // RAM em negedge (mesmo protocolo do ram64k.v)
    reg [7:0] mem [0:65535];
    initial $readmemh("test1.hex", mem);

    always @(negedge clk) begin
        if (mem_wr && t2) mem[addr] <= dout;
        din <= mem[addr];
    end

    // ------------------------------------------------------------------
    integer errors;
    task check(input [15:0] a, input [7:0] exp);
        begin
            if (mem[a] !== exp) begin
                $display("FALHA  [%04Xh] = %02Xh (esperado %02Xh)",
                         a, mem[a], exp);
                errors = errors + 1;
            end else
                $display("ok     [%04Xh] = %02Xh", a, exp);
        end
    endtask

    integer cyc;
    initial begin
        errors = 0;
        repeat (4) @(posedge clk);
        rst = 0;

        // executa ate HLT (limite de seguranca)
        cyc = 0;
        while (!hlta && cyc < 100000) begin
            @(posedge clk);
            cyc = cyc + 1;
        end

        if (!hlta) begin
            $display("FALHA: HLT nao alcancado em %0d ciclos (PC=%04Xh)",
                     cyc, pc_out);
            $finish;
        end
        $display("HLT alcancado apos %0d clocks. Verificando memoria...", cyc);

        check(16'h8000, 8'h08);  // ADD
        check(16'h8001, 8'h34);  // SHLD lo
        check(16'h8002, 8'h12);  // SHLD hi
        check(16'h8003, 8'h56);  // PUSH/POP/MOV
        check(16'h8004, 8'hAA);  // CALL/RET
        check(16'h8005, 8'h00);  // ADI+DAA (99+01 -> 00, C=1)
        check(16'h8006, 8'h01);  // ACI com carry do DAA
        check(16'h8007, 8'h00);  // DCR/JNZ
        check(16'h8008, 8'h01);  // DAD (00FF+0001 -> 0100)
        check(16'h8009, 8'h05);  // LDAX B (BC=0001)
        check(16'h800A, 8'h82);  // RRC de 05h

        if (errors == 0) $display("PASS: todos os testes do nucleo 8080 ok.");
        else             $display("FAIL: %0d erro(s).", errors);
        $finish;
    end

endmodule
