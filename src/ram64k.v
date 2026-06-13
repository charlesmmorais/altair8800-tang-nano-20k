// ============================================================================
// ram64k.v - RAM 64KB sincrona em negedge clk
//
// A CPU lanca endereco/strobe no posedge (phase 0); a RAM amostra no negedge
// seguinte; o dado lido esta estavel no posedge de phase 1 (retirada).
// Infere BSRAM no Gowin EDA. Conteudo inicial via boot.hex ($readmemh).
// ============================================================================
`default_nettype none

module ram64k (
    input  wire        clk,
    input  wire        we,
    input  wire [15:0] addr,
    input  wire [7:0]  d,
    output reg  [7:0]  q
);

    reg [7:0] mem [0:65535];

    initial $readmemh("boot.hex", mem);

    always @(negedge clk) begin
        if (we) mem[addr] <= d;
        q <= mem[addr];
    end

endmodule

`default_nettype wire
