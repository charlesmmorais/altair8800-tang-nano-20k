// ============================================================================
// i8080.v - Nucleo Intel 8080 completo (todos os opcodes documentados,
//           nao-documentados tratados como no silicio original)
//
// Microarquitetura:
//   - 2 clocks por ciclo de maquina: phase 0 = lanca tarefa de barramento,
//     phase 1 = consome dado (din) e "retira" o ciclo.
//   - mc = contador de ciclos de maquina da instrucao corrente (0..4).
//   - RAM externa amostra em negedge clk (ver ram64k.v), garantindo que o
//     dado lido esteja estavel no posedge de phase 1.
//   - Sem interrupcoes (INTE apenas para o LED do painel, EI/DI funcionam).
//   - pc_load/pc_in: o painel frontal forca o PC quando a CPU esta parada
//     (tambem tira a CPU de HLT).
//
// Projeto: Altair 8800 para Tang Nano 20K
// ============================================================================
`default_nettype none

module i8080 (
    input  wire        clk,
    input  wire        rst,        // sincrono, ativo alto
    input  wire        ce,         // clock-enable (divisor de velocidade)

    output reg  [15:0] addr,
    input  wire [7:0]  din,
    output reg  [7:0]  dout,

    output reg         mem_rd,
    output reg         mem_wr,
    output reg         io_rd,
    output reg         io_wr,

    output reg         m1,         // ciclo de busca de opcode
    output reg         stat_stack, // acesso via SP (LED STACK)
    output wire        hlta,       // CPU em HALT (LED HLTA)
    output wire        inte_o,     // flip-flop de interrupcao (LED INTE)
    output wire        t2,         // 1 durante a metade ativa do ciclo
    output wire        boundary,   // 1 = fronteira de instrucao (parada segura)
    output wire [15:0] pc_out,

    input  wire        pc_load,    // painel: carrega PC (e sai de HLT)
    input  wire [15:0] pc_in
);

    // ------------------------------------------------------------------
    // Registradores
    // ------------------------------------------------------------------
    // RF[0]=B RF[1]=C RF[2]=D RF[3]=E RF[4]=H RF[5]=L RF[6]=(nao usado) RF[7]=A
    reg [7:0]  RF [0:7];
    reg [15:0] PC, SP;
    reg [7:0]  W, Z;            // par temporario interno (enderecos/imediatos)
    reg [7:0]  IR;              // registrador de instrucao
    reg        fS, fZ, fA, fP, fC;
    reg        INTE;
    reg        HALT_r;
    reg        phase;           // 0 = lanca ciclo, 1 = retira ciclo
    reg [2:0]  mc;              // ciclo de maquina corrente

    assign hlta     = HALT_r;
    assign inte_o   = INTE;
    assign t2       = phase;
    assign boundary = (mc == 3'd0) && (phase == 1'b0) && !HALT_r;
    assign pc_out   = PC;

    // ------------------------------------------------------------------
    // Auxiliares combinacionais (lidos dentro do always)
    // ------------------------------------------------------------------
    wire [15:0] HL = {RF[4], RF[5]};
    wire [15:0] BC = {RF[0], RF[1]};
    wire [15:0] DE = {RF[2], RF[3]};
    wire [7:0]  PSW = {fS, fZ, 1'b0, fA, 1'b0, fP, 1'b1, fC};

    // variaveis temporarias (uso exclusivamente com atribuicao blocking)
    reg [8:0]  tsum;
    reg [4:0]  tlo;
    reg [7:0]  tr, badj, b2;
    reg        cin, tcy;
    reg [15:0] trp;
    reg [16:0] t17;

    // ------------------------------------------------------------------
    // Tarefas de barramento (atribuicoes blocking sobre regs de saida)
    // ------------------------------------------------------------------
    task t_clear; begin
        mem_rd = 1'b0; mem_wr = 1'b0; io_rd = 1'b0; io_wr = 1'b0;
        m1 = 1'b0; stat_stack = 1'b0;
    end endtask

    task t_fetch; begin
        addr = PC; PC = PC + 16'd1; mem_rd = 1'b1; m1 = 1'b1;
    end endtask

    task t_rd(input [15:0] a); begin
        addr = a; mem_rd = 1'b1;
    end endtask

    task t_rd_pc; begin
        addr = PC; PC = PC + 16'd1; mem_rd = 1'b1;
    end endtask

    task t_wr(input [15:0] a, input [7:0] d); begin
        addr = a; dout = d; mem_wr = 1'b1;
    end endtask

    task t_inp(input [7:0] p); begin
        addr = {p, p}; io_rd = 1'b1;
    end endtask

    task t_out(input [7:0] p, input [7:0] d); begin
        addr = {p, p}; dout = d; io_wr = 1'b1;
    end endtask

    // ------------------------------------------------------------------
    // Operacoes de registrador-par (rp = IR[5:4]: BC, DE, HL, SP)
    // ------------------------------------------------------------------
    task get_rp(output [15:0] v); begin
        case (IR[5:4])
            2'd0: v = BC;
            2'd1: v = DE;
            2'd2: v = HL;
            2'd3: v = SP;
        endcase
    end endtask

    task set_rp(input [15:0] v); begin
        case (IR[5:4])
            2'd0: begin RF[0] = v[15:8]; RF[1] = v[7:0]; end
            2'd1: begin RF[2] = v[15:8]; RF[3] = v[7:0]; end
            2'd2: begin RF[4] = v[15:8]; RF[5] = v[7:0]; end
            2'd3: SP = v;
        endcase
    end endtask

    // byte alto/baixo para PUSH (rp=3 -> PSW)
    task push_hi(output [7:0] v); begin
        case (IR[5:4])
            2'd0: v = RF[0]; 2'd1: v = RF[2]; 2'd2: v = RF[4]; 2'd3: v = RF[7];
        endcase
    end endtask

    task push_lo(output [7:0] v); begin
        case (IR[5:4])
            2'd0: v = RF[1]; 2'd1: v = RF[3]; 2'd2: v = RF[5]; 2'd3: v = PSW;
        endcase
    end endtask

    // ------------------------------------------------------------------
    // Flags S/Z/P a partir de um resultado
    // ------------------------------------------------------------------
    task set_szp(input [7:0] r); begin
        fS = r[7]; fZ = (r == 8'h00); fP = ~^r;
    end endtask

    // ------------------------------------------------------------------
    // ALU principal: op = IR[5:3] (ADD ADC SUB SBB ANA XRA ORA CMP)
    // ------------------------------------------------------------------
    task alu_op(input [2:0] op, input [7:0] b);
    begin
        case (op)
            3'd0, 3'd1, 3'd2, 3'd3, 3'd7: begin // ADD/ADC/SUB/SBB/CMP
                case (op)
                    3'd0: begin b2 = b;  cin = 1'b0; end // ADD
                    3'd1: begin b2 = b;  cin = fC;   end // ADC
                    3'd2: begin b2 = ~b; cin = 1'b1; end // SUB
                    3'd3: begin b2 = ~b; cin = ~fC;  end // SBB
                    default: begin b2 = ~b; cin = 1'b1; end // CMP (= SUB)
                endcase
                tsum = {1'b0, RF[7]} + {1'b0, b2} + {8'b0, cin};
                tlo  = {1'b0, RF[7][3:0]} + {1'b0, b2[3:0]} + {4'b0, cin};
                fA   = tlo[4];
                fC   = (op == 3'd0 || op == 3'd1) ? tsum[8] : ~tsum[8];
                tr   = tsum[7:0];
                set_szp(tr);
                if (op != 3'd7) RF[7] = tr;   // CMP nao grava A
            end
            3'd4: begin // ANA
                tr = RF[7] & b; fC = 1'b0; fA = RF[7][3] | b[3];
                set_szp(tr); RF[7] = tr;
            end
            3'd5: begin // XRA
                tr = RF[7] ^ b; fC = 1'b0; fA = 1'b0;
                set_szp(tr); RF[7] = tr;
            end
            default: begin // ORA
                tr = RF[7] | b; fC = 1'b0; fA = 1'b0;
                set_szp(tr); RF[7] = tr;
            end
        endcase
    end
    endtask

    // INR/DCR (nao afetam fC)
    task do_inr(input [7:0] v, output [7:0] r); begin
        r = v + 8'd1; fA = (r[3:0] == 4'h0); set_szp(r);
    end endtask

    task do_dcr(input [7:0] v, output [7:0] r); begin
        r = v - 8'd1; fA = ~(r[3:0] == 4'hF); set_szp(r);
    end endtask

    // Avaliacao de condicao: IR[5:3] = NZ Z NC C PO PE P M
    task cond_ok(output ok); begin
        case (IR[5:3])
            3'd0: ok = ~fZ;  3'd1: ok = fZ;
            3'd2: ok = ~fC;  3'd3: ok = fC;
            3'd4: ok = ~fP;  3'd5: ok = fP;
            3'd6: ok = ~fS;  default: ok = fS;
        endcase
    end endtask

    reg ok_c;

    // ------------------------------------------------------------------
    // FSM principal
    // ------------------------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            PC = 16'h0000; SP = 16'h0000;
            for (i = 0; i < 8; i = i + 1) RF[i] = 8'h00;
            W = 8'h00; Z = 8'h00; IR = 8'h00;
            fS = 0; fZ = 0; fA = 0; fP = 0; fC = 0;
            INTE = 1'b0; HALT_r = 1'b0;
            phase = 1'b0; mc = 3'd0;
            addr = 16'h0000; dout = 8'h00;
            t_clear;
        end else if (pc_load) begin
            // painel frontal: forca PC, sai de HLT, reinicia na fronteira
            PC = pc_in; HALT_r = 1'b0; phase = 1'b0; mc = 3'd0;
            t_clear;
        end else if (ce && !HALT_r) begin
            if (phase == 1'b0) begin
                // ====================== LANCAMENTO DO CICLO ======================
                t_clear;
                case (mc)
                3'd0: t_fetch;
                3'd1: casez (IR)
                    8'b01???110: t_rd(HL);                      // MOV r,M
                    8'b01110???: t_wr(HL, RF[IR[2:0]]);         // MOV M,r
                    8'b10???110: t_rd(HL);                      // ALU M
                    8'b00110110: t_rd_pc;                       // MVI M,d8
                    8'b00???110: t_rd_pc;                       // MVI r,d8
                    8'b00110100: t_rd(HL);                      // INR M
                    8'b00110101: t_rd(HL);                      // DCR M
                    8'b00??0001: t_rd_pc;                       // LXI rp (lo)
                    8'b000?0010: t_wr(IR[4] ? DE : BC, RF[7]);  // STAX
                    8'b000?1010: t_rd(IR[4] ? DE : BC);         // LDAX
                    8'h22, 8'h2A, 8'h32, 8'h3A: t_rd_pc;        // SHLD/LHLD/STA/LDA lo
                    8'hDB, 8'hD3: t_rd_pc;                      // IN/OUT (porta)
                    8'hE3: begin t_rd(SP); stat_stack = 1'b1; end // XTHL rd lo
                    8'b1100?011: t_rd_pc;                       // JMP (C3/CB) lo
                    8'b11??1101: t_rd_pc;                       // CALL lo
                    8'b110?1001: begin t_rd(SP); stat_stack = 1'b1; end // RET lo
                    8'b11???010: t_rd_pc;                       // Jcc lo
                    8'b11???100: t_rd_pc;                       // Ccc lo
                    8'b11???000: begin t_rd(SP); stat_stack = 1'b1; end // Rcc lo
                    8'b11??0001: begin t_rd(SP); stat_stack = 1'b1; end // POP lo
                    8'b11??0101: begin                          // PUSH hi
                        push_hi(tr); t_wr(SP - 16'd1, tr); stat_stack = 1'b1;
                    end
                    8'b11???111: begin                          // RST push PCH
                        t_wr(SP - 16'd1, PC[15:8]); stat_stack = 1'b1;
                    end
                    8'b11???110: t_rd_pc;                       // ALU imediato
                    default: t_fetch;                           // (nao alcanca)
                endcase
                3'd2: casez (IR)
                    8'b00??0001: t_rd_pc;                       // LXI hi
                    8'b00110110: t_wr(HL, Z);                   // MVI M grava
                    8'b00110100, 8'b00110101: t_wr(HL, Z);      // INR/DCR M grava
                    8'h22, 8'h2A, 8'h32, 8'h3A: t_rd_pc;        // hi do endereco
                    8'hDB: t_inp(Z);                            // IN porta
                    8'hD3: t_out(Z, RF[7]);                     // OUT porta
                    8'hE3: begin t_rd(SP + 16'd1); stat_stack = 1'b1; end
                    8'b1100?011: t_rd_pc;                       // JMP hi
                    8'b11??1101: t_rd_pc;                       // CALL hi
                    8'b110?1001: begin t_rd(SP + 16'd1); stat_stack = 1'b1; end
                    8'b11???010: t_rd_pc;                       // Jcc hi
                    8'b11???100: t_rd_pc;                       // Ccc hi
                    8'b11???000: begin t_rd(SP + 16'd1); stat_stack = 1'b1; end
                    8'b11??0001: begin t_rd(SP + 16'd1); stat_stack = 1'b1; end
                    8'b11??0101: begin                          // PUSH lo
                        push_lo(tr); t_wr(SP - 16'd2, tr); stat_stack = 1'b1;
                    end
                    8'b11???111: begin                          // RST push PCL
                        t_wr(SP - 16'd2, PC[7:0]); stat_stack = 1'b1;
                    end
                    default: t_fetch;
                endcase
                3'd3: casez (IR)
                    8'h32: t_wr({W, Z}, RF[7]);                 // STA
                    8'h3A: t_rd({W, Z});                        // LDA
                    8'h22: t_wr({W, Z}, RF[5]);                 // SHLD (L)
                    8'h2A: t_rd({W, Z});                        // LHLD (L)
                    8'hE3: begin t_wr(SP + 16'd1, RF[4]); stat_stack = 1'b1; end
                    8'b11??1101, 8'b11???100: begin             // CALL/Ccc push PCH
                        t_wr(SP - 16'd1, PC[15:8]); stat_stack = 1'b1;
                    end
                    default: t_fetch;
                endcase
                default: casez (IR) // mc4
                    8'h22: t_wr({W, Z} + 16'd1, RF[4]);         // SHLD (H)
                    8'h2A: t_rd({W, Z} + 16'd1);                // LHLD (H)
                    8'hE3: begin t_wr(SP, RF[5]); stat_stack = 1'b1; end
                    8'b11??1101, 8'b11???100: begin             // CALL/Ccc push PCL
                        t_wr(SP - 16'd2, PC[7:0]); stat_stack = 1'b1;
                    end
                    default: t_fetch;
                endcase
                endcase
                phase = 1'b1;
            end else begin
                // ====================== RETIRADA DO CICLO ======================
                phase = 1'b0;
                case (mc)
                // ---------------------------------------------------- mc0
                3'd0: begin
                    IR = din;
                    mc = 3'd0; // padrao: instrucao de 1 ciclo
                    casez (IR)
                    8'h76: HALT_r = 1'b1;                       // HLT
                    // --- rotacoes / especiais (00???111) ---
                    8'h07: begin fC = RF[7][7]; RF[7] = {RF[7][6:0], RF[7][7]}; end // RLC
                    8'h0F: begin fC = RF[7][0]; RF[7] = {RF[7][0], RF[7][7:1]}; end // RRC
                    8'h17: begin tcy = fC; fC = RF[7][7]; RF[7] = {RF[7][6:0], tcy}; end // RAL
                    8'h1F: begin tcy = fC; fC = RF[7][0]; RF[7] = {tcy, RF[7][7:1]}; end // RAR
                    8'h27: begin                                // DAA
                        badj = 8'h00; tcy = fC;
                        if (fA || (RF[7][3:0] > 4'h9)) badj[3:0] = 4'h6;
                        if (fC || (RF[7][7:4] > 4'h9) ||
                            ((RF[7][7:4] == 4'h9) && (RF[7][3:0] > 4'h9))) begin
                            badj[7:4] = 4'h6; tcy = 1'b1;
                        end
                        tlo = {1'b0, RF[7][3:0]} + {1'b0, badj[3:0]};
                        fA  = tlo[4];
                        RF[7] = RF[7] + badj;
                        fC  = tcy;
                        set_szp(RF[7]);
                    end
                    8'h2F: RF[7] = ~RF[7];                      // CMA
                    8'h37: fC = 1'b1;                           // STC
                    8'h3F: fC = ~fC;                            // CMC
                    // --- enderecamento direto / IO / trocas ---
                    8'h22, 8'h2A, 8'h32, 8'h3A: mc = 3'd1;      // SHLD/LHLD/STA/LDA
                    8'hDB, 8'hD3: mc = 3'd1;                    // IN/OUT
                    8'hEB: begin                                // XCHG
                        tr = RF[2]; RF[2] = RF[4]; RF[4] = tr;
                        tr = RF[3]; RF[3] = RF[5]; RF[5] = tr;
                    end
                    8'hE3: mc = 3'd1;                           // XTHL
                    8'hF9: SP = HL;                             // SPHL
                    8'hE9: PC = HL;                             // PCHL
                    8'hFB: INTE = 1'b1;                         // EI
                    8'hF3: INTE = 1'b0;                         // DI
                    // --- saltos/chamadas/retornos ---
                    8'b1100?011: mc = 3'd1;                     // JMP
                    8'b11??1101: mc = 3'd1;                     // CALL
                    8'b110?1001: mc = 3'd1;                     // RET
                    8'b11???010: mc = 3'd1;                     // Jcc
                    8'b11???100: mc = 3'd1;                     // Ccc
                    8'b11???000: begin                          // Rcc
                        cond_ok(ok_c);
                        if (ok_c) mc = 3'd1;
                    end
                    8'b11??0001: mc = 3'd1;                     // POP
                    8'b11??0101: mc = 3'd1;                     // PUSH
                    8'b11???111: mc = 3'd1;                     // RST
                    8'b11???110: mc = 3'd1;                     // ALU imediato
                    // --- bloco 01: MOV / HLT ja tratado ---
                    8'b01???110: mc = 3'd1;                     // MOV r,M
                    8'b01110???: mc = 3'd1;                     // MOV M,r
                    8'b01??????: RF[IR[5:3]] = RF[IR[2:0]];     // MOV r,r
                    // --- bloco 10: ALU registrador ---
                    8'b10???110: mc = 3'd1;                     // ALU M
                    8'b10??????: alu_op(IR[5:3], RF[IR[2:0]]);  // ALU r
                    // --- bloco 00 ---
                    8'b00110110: mc = 3'd1;                     // MVI M,d8
                    8'b00???110: mc = 3'd1;                     // MVI r,d8
                    8'b00110100: mc = 3'd1;                     // INR M
                    8'b00110101: mc = 3'd1;                     // DCR M
                    8'b00???100: do_inr(RF[IR[5:3]], RF[IR[5:3]]); // INR r
                    8'b00???101: do_dcr(RF[IR[5:3]], RF[IR[5:3]]); // DCR r
                    8'b00??0001: mc = 3'd1;                     // LXI rp
                    8'b00??1001: begin                          // DAD rp
                        get_rp(trp);
                        t17 = {1'b0, HL} + {1'b0, trp};
                        fC = t17[16];
                        RF[4] = t17[15:8]; RF[5] = t17[7:0];
                    end
                    8'b00??0011: begin get_rp(trp); set_rp(trp + 16'd1); end // INX
                    8'b00??1011: begin get_rp(trp); set_rp(trp - 16'd1); end // DCX
                    8'b000?0010: mc = 3'd1;                     // STAX
                    8'b000?1010: mc = 3'd1;                     // LDAX
                    8'b00???000: ;                              // NOP (e nao-doc.)
                    default: ;                                  // NOP
                    endcase
                end
                // ---------------------------------------------------- mc1
                3'd1: begin
                    mc = 3'd0;
                    casez (IR)
                    8'b01???110: RF[IR[5:3]] = din;             // MOV r,M
                    8'b01110???: ;                              // MOV M,r (feito)
                    8'b10???110: alu_op(IR[5:3], din);          // ALU M
                    8'b00110110: begin Z = din; mc = 3'd2; end  // MVI M,d8
                    8'b00???110: RF[IR[5:3]] = din;             // MVI r,d8
                    8'b00110100: begin do_inr(din, Z); mc = 3'd2; end // INR M
                    8'b00110101: begin do_dcr(din, Z); mc = 3'd2; end // DCR M
                    8'b00??0001: begin                          // LXI lo
                        case (IR[5:4])
                            2'd0: RF[1] = din; 2'd1: RF[3] = din;
                            2'd2: RF[5] = din; 2'd3: SP[7:0] = din;
                        endcase
                        mc = 3'd2;
                    end
                    8'b000?0010: ;                              // STAX (feito)
                    8'b000?1010: RF[7] = din;                   // LDAX
                    8'h22, 8'h2A, 8'h32, 8'h3A: begin Z = din; mc = 3'd2; end
                    8'hDB, 8'hD3: begin Z = din; mc = 3'd2; end // porta
                    8'hE3: begin Z = din; mc = 3'd2; end        // XTHL lo
                    8'b1100?011: begin Z = din; mc = 3'd2; end  // JMP lo
                    8'b11??1101: begin Z = din; mc = 3'd2; end  // CALL lo
                    8'b110?1001: begin Z = din; mc = 3'd2; end  // RET lo
                    8'b11???010: begin Z = din; mc = 3'd2; end  // Jcc lo
                    8'b11???100: begin Z = din; mc = 3'd2; end  // Ccc lo
                    8'b11???000: begin Z = din; mc = 3'd2; end  // Rcc lo
                    8'b11??0001: begin                          // POP lo
                        case (IR[5:4])
                            2'd0: RF[1] = din; 2'd1: RF[3] = din;
                            2'd2: RF[5] = din;
                            2'd3: begin
                                fS = din[7]; fZ = din[6]; fA = din[4];
                                fP = din[2]; fC = din[0];
                            end
                        endcase
                        mc = 3'd2;
                    end
                    8'b11??0101: mc = 3'd2;                     // PUSH
                    8'b11???111: mc = 3'd2;                     // RST
                    8'b11???110: alu_op(IR[5:3], din);          // ALU imediato
                    default: ;
                    endcase
                end
                // ---------------------------------------------------- mc2
                3'd2: begin
                    mc = 3'd0;
                    casez (IR)
                    8'b00??0001: begin                          // LXI hi
                        case (IR[5:4])
                            2'd0: RF[0] = din; 2'd1: RF[2] = din;
                            2'd2: RF[4] = din; 2'd3: SP[15:8] = din;
                        endcase
                    end
                    8'b00110110: ;                              // MVI M (gravado)
                    8'b00110100, 8'b00110101: ;                 // INR/DCR M (gravado)
                    8'h22, 8'h2A, 8'h32, 8'h3A: begin W = din; mc = 3'd3; end
                    8'hDB: RF[7] = din;                         // IN
                    8'hD3: ;                                    // OUT (feito)
                    8'hE3: begin W = din; mc = 3'd3; end        // XTHL hi
                    8'b1100?011: PC = {din, Z};                 // JMP
                    8'b11??1101: begin W = din; mc = 3'd3; end  // CALL hi
                    8'b110?1001: begin PC = {din, Z}; SP = SP + 16'd2; end // RET
                    8'b11???010: begin                          // Jcc
                        cond_ok(ok_c);
                        if (ok_c) PC = {din, Z};
                    end
                    8'b11???100: begin                          // Ccc
                        W = din;
                        cond_ok(ok_c);
                        if (ok_c) mc = 3'd3;
                    end
                    8'b11???000: begin PC = {din, Z}; SP = SP + 16'd2; end // Rcc
                    8'b11??0001: begin                          // POP hi
                        case (IR[5:4])
                            2'd0: RF[0] = din; 2'd1: RF[2] = din;
                            2'd2: RF[4] = din; 2'd3: RF[7] = din;
                        endcase
                        SP = SP + 16'd2;
                    end
                    8'b11??0101: SP = SP - 16'd2;               // PUSH
                    8'b11???111: begin                          // RST
                        SP = SP - 16'd2;
                        PC = {10'b0, IR[5:3], 3'b000};
                    end
                    default: ;
                    endcase
                end
                // ---------------------------------------------------- mc3
                3'd3: begin
                    mc = 3'd0;
                    casez (IR)
                    8'h32: ;                                    // STA (gravado)
                    8'h3A: RF[7] = din;                         // LDA
                    8'h22: mc = 3'd4;                           // SHLD
                    8'h2A: begin RF[5] = din; mc = 3'd4; end    // LHLD (L)
                    8'hE3: mc = 3'd4;                           // XTHL
                    8'b11??1101, 8'b11???100: mc = 3'd4;        // CALL/Ccc
                    default: ;
                    endcase
                end
                // ---------------------------------------------------- mc4
                default: begin
                    mc = 3'd0;
                    casez (IR)
                    8'h22: ;                                    // SHLD (gravado)
                    8'h2A: RF[4] = din;                         // LHLD (H)
                    8'hE3: begin RF[4] = W; RF[5] = Z; end      // XTHL
                    8'b11??1101, 8'b11???100: begin             // CALL/Ccc
                        SP = SP - 16'd2;
                        PC = {W, Z};
                    end
                    default: ;
                    endcase
                end
                endcase
            end
        end
    end

endmodule

`default_nettype wire
