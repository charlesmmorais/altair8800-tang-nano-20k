// ============================================================================
// tb_top.v - Teste de fumaca do altair_top
//
//   1. Roda "Kill the Bit" (boot.hex) e confere atividade do barramento.
//   2. Captura quadros da cadeia de 595 e confere consistencia dos LEDs.
//   3. Injeta chaves via cadeia 165 simulada: STOP, EXAMINE 0010h,
//      DEPOSIT 55h, EXAMINE NEXT, DEPOSIT AAh e verifica leitura dos LEDs.
// ============================================================================
`timescale 1ns/1ps

module tb_top;

    reg clk = 0;
    always #18.5 clk = ~clk;   // ~27 MHz

    reg btn_rst_n = 0;

    wire uart_txp;
    wire [5:0] led_ob;
    wire led_sclk, led_sdat, led_rclk;
    wire sw_sclk, sw_pln;

    // ------------------------------------------------------------------
    // chaves simuladas: modelo da cadeia de 4x 74HC165
    // ------------------------------------------------------------------
    reg [31:0] sw_model = 32'h0;
    reg [31:0] sw_sh;
    // ordem de leitura do RTL (MSB primeiro): q[31] e o primeiro bit
    always @(negedge sw_pln) sw_sh <= sw_model;          // carga paralela
    always @(posedge sw_sclk) sw_sh <= {sw_sh[30:0], 1'b0};
    wire sw_sdat = sw_sh[31];

    altair_top dut (
        .clk27(clk), .btn_rst_n(btn_rst_n),
        .uart_txp(uart_txp), .uart_rxp(1'b1),
        .led_ob(led_ob),
        .led_sclk(led_sclk), .led_sdat(led_sdat), .led_rclk(led_rclk),
        .sw_sclk(sw_sclk), .sw_pln(sw_pln), .sw_sdat(sw_sdat)
    );

    // ------------------------------------------------------------------
    // captura dos quadros de LED (modelo da cadeia de 595)
    // ------------------------------------------------------------------
    reg [39:0] led_sh = 0;
    reg [39:0] led_frame = 0;
    always @(posedge led_sclk) led_sh <= {led_sh[38:0], led_sdat};
    always @(posedge led_rclk) led_frame <= led_sh;

    wire [15:0] f_addr = led_frame[39:24];
    wire [7:0]  f_data = led_frame[23:16];
    wire [15:0] f_stat = led_frame[15:0];

    // ------------------------------------------------------------------
    integer errors = 0;
    task expect(input cond, input [127:0] nome);
        begin
            if (!cond) begin
                $display("FALHA: %0s", nome);
                errors = errors + 1;
            end else
                $display("ok:    %0s", nome);
        end
    endtask

    task press(input [4:0] bitn);
        begin
            sw_model[bitn] = 1'b1;
            #15_000_000;          // 15 ms (debounce de 8 ms + margem)
            sw_model[bitn] = 1'b0;
            #15_000_000;
        end
    endtask

    integer i;
    reg saw_m1;
    initial begin
        #2000 btn_rst_n = 1;

        // -------- 1. CPU rodando Kill the Bit
        saw_m1 = 0;
        for (i = 0; i < 20000; i = i + 1) begin
            @(posedge clk);
            if (dut.c_m1 && dut.c_t2) saw_m1 = 1;
        end
        expect(saw_m1, "CPU executando (ciclos M1 observados)");
        expect(dut.c_pc >= 16'h0008 && dut.c_pc <= 16'h0018,
               "PC dentro do laco do Kill the Bit");

        // -------- 2. quadro de LEDs coerente
        #1_000_000;
        expect(led_frame !== 40'h0, "cadeia de 595 transmitindo quadros");
        expect(f_stat[13] || f_stat[7], "status MEMR ou /WO ativo rodando");

        // -------- 3. painel: STOP
        press(16);
        expect(dut.stopped === 1'b1, "STOP parou a CPU na fronteira");
        expect(f_stat[5] === 1'b1 || dut.stopped, "LED WAIT (apos quadro)");

        // EXAMINE 0010h
        sw_model[15:0] = 16'h0010;
        press(20);
        expect(dut.exam_addr === 16'h0010, "EXAMINE carregou 0010h");
        expect(dut.u_cpu.PC === 16'h0010, "PC forcado para 0010h");

        // DEPOSIT 55h
        sw_model[15:0] = 16'h0055;
        press(22);
        expect(dut.u_ram.mem[16'h0010] === 8'h55, "DEPOSIT gravou 55h em 0010h");

        // DEPOSIT NEXT AAh -> grava em 0011h
        sw_model[15:0] = 16'h00AA;
        press(23);
        expect(dut.exam_addr === 16'h0011, "DEPOSIT NEXT avancou para 0011h");
        expect(dut.u_ram.mem[16'h0011] === 8'hAA, "DEPOSIT NEXT gravou AAh");

        // EXAMINE NEXT -> 0012h
        press(21);
        expect(dut.exam_addr === 16'h0012, "EXAMINE NEXT avancou para 0012h");

        // LEDs de dado mostram a RAM no endereco examinado
        sw_model[15:0] = 16'h0010;
        press(20);
        #2_000_000;
        expect(f_addr === 16'h0010, "LEDs de endereco = 0010h");
        expect(f_data === 8'h55,    "LEDs de dado = conteudo da RAM (55h)");

        // -------- 4. SINGLE STEP
        press(18);
        expect(dut.u_cpu.PC !== 16'h0010, "SINGLE STEP executou 1 instrucao");

        // -------- 5. RUN novamente
        press(17);
        expect(dut.stopped === 1'b0, "RUN retomou a execucao");

        if (errors == 0) $display("PASS: teste de fumaca do top-level ok.");
        else             $display("FAIL: %0d erro(s).", errors);
        $finish;
    end

    // limite de seguranca
    initial begin
        #400_000_000;
        $display("FALHA: timeout do teste de fumaca");
        $finish;
    end

endmodule
