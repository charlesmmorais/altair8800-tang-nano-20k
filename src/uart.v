// ============================================================================
// uart.v - UART 115200 8N1 @ 27 MHz + periferico estilo 88-2SIO (canal A)
//
//   Porta 0x10: status  bit0 = RDRF (dado recebido pronto)
//                       bit1 = TDRE (transmissor livre)
//   Porta 0x11: dados   leitura = RX (limpa RDRF), escrita = TX
//
// DIV = 27_000_000 / 115_200 ~= 234
// ============================================================================
`default_nettype none

// ---------------------------------------------------------------- TX
module uart_tx #(
    parameter DIV = 234
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       wr,        // pulso de 1 clk com dado em d
    input  wire [7:0] d,
    output reg        txp,
    output wire       busy
);
    reg [9:0]  sh;      // start + 8 dados + stop
    reg [3:0]  bitcnt;
    reg [15:0] baud;
    reg        active;

    assign busy = active;

    always @(posedge clk) begin
        if (rst) begin
            txp <= 1'b1; active <= 1'b0; bitcnt <= 0; baud <= 0; sh <= 10'h3FF;
        end else if (!active) begin
            txp <= 1'b1;
            if (wr) begin
                sh     <= {1'b1, d, 1'b0}; // stop, dados (LSB primeiro), start
                bitcnt <= 4'd10;
                baud   <= DIV - 1;
                active <= 1'b1;
                txp    <= 1'b0;            // start bit imediato
            end
        end else begin
            if (baud == 0) begin
                if (bitcnt == 1) begin
                    active <= 1'b0;
                    txp    <= 1'b1;
                end else begin
                    sh     <= {1'b1, sh[9:1]};
                    txp    <= sh[1];
                    bitcnt <= bitcnt - 1'b1;
                    baud   <= DIV - 1;
                end
            end else
                baud <= baud - 1'b1;
        end
    end
endmodule

// ---------------------------------------------------------------- RX
module uart_rx #(
    parameter DIV = 234
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rxp,
    output reg  [7:0] q,
    output reg        valid      // pulso de 1 clk quando byte completo
);
    reg [1:0]  sync;
    reg [15:0] baud;
    reg [3:0]  bitcnt;
    reg [7:0]  sh;
    reg        active;

    wire rxs = sync[1];

    always @(posedge clk) begin
        sync <= {sync[0], rxp};
        valid <= 1'b0;
        if (rst) begin
            active <= 1'b0; bitcnt <= 0; baud <= 0; q <= 8'h00;
        end else if (!active) begin
            if (rxs == 1'b0) begin          // borda de start
                active <= 1'b1;
                bitcnt <= 4'd0;
                baud   <= (DIV / 2) - 1;    // amostra no meio do bit
            end
        end else begin
            if (baud == 0) begin
                baud <= DIV - 1;
                if (bitcnt == 0) begin
                    if (rxs == 1'b0) bitcnt <= 4'd1;  // start valido
                    else active <= 1'b0;              // glitch
                end else if (bitcnt <= 8) begin
                    sh     <= {rxs, sh[7:1]};         // LSB primeiro
                    bitcnt <= bitcnt + 1'b1;
                end else begin                        // stop bit
                    if (rxs) begin
                        q <= sh;
                        valid <= 1'b1;
                    end
                    active <= 1'b0;
                end
            end else
                baud <= baud - 1'b1;
        end
    end
endmodule

// ---------------------------------------------------------------- 88-2SIO
module sio2 #(
    parameter DIV = 234
)(
    input  wire       clk,
    input  wire       rst,
    // barramento de E/S da CPU
    input  wire [7:0] port,      // endereco da porta
    input  wire       rd_stb,    // pulso de leitura  (porta selecionada)
    input  wire       wr_stb,    // pulso de escrita  (porta selecionada)
    input  wire [7:0] d,
    output wire [7:0] q,
    // serial fisica
    output wire       txp,
    input  wire       rxp
);
    wire       tx_busy;
    wire [7:0] rx_q;
    wire       rx_valid;

    reg  [7:0] rx_data;
    reg        rdrf;

    wire sel_data = (port[0] == 1'b1);   // 0x11
    wire [7:0] status = {6'b000000, ~tx_busy, rdrf}; // bit1=TDRE bit0=RDRF

    assign q = sel_data ? rx_data : status;

    uart_tx #(.DIV(DIV)) u_tx (
        .clk(clk), .rst(rst),
        .wr(wr_stb && sel_data), .d(d),
        .txp(txp), .busy(tx_busy)
    );

    uart_rx #(.DIV(DIV)) u_rx (
        .clk(clk), .rst(rst), .rxp(rxp),
        .q(rx_q), .valid(rx_valid)
    );

    always @(posedge clk) begin
        if (rst) begin
            rdrf <= 1'b0; rx_data <= 8'h00;
        end else begin
            if (rx_valid) begin
                rx_data <= rx_q;
                rdrf    <= 1'b1;
            end
            if (rd_stb && sel_data)
                rdrf <= 1'b0;
        end
    end
endmodule

`default_nettype wire
