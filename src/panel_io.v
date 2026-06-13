// ============================================================================
// panel_io.v - E/S do painel frontal via shift registers
//
//   sr595_out : cadeia de 5x 74HC595 -> 40 LEDs (16 end + 8 dados + 16 status)
//   sr165_in  : cadeia de 4x 74HC165 -> 32 chaves (16 end + 16 controle)
//   debounce  : filtro de 8 amostras a 1 kHz por chave
//
// Convencao de bits (MSB enviado/recebido primeiro):
//   LEDs  d[39:0] = {A15..A0, D7..D0, ST15..ST0}
//   Chaves q[31:0]: q[31:24]=chip1 (controles altos), q[23:16]=chip2
//                   (controles baixos), q[15:8]=A15..A8, q[7:0]=A7..A0
// ============================================================================
`default_nettype none

// ---------------------------------------------------------------- 595 (LEDs)
module sr595_out #(
    parameter NBITS = 40,
    parameter DIVW  = 6        // sclk = clk / 2^DIVW  (~422 kHz @ 27 MHz)
)(
    input  wire             clk,
    input  wire             rst,
    input  wire [NBITS-1:0] d,
    output reg              sclk,
    output reg              sdat,
    output reg              rclk
);
    reg [DIVW-1:0]      div;
    reg [NBITS-1:0]     sh;
    reg [6:0]           bitcnt;
    reg [1:0]           state;   // 0=carrega 1=dado 2=clock 3=latch

    always @(posedge clk) begin
        if (rst) begin
            div <= 0; bitcnt <= 0; state <= 0;
            sclk <= 0; sdat <= 0; rclk <= 0; sh <= 0;
        end else begin
            div <= div + 1'b1;
            if (div == 0) begin
                case (state)
                2'd0: begin                 // captura novo quadro
                    sh     <= d;
                    bitcnt <= NBITS[6:0];
                    rclk   <= 1'b0;
                    sclk   <= 1'b0;
                    state  <= 2'd1;
                end
                2'd1: begin                 // apresenta bit (MSB primeiro)
                    sdat  <= sh[NBITS-1];
                    sh    <= {sh[NBITS-2:0], 1'b0};
                    sclk  <= 1'b0;
                    state <= 2'd2;
                end
                2'd2: begin                 // borda de subida do SRCLK
                    sclk   <= 1'b1;
                    bitcnt <= bitcnt - 1'b1;
                    state  <= (bitcnt == 1) ? 2'd3 : 2'd1;
                end
                2'd3: begin                 // pulso de latch (RCLK)
                    sclk  <= 1'b0;
                    rclk  <= 1'b1;
                    state <= 2'd0;
                end
                endcase
            end
        end
    end
endmodule

// ---------------------------------------------------------------- 165 (chaves)
module sr165_in #(
    parameter NBITS = 32,
    parameter DIVW  = 6
)(
    input  wire             clk,
    input  wire             rst,
    output reg  [NBITS-1:0] q,
    output reg              sclk,    // CP
    output reg              pln,     // /PL (carga paralela, ativo baixo)
    input  wire             sdat     // QH do ultimo CI da cadeia
);
    reg [DIVW-1:0]  div;
    reg [NBITS-1:0] sh;
    reg [6:0]       bitcnt;
    reg [1:0]       state;   // 0=/PL baixo 1=amostra 2=clock 3=entrega

    always @(posedge clk) begin
        if (rst) begin
            div <= 0; state <= 0; bitcnt <= 0;
            sclk <= 0; pln <= 1'b1; q <= 0; sh <= 0;
        end else begin
            div <= div + 1'b1;
            if (div == 0) begin
                case (state)
                2'd0: begin                 // pulso de carga paralela
                    pln    <= 1'b0;
                    sclk   <= 1'b0;
                    bitcnt <= NBITS[6:0];
                    state  <= 2'd1;
                end
                2'd1: begin                 // amostra bit corrente (MSB primeiro)
                    pln   <= 1'b1;
                    sh    <= {sh[NBITS-2:0], sdat};
                    sclk  <= 1'b0;
                    state <= 2'd2;
                end
                2'd2: begin                 // CP sobe -> proximo bit no QH
                    sclk   <= 1'b1;
                    bitcnt <= bitcnt - 1'b1;
                    state  <= (bitcnt == 1) ? 2'd3 : 2'd1;
                end
                2'd3: begin                 // quadro completo
                    sclk  <= 1'b0;
                    q     <= sh;
                    state <= 2'd0;
                end
                endcase
            end
        end
    end
endmodule

// ---------------------------------------------------------------- debounce
module debounce #(
    parameter N = 32
)(
    input  wire         clk,
    input  wire         tick,    // ~1 kHz
    input  wire [N-1:0] d,
    output reg  [N-1:0] q
);
    reg [7:0] hist [0:N-1];
    integer i;

    initial begin
        q = {N{1'b0}};
        for (i = 0; i < N; i = i + 1) hist[i] = 8'h00;
    end

    always @(posedge clk) begin
        if (tick) begin
            for (i = 0; i < N; i = i + 1) begin
                hist[i] <= {hist[i][6:0], d[i]};
                if (hist[i] == 8'hFF) q[i] <= 1'b1;
                else if (hist[i] == 8'h00) q[i] <= 1'b0;
            end
        end
    end
endmodule

`default_nettype wire
