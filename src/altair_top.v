// ============================================================================
// altair_top.v - Altair 8800 para Tang Nano 20K
//
//   - CPU i8080 @ ~1,23 MHz (27 MHz / 22), proximo dos 2 MHz originais o
//     suficiente para "Kill the Bit"; AUX1 alterna modo turbo (27 MHz).
//   - RAM 64KB em BSRAM, carregada de boot.hex na configuracao.
//   - 88-2SIO nas portas 0x10/0x11 -> UART USB da placa (115200 8N1).
//   - Sense switches (A15..A8) lidas na porta 0xFF, como no original.
//   - Painel frontal: 40 LEDs via 5x 74HC595, 32 chaves via 4x 74HC165.
//
// Chaves (apos debounce):
//   sw[15:0]  = chaves de endereco/dados A15..A0
//   sw[16] STOP        sw[17] RUN        sw[18] SINGLE STEP
//   sw[20] EXAMINE     sw[21] EXAMINE NEXT
//   sw[22] DEPOSIT     sw[23] DEPOSIT NEXT
//   sw[24] RESET       sw[28] AUX1 (turbo)
// ============================================================================
`default_nettype none

module altair_top (
    input  wire clk27,        // 27 MHz onboard
    input  wire btn_rst_n,    // S1 (ativo baixo)

    output wire uart_txp,
    input  wire uart_rxp,

    output wire [5:0] led_ob, // LEDs onboard (ativo baixo)

    // painel frontal
    output wire led_sclk,
    output wire led_sdat,
    output wire led_rclk,
    output wire sw_sclk,
    output wire sw_pln,
    input  wire sw_sdat
);

    // ------------------------------------------------------------------
    // Reset sincrono
    // ------------------------------------------------------------------
    reg [3:0] rst_sync = 4'hF;
    always @(posedge clk27)
        rst_sync <= {rst_sync[2:0], ~btn_rst_n};
    wire rst_btn = rst_sync[3];

    reg cpu_rst_r = 1'b1;     // reset da CPU (botao, painel ou power-on)
    wire rst_sys = rst_btn;

    // ------------------------------------------------------------------
    // Clock-enable: 27 MHz / 22 ~= 1,23 MHz; turbo = sem divisao
    // ------------------------------------------------------------------
    reg  [4:0] cediv = 5'd0;
    reg        turbo = 1'b0;
    always @(posedge clk27)
        cediv <= (cediv == 5'd21) ? 5'd0 : cediv + 5'd1;
    wire ce_slow = (cediv == 5'd0);
    wire cpu_ce  = turbo ? 1'b1 : ce_slow;

    // ------------------------------------------------------------------
    // CPU
    // ------------------------------------------------------------------
    wire [15:0] c_addr;
    wire [7:0]  c_dout;
    reg  [7:0]  c_din;
    wire        c_mrd, c_mwr, c_ior, c_iow;
    wire        c_m1, c_stack, c_hlta, c_inte, c_t2, c_bound;
    wire [15:0] c_pc;

    reg         pc_ld   = 1'b0;
    reg  [15:0] pc_in_r = 16'h0000;
    reg         stopped = 1'b0;      // 0 = RUN apos configuracao (autorun)
    reg         stepping = 1'b0;
    reg         stop_req = 1'b0;

    wire cpu_run_ce = cpu_ce && (!stopped || stepping);

    i8080 u_cpu (
        .clk(clk27), .rst(cpu_rst_r), .ce(cpu_run_ce),
        .addr(c_addr), .din(c_din), .dout(c_dout),
        .mem_rd(c_mrd), .mem_wr(c_mwr), .io_rd(c_ior), .io_wr(c_iow),
        .m1(c_m1), .stat_stack(c_stack),
        .hlta(c_hlta), .inte_o(c_inte), .t2(c_t2), .boundary(c_bound),
        .pc_out(c_pc),
        .pc_load(pc_ld), .pc_in(pc_in_r)
    );

    // ------------------------------------------------------------------
    // Chaves do painel
    // ------------------------------------------------------------------
    wire [31:0] sw_raw;
    wire [31:0] sw;

    sr165_in #(.NBITS(32)) u_sw (
        .clk(clk27), .rst(rst_sys),
        .q(sw_raw),
        .sclk(sw_sclk), .pln(sw_pln), .sdat(sw_sdat)
    );

    // tick ~1 kHz para o debounce
    reg [14:0] tickdiv = 15'd0;
    wire tick1k = (tickdiv == 15'd0);
    always @(posedge clk27)
        tickdiv <= (tickdiv == 15'd26999) ? 15'd0 : tickdiv + 15'd1;

    debounce #(.N(32)) u_db (
        .clk(clk27), .tick(tick1k), .d(sw_raw), .q(sw)
    );

    // bordas de subida das chaves de controle
    reg [31:0] sw_d = 32'h0;
    always @(posedge clk27) sw_d <= sw;
    wire [31:0] sw_pe = sw & ~sw_d;

    wire pe_stop    = sw_pe[16];
    wire pe_run     = sw_pe[17];
    wire pe_step    = sw_pe[18];
    wire pe_exam    = sw_pe[20];
    wire pe_examnx  = sw_pe[21];
    wire pe_dep     = sw_pe[22];
    wire pe_depnx   = sw_pe[23];
    wire pe_reset   = sw_pe[24];
    wire pe_aux1    = sw_pe[28];

    // ------------------------------------------------------------------
    // FSM do painel
    // ------------------------------------------------------------------
    reg  [15:0] exam_addr = 16'h0000;
    reg         pnl_we    = 1'b0;
    reg         dep_pend  = 1'b0;
    reg         pend_sync = 1'b0;   // carrega PC um ciclo depois (evita corrida)
    reg  [2:0]  rst_cnt   = 3'd7;   // reset de power-on estendido

    always @(posedge clk27) begin
        pc_ld  <= 1'b0;
        pnl_we <= 1'b0;

        // reset: botao S1, chave RESET do painel, ou power-on
        if (rst_btn || pe_reset) begin
            cpu_rst_r <= 1'b1;
            rst_cnt   <= 3'd7;
            exam_addr <= 16'h0000;
            stopped   <= 1'b0;     // autorun a partir de 0x0000
            stepping  <= 1'b0;
            stop_req  <= 1'b0;
            dep_pend  <= 1'b0;
            pend_sync <= 1'b0;
            if (pe_reset) turbo <= turbo; // turbo preservado
        end else if (rst_cnt != 3'd0) begin
            rst_cnt   <= rst_cnt - 3'd1;
            cpu_rst_r <= 1'b1;
        end else begin
            cpu_rst_r <= 1'b0;

            if (pe_aux1) turbo <= ~turbo;

            // ---------------- STOP: para na fronteira de instrucao
            if (pe_stop) stop_req <= 1'b1;
            if (stop_req && (c_bound || c_hlta)) begin
                stopped  <= 1'b1;
                stop_req <= 1'b0;
            end

            // ---------------- RUN
            if (pe_run && stopped) begin
                stopped  <= 1'b0;
                stepping <= 1'b0;
            end

            // ---------------- SINGLE STEP: executa 1 instrucao
            if (pe_step && stopped && !stepping)
                stepping <= 1'b1;
            if (stepping && !c_bound && !c_hlta)
                ; // saiu da fronteira: instrucao em andamento
            if (stepping && c_t2)            // marcou que realmente avancou
                ;
            // fim do passo: voltou a fronteira (ou parou em HLT)
            if (stepping && step_left && (c_bound || c_hlta))
                stepping <= 1'b0;

            // ---------------- EXAMINE / EXAMINE NEXT
            if (stopped && pe_exam) begin
                exam_addr <= sw[15:0];
                pend_sync <= 1'b1;
            end
            if (stopped && pe_examnx) begin
                exam_addr <= exam_addr + 16'd1;
                pend_sync <= 1'b1;
            end

            // ---------------- DEPOSIT / DEPOSIT NEXT
            if (stopped && pe_dep) begin
                pnl_we    <= 1'b1;
                pend_sync <= 1'b1;
            end
            if (stopped && pe_depnx) begin
                exam_addr <= exam_addr + 16'd1;
                dep_pend  <= 1'b1;
            end
            if (dep_pend) begin
                dep_pend  <= 1'b0;
                pnl_we    <= 1'b1;
                pend_sync <= 1'b1;
            end

            // PC acompanha o endereco examinado (semantica do painel original)
            if (pend_sync && !pnl_we && !dep_pend) begin
                pend_sync <= 1'b0;
                pc_in_r   <= exam_addr;
                pc_ld     <= 1'b1;
            end
        end
    end

    // rastreio de saida da fronteira durante SINGLE STEP
    reg step_left = 1'b0;
    always @(posedge clk27) begin
        if (!stepping)            step_left <= 1'b0;
        else if (!c_bound)        step_left <= 1'b1;
    end

    // ------------------------------------------------------------------
    // RAM 64KB + mux painel/CPU
    // ------------------------------------------------------------------
    wire [15:0] ram_addr = stopped ? exam_addr : c_addr;
    wire [7:0]  ram_d    = stopped ? sw[7:0]   : c_dout;
    wire        ram_we   = stopped ? pnl_we    : (c_mwr && c_t2);
    wire [7:0]  ram_q;

    ram64k u_ram (
        .clk(clk27), .we(ram_we),
        .addr(ram_addr), .d(ram_d), .q(ram_q)
    );

    // ------------------------------------------------------------------
    // E/S: 88-2SIO (0x10/0x11) e sense switches (0xFF)
    // ------------------------------------------------------------------
    wire [7:0] port    = c_addr[7:0];
    wire       sio_sel = (port[7:1] == 7'b0001000);   // 0x10-0x11
    wire       sns_sel = (port == 8'hFF);

    wire io_rd_stb = c_ior && c_t2 && cpu_run_ce && sio_sel;
    wire io_wr_stb = c_iow && c_t2 && cpu_run_ce && sio_sel;

    wire [7:0] sio_q;

    sio2 #(.DIV(234)) u_sio (
        .clk(clk27), .rst(rst_sys),
        .port(port), .rd_stb(io_rd_stb), .wr_stb(io_wr_stb),
        .d(c_dout), .q(sio_q),
        .txp(uart_txp), .rxp(uart_rxp)
    );

    // mux de entrada da CPU
    always @(*) begin
        if (c_ior) begin
            if (sio_sel)      c_din = sio_q;
            else if (sns_sel) c_din = sw[15:8];   // sense switches A15..A8
            else              c_din = 8'hFF;
        end else
            c_din = ram_q;
    end

    // ------------------------------------------------------------------
    // LEDs do painel: {A15..A0, D7..D0, ST15..ST0}
    // ------------------------------------------------------------------
    wire [15:0] led_a = stopped ? exam_addr : c_addr;
    wire [7:0]  led_d = stopped ? ram_q
                                : ((c_mwr || c_iow) ? c_dout : c_din);

    wire [15:0] led_st;
    assign led_st[15] = c_inte;                       // INTE
    assign led_st[14] = 1'b0;                         // PROT
    assign led_st[13] = stopped ? 1'b1 : c_mrd;       // MEMR
    assign led_st[12] = c_ior;                        // INP
    assign led_st[11] = c_m1;                         // M1
    assign led_st[10] = c_iow;                        // OUT
    assign led_st[9]  = c_hlta;                       // HLTA
    assign led_st[8]  = c_stack;                      // STACK
    assign led_st[7]  = ~c_mwr;                       // /WO
    assign led_st[6]  = 1'b0;                         // INT
    assign led_st[5]  = stopped | c_hlta;             // WAIT
    assign led_st[4]  = stopped;                      // HLDA
    assign led_st[3:0] = 4'b0000;

    sr595_out #(.NBITS(40)) u_led (
        .clk(clk27), .rst(rst_sys),
        .d({led_a, led_d, led_st}),
        .sclk(led_sclk), .sdat(led_sdat), .rclk(led_rclk)
    );

    // LEDs onboard espelham D7..D2 (ativo baixo)
    assign led_ob = ~led_d[7:2];

endmodule

`default_nettype wire
