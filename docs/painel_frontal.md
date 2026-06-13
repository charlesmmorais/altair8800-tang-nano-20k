# Painel Frontal do Altair 8800 — Esquema de Montagem

Painel completo (36 LEDs + 25 chaves) ligado ao Tang Nano 20K por **6 fios**
(+3V3 e GND), usando cadeias de shift registers — todos CIs baratos da série
74HC, operando em 3,3 V.

## Lista de materiais (BOM)

| Qtd | Item | Função |
|----:|------|--------|
| 5 | 74HC595 (DIP-16) | saída serial → 40 bits de LEDs |
| 4 | 74HC165 (DIP-16) | 32 chaves → entrada serial |
| 36 | LED 3 ou 5 mm vermelho | 16 endereço + 8 dados + 12 status |
| 36 | Resistor 330 Ω | limitação de corrente dos LEDs |
| 16 | Chave alavanca ON-OFF (SPST) | endereço/dados A15..A0 |
| 9 | Chave alavanca momentânea (ON)-OFF ou (ON)-OFF-(ON) | controles |
| 25 | Resistor 10 kΩ | pull-down das chaves |
| 1 | Capacitor 100 nF por CI | desacoplamento |
| — | Fios, protoboard ou PCB, painel (acrílico/alumínio) | — |

> Nota elétrica: tudo em **3,3 V** (74HC funciona de 2 a 6 V). Com 330 Ω o
> LED consome ~4 mA — o 74HC595 aguenta com folga. Não usar 5 V em nenhum
> ponto que volte ao FPGA.

## Conexões com o Tang Nano 20K

| Sinal FPGA | Pino .cst | Vai para |
|------------|-----------|----------|
| `led_sdat` | 74 | SER (pino 14) do **595 nº 1** |
| `led_sclk` | 73 | SRCLK (11) de **todos** os 595, em paralelo |
| `led_rclk` | 75 | RCLK (12) de **todos** os 595, em paralelo |
| `sw_sdat`  | 85 | QH (9) do **165 nº 1** |
| `sw_sclk`  | 76 | CP (2) de **todos** os 165, em paralelo |
| `sw_pln`   | 80 | /PL (1) de **todos** os 165, em paralelo |
| 3V3 / GND  | — | alimentação dos CIs |

## Cadeia de LEDs — 5× 74HC595

Pinagem fixa em cada 595: /OE (13) → GND, /SRCLR (10) → 3V3,
VCC (16) → 3V3, GND (8) → GND, 100 nF entre VCC e GND.

Encadeamento: QH' (pino 9) de um CI → SER (pino 14) do próximo.

```
FPGA led_sdat ──► [595 #1] ──► [595 #2] ──► [595 #3] ──► [595 #4] ──► [595 #5]
                  STATUS L     STATUS H     DADOS        END. BAIXO   END. ALTO
                  ST7..ST0     ST15..ST8    D7..D0       A7..A0       A15..A8
```

O bit **mais significativo é enviado primeiro** (A15), por isso ele termina
no CI **mais distante** da entrada serial (chip #5).

Mapa LED → saída (Q_A = bit mais significativo de cada grupo de 8):

| CI | Q_A..Q_H |
|----|----------|
| #5 | A15 A14 A13 A12 A11 A10 A9 A8 |
| #4 | A7 A6 A5 A4 A3 A2 A1 A0 |
| #3 | D7 D6 D5 D4 D3 D2 D1 D0 |
| #2 | INTE PROT MEMR INP M1 OUT HLTA STACK |
| #1 | /WO INT WAIT HLDA — — — — |

Cada saída Q → resistor 330 Ω → ânodo do LED → cátodo no GND.

## Cadeia de chaves — 4× 74HC165

Pinagem fixa em cada 165: /CE (15) → GND, VCC (16) → 3V3, GND (8) → GND,
100 nF de desacoplamento. Encadeamento: QH (9) de um CI → DS (10) do
**anterior** na ordem de leitura.

```
FPGA sw_sdat ◄── [165 #1] ◄── [165 #2] ◄── [165 #3] ◄── [165 #4]
                 CTRL ALTO    CTRL BAIXO   A15..A8      A7..A0
```

O primeiro bit lido é D7 do chip #1. Mapa entrada paralela → função
(D7 = primeiro bit do grupo):

| CI | D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0 |
|----|----|----|----|----|----|----|----|----|
| #1 | — | — | — | **AUX1 (turbo)** | — | — | — | **RESET** |
| #2 | **DEP NEXT** | **DEPOSIT** | **EX NEXT** | **EXAMINE** | — | **STEP** | **RUN** | **STOP** |
| #3 | A15 | A14 | A13 | A12 | A11 | A10 | A9 | A8 |
| #4 | A7 | A6 | A5 | A4 | A3 | A2 | A1 | A0 |

Cada chave: um terminal no **3V3**, outro na entrada Dx **e** num resistor de
**10 kΩ para GND** (pull-down). Chave fechada = nível alto = ativa.

Para reproduzir o visual original, use chaves (ON)-OFF-(ON) momentâneas nos
pares EXAMINE/EXAMINE NEXT, DEPOSIT/DEPOSIT NEXT, RUN/STOP e STEP — cada
lado da alavanca vai a uma entrada Dx distinta.

## Layout sugerido (fiel ao original)

```
 ┌────────────────────────────────────────────────────────────────────┐
 │  INTE PROT MEMR INP  M1  OUT HLTA STACK WO  INT          WAIT HLDA │
 │   o    o    o    o   o    o    o    o   o    o            o    o   │
 │                                                                    │
 │        D7   D6   D5   D4   D3   D2   D1   D0                       │
 │         o    o    o    o    o    o    o    o                       │
 │                                                                    │
 │  A15 A14 A13 A12 A11 A10  A9  A8  A7  A6  A5  A4  A3  A2  A1  A0  │
 │   o   o   o   o   o   o   o   o   o   o   o   o   o   o   o   o   │
 │   ╫   ╫   ╫   ╫   ╫   ╫   ╫   ╫   ╫   ╫   ╫   ╫   ╫   ╫   ╫   ╫   │ ← 16 chaves
 │                                                                    │
 │  STOP  STEP  EXAMINE  DEPOSIT   RESET            AUX1              │
 │  RUN         EX NEXT  DEP NEXT                                     │
 │   ╪     ╪      ╪        ╪        ╪                ╪                │ ← momentâneas
 └────────────────────────────────────────────────────────────────────┘
```

## Operação do painel

| Ação | Efeito |
|------|--------|
| **STOP** | para a CPU na fronteira da próxima instrução (LED WAIT acende) |
| **RUN** | retoma a execução a partir do PC atual |
| **SINGLE STEP** | executa exatamente uma instrução |
| **EXAMINE** | endereço das 16 chaves → LEDs mostram o conteúdo; PC aponta para lá |
| **EXAMINE NEXT** | avança para o endereço seguinte |
| **DEPOSIT** | grava as chaves A7..A0 no endereço examinado |
| **DEPOSIT NEXT** | avança o endereço **e** grava |
| **RESET** | zera a CPU e reinicia em 0000h (funciona rodando ou parado) |
| **AUX1** | alterna entre ~1,23 MHz (original) e turbo 27 MHz |

As 8 chaves altas (A15..A8) também funcionam como **sense switches**, lidas
pelo software na porta de E/S **FFh** — exatamente como no Altair original
(é o que o *Kill the Bit* usa).
