# Manual de montagem do painel frontal

Construção física do painel (36 LEDs + 25 chaves) e ligação à Tang Nano
20K com apenas **6 fios de sinal** + alimentação. Complementa o esquema
elétrico em [painel_frontal.md](painel_frontal.md).

## Sumário

1. [Lista de materiais](#1-lista-de-materiais)
2. [Ferramentas](#2-ferramentas)
3. [Como funciona (2 minutos de teoria)](#3-como-funciona-2-minutos-de-teoria)
4. [Etapa 1 — protótipo mínimo na protoboard](#4-etapa-1--protótipo-mínimo-na-protoboard)
5. [Etapa 2 — placa dos LEDs (5× 74HC595)](#5-etapa-2--placa-dos-leds-5-74hc595)
6. [Etapa 3 — placa das chaves (4× 74HC165)](#6-etapa-3--placa-das-chaves-4-74hc165)
7. [Etapa 4 — cabo para a Tang Nano 20K](#7-etapa-4--cabo-para-a-tang-nano-20k)
8. [Etapa 5 — painel mecânico](#8-etapa-5--painel-mecânico)
9. [Checklist antes de energizar](#9-checklist-antes-de-energizar)
10. [Testes de bring-up](#10-testes-de-bring-up)
11. [Solução de problemas](#11-solução-de-problemas)

---

## 1. Lista de materiais

| Qtd | Item | Função | Obs. |
|----:|------|--------|------|
| 5 | 74HC595N (DIP-16) | LEDs | série **HC**, não LS |
| 4 | 74HC165N (DIP-16) | chaves | idem |
| 9 | Soquete DIP-16 | manutenção | recomendado |
| 36 | LED 5 mm vermelho difuso | indicadores | difuso fica mais fiel |
| 36 | Resistor 330 Ω 1/4 W | série dos LEDs | ~4 mA por LED em 3,3 V |
| 16 | Chave alavanca SPST ON-OFF | endereço A15..A0 | |
| 5 | Chave alavanca (ON)-OFF-(ON) momentânea | STOP/RUN, STEP, EXAMINE/EX NEXT, DEPOSIT/DEP NEXT, RESET/AUX1 | ou 9 chaves momentâneas simples |
| 25 | Resistor 10 kΩ 1/4 W | pull-down das chaves | um por contato usado |
| 9 | Capacitor cerâmico 100 nF | desacoplamento | um junto a cada CI |
| 1 | Capacitor eletrolítico 10–47 µF | filtro da alimentação | na entrada do 3V3 |
| 2 | Placa perfurada/ilhada ~10×15 cm | LEDs e chaves | ou PCB própria |
| 1 | Cabo flat 8 vias, 30–50 cm | painel ↔ FPGA | + conectores Dupont |
| — | Fio wire-wrap ou AWG28-30, estanho, espaguete | fiação | |
| 1 | Painel: chapa de acrílico/alumínio/MDF ~45×20 cm | frente | |

> **Por que 74HC e não 74LS ou 74HCT?** A série HC funciona de 2 a 6 V —
> perfeita nos 3,3 V do FPGA. LS exige 5 V e devolveria níveis perigosos
> para os pinos do GW2AR. **Nada de 5 V em ponto algum do painel.**

## 2. Ferramentas

Ferro de solda 25–40 W ponta fina, estanho 0,5–0,8 mm, sugador ou malha,
alicate de corte, descascador, **multímetro** (indispensável para o
checklist), furadeira com brocas de 5 mm (LEDs) e 6–12 mm (chaves,
conforme o modelo).

## 3. Como funciona (2 minutos de teoria)

O FPGA não tem 70 pinos sobrando para LEDs e chaves, então usamos
*shift registers*:

- **Saída (LEDs)**: o FPGA envia 40 bits em série pelo fio `SDAT`,
  cadenciados por `SRCLK`. Os bits atravessam os cinco 74HC595
  encadeados (a saída `QH'` de um alimenta a entrada `SER` do próximo).
  Quando os 40 bits estão posicionados, um pulso em `RCLK` transfere tudo
  para as saídas de uma vez — os LEDs atualizam sem piscar. Isso se
  repete ~6.500 vezes por segundo.
- **Entrada (chaves)**: um pulso baixo em `/PL` fotografa as 32 chaves
  dentro dos quatro 74HC165; em seguida o FPGA puxa os 32 bits em série
  pelo fio `QH`, cadenciados por `CP`. O firmware ainda aplica *debounce*
  de 8 ms em cada chave.

A **ordem dos bits** importa: o primeiro bit que o FPGA envia é o **A15**
(por isso ele acaba no CI mais distante da cadeia de LEDs), e o primeiro
bit que ele lê é o **D7 do CI #1** das chaves. As tabelas das etapas 5 e 6
já estão nessa ordem — basta segui-las.

## 4. Etapa 1 — protótipo mínimo na protoboard

Antes de soldar 36 LEDs, valide o conceito com **1 CI de cada**:

1. Monte um 74HC595 na protoboard: VCC(16)→3V3, GND(8)→GND, /OE(13)→GND,
   /SRCLR(10)→3V3, 100 nF no VCC. Ligue 8 LEDs+330 Ω nas saídas QA..QH.
2. Ligue ao FPGA: SER(14)→pino 74, SRCLK(11)→pino 73, RCLK(12)→pino 75.
3. Grave o bitstream e dê o boot: você verá o byte de **status** do
   Altair (este CI sozinho recebe os últimos 8 bits do quadro = ST7..ST0;
   o LED do /WO deve acender fixo e o M1 piscar).
4. Repita com um 74HC165: /PL(1)→pino 80, CP(2)→pino 76, QH(9)→pino 85,
   /CE(15)→GND, DS(10)→GND. Ligue **uma** chave com pull-down no D0:
   com a CPU em STOP* essa chave é o **STOP**... mas com 1 CI só a cadeia
   fica deslocada — então para o protótipo apenas confira no multímetro
   que `/PL` e `CP` pulsam (≈0,5–1,6 V de média) e que mexer a chave não
   trava nada.
5. Funcionou? Desmonte e parta para as placas definitivas.

## 5. Etapa 2 — placa dos LEDs (5× 74HC595)

### 5.1 Ligações comuns a TODOS os 595

| Pino | Nome | Liga em |
|-----:|------|---------|
| 16 | VCC | 3V3 |
| 8 | GND | GND |
| 13 | /OE | **GND** (saídas sempre ativas) |
| 10 | /SRCLR | **3V3** (nunca limpa) |
| 11 | SRCLK | barramento `led_sclk` (todos juntos) |
| 12 | RCLK | barramento `led_rclk` (todos juntos) |
| — | 100 nF | entre 16 e 8, colado no CI |

### 5.2 Encadeamento (ordem física da serial)

```
FPGA pino 74 ─► SER #1 │ QH'#1 ─► SER #2 │ QH'#2 ─► SER #3 │ QH'#3 ─► SER #4 │ QH'#4 ─► SER #5 │ QH'#5: livre
                (status L)        (status H)        (dados)           (A7..A0)          (A15..A8)
```

SER = pino 14, QH' = pino 9.

### 5.3 Mapa LED por LED

Cada saída → resistor 330 Ω → **ânodo** do LED → **cátodo** no GND.
(QA=pino 15, QB=1, QC=2, QD=3, QE=4, QF=5, QG=6, QH=7.)

| CI | QA | QB | QC | QD | QE | QF | QG | QH |
|----|----|----|----|----|----|----|----|----|
| **#1** status L | /WO | INT | WAIT | HLDA | — | — | — | — |
| **#2** status H | INTE | PROT | MEMR | INP | M1 | OUT | HLTA | STACK |
| **#3** dados | D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0 |
| **#4** end. baixo | A7 | A6 | A5 | A4 | A3 | A2 | A1 | A0 |
| **#5** end. alto | A15 | A14 | A13 | A12 | A11 | A10 | A9 | A8 |

As 4 saídas livres do CI #1 ficam sem conexão.

**Dica de montagem**: solde os 5 soquetes em linha, com os barramentos
SRCLK/RCLK/3V3/GND passando por baixo em fio nu, e os resistores em pé ao
lado de cada CI. Os LEDs ficam no painel e chegam por fios — deixe 15 cm
de folga.

## 6. Etapa 3 — placa das chaves (4× 74HC165)

### 6.1 Ligações comuns a TODOS os 165

| Pino | Nome | Liga em |
|-----:|------|---------|
| 16 | VCC | 3V3 |
| 8 | GND | GND |
| 15 | /CE | **GND** (sempre habilitado) |
| 1 | /PL | barramento `sw_pln` (todos juntos) |
| 2 | CP | barramento `sw_sclk` (todos juntos) |
| 7 | /QH | livre |
| — | 100 nF | entre 16 e 8 |

### 6.2 Encadeamento

```
FPGA pino 85 ◄─ QH #1 │ DS#1 ◄─ QH #2 │ DS#2 ◄─ QH #3 │ DS#3 ◄─ QH #4 │ DS#4 ─► GND
                (controles A)    (controles B)    (A15..A8)        (A7..A0)
```

QH = pino 9, DS = pino 10. Note o sentido: o dado **flui na direção do
FPGA** — o DS de cada CI recebe o QH do **seguinte**.

### 6.3 Cada chave

```
3V3 ──○ ╱ ○──┬──► entrada Dx do CI
              └──[10 kΩ]──► GND
```

Chave **fechada = nível alto = ativa**. O pull-down de 10 kΩ é
obrigatório em cada entrada usada; entradas Dx não usadas vão direto ao
GND (sem resistor).

### 6.4 Mapa chave por chave

Pinos das entradas: D0=11, D1=12, D2=13, D3=14, D4=3, D5=4, D6=5, D7=6.

| CI | D0 | D1 | D2 | D3 | D4 | D5 | D6 | D7 |
|----|----|----|----|----|----|----|----|----|
| **#1** controles A | **RESET** | — | — | — | **AUX1** (turbo) | — | — | — |
| **#2** controles B | **STOP** | **RUN** | **STEP** | — | **EXAMINE** | **EX NEXT** | **DEPOSIT** | **DEP NEXT** |
| **#3** end. alto | A8 | A9 | A10 | A11 | A12 | A13 | A14 | A15 |
| **#4** end. baixo | A0 | A1 | A2 | A3 | A4 | A5 | A6 | A7 |

> **Chaves de alavanca dupla (ON)-OFF-(ON)**: para o visual original,
> use uma alavanca por par de funções — para cima = primeira função,
> para baixo = segunda. Cada lado é um contato independente: comum no
> 3V3, cada contato vai à sua entrada Dx **com seu próprio 10 kΩ**:
> STOP/RUN, EXAMINE/EX NEXT, DEPOSIT/DEP NEXT, RESET/AUX1, e STEP
> (só um lado usado).

## 7. Etapa 4 — cabo para a Tang Nano 20K

8 vias entre as placas e o FPGA:

| Via | Sinal | Pino FPGA | Vai para |
|-----|-------|-----------|----------|
| 1 | `led_sdat` | **74** | SER do 595 #1 |
| 2 | `led_sclk` | **73** | SRCLK de todos os 595 |
| 3 | `led_rclk` | **75** | RCLK de todos os 595 |
| 4 | `sw_sdat` | **85** | QH do 165 #1 |
| 5 | `sw_sclk` | **76** | CP de todos os 165 |
| 6 | `sw_pln` | **80** | /PL de todos os 165 |
| 7 | 3V3 | pino 3V3 da placa | VCC dos CIs, chaves |
| 8 | GND | GND da placa | GND comum |

Regras do cabo:

- Até **50 cm** com fio comum funciona bem (clock de ~422 kHz).
- Acima disso, ou se aparecer instabilidade: resistor série de **100 Ω**
  em `led_sclk`, `led_rclk` e `sw_sclk` (na ponta do FPGA) e intercale o
  GND entre os sinais no cabo flat.
- **Antes de soldar, confirme os pinos 73/74/75/76/80/85 no esquemático
  da revisão da sua placa** (conector de expansão). Se algum estiver
  ocupado na sua revisão, troque a atribuição no
  `constraints/tang_nano_20k.cst` e ressintetize — qualquer pino de E/S
  livre serve.
- A alimentação 3V3 da Tang Nano aguenta o painel com folga: pior caso
  ≈ 150 mA (todos os 36 LEDs acesos + lógica).

## 8. Etapa 5 — painel mecânico

1. Imprima um gabarito em escala (o layout clássico está em
   [painel_frontal.md](painel_frontal.md)): linha de status no topo,
   dados abaixo, endereço no meio, as 16 chaves de endereço sob os LEDs
   de endereço e as alavancas de comando na base.
2. Fure: 5 mm para os LEDs, 6–12 mm para as chaves (meça as suas).
3. Encaixe os LEDs (anel de travamento ou cola quente por trás) e
   parafuse as chaves.
4. Cabeamento até as placas: agrupe os fios por CI (8 LEDs ou 8 chaves
   por grupo) — facilita demais o teste e a manutenção.
5. Acabamento clássico: fundo azul, faixa branca com a serigrafia
   "ALTAIR 8800" e as legendas das chaves.

## 9. Checklist antes de energizar

Com o multímetro, **placa desligada**:

- [ ] Continuidade 3V3 ↔ pino 16 de cada um dos 9 CIs
- [ ] Continuidade GND ↔ pino 8 de cada CI
- [ ] **Sem curto** entre 3V3 e GND (resistência > 1 kΩ)
- [ ] /OE de cada 595 (pino 13) no GND; /SRCLR (pino 10) no 3V3
- [ ] /CE de cada 165 (pino 15) no GND
- [ ] Cadeia 595: QH'(9) do #1 → SER(14) do #2 ... até o #5
- [ ] Cadeia 165: QH(9) do #2 → DS(10) do #1 ... DS do #4 no GND
- [ ] Cada entrada Dx usada: ~10 kΩ para o GND (chave aberta)
- [ ] Cada entrada Dx usada: ~0 Ω para o 3V3 com a chave fechada
- [ ] LEDs: polaridade (perna longa/ânodo no resistor, cátodo no GND)
- [ ] Nenhum fio do cabo trocado (campainha ponta a ponta nas 8 vias)

## 10. Testes de bring-up

Faça **nesta ordem** — cada teste depende do anterior:

1. **Só a placa, sem painel** — grave o bitstream: LEDs onboard piscando
   (Kill the Bit). Isso prova que FPGA + RAM + CPU estão ok.
2. **Conecte só a placa de LEDs** — ao ligar: LEDs de endereço varrendo
   (a CPU percorrendo o laço), **/WO** aceso, **M1** tremulando, D7..D0
   com um bit circulando. Se tudo estiver deslocado de 8 em 8 posições,
   um CI da cadeia está fora de ordem.
3. **Conecte a placa de chaves** — sequência de validação:
   - **STOP** → LED **WAIT** acende, endereço congela;
   - chaves A15..A0 em `0000h` + **EXAMINE** → LEDs de endereço `0000h`,
     dados mostram `21h` (primeiro byte do Kill the Bit);
   - **EXAMINE NEXT** → endereço `0001h`, dados `00h`;
   - A7..A0 = `76h` (HLT) + **DEPOSIT** → dados mudam para `76h`;
   - **RESET** e o programa volta a rodar... e para em HLT no `0001h`
     que você acabou de depositar — LED **HLTA** acende. Funcionou tudo!
   - **RESET**, **STOP**, EXAMINE `0001h`, DEPOSIT `00h` de volta (NOP),
     **RESET**: Kill the Bit rodando de novo.
4. **Sense switches** — com o jogo rodando, feche uma chave entre A15 e
   A8: o bit correspondente "morre" quando colide. É o Kill the Bit
   funcionando como em 1975.
5. **Turbo** — **AUX1**: o bit passa a girar rápido demais para jogar
   (27 MHz). AUX1 de novo volta ao normal.

## 11. Solução de problemas

| Sintoma | Verificar |
|---------|-----------|
| Nenhum LED acende | 3V3/GND nas placas; RCLK chegando (multímetro: tensão média ~0,1–0,5 V = pulsos) |
| LEDs todos acesos fracos | /OE solto (pino 13 deve estar no GND) |
| Padrão deslocado em blocos de 8 | Ordem dos CIs na cadeia trocada (ver 5.2) |
| Padrão "espelhado" dentro de um grupo | LEDs ligados de QH→QA em vez de QA→QH |
| LEDs piscam aleatório | SRCLK/RCLK trocados entre si, ou SDAT em CI errado |
| Um LED nunca acende | Polaridade do LED ou resistor frio |
| Nenhuma chave funciona | /PL e CP trocados; QH do #1 não chega ao pino 85 |
| Chaves trocadas entre grupos | Ordem dos 165 na cadeia (ver 6.2) |
| Uma chave sempre "apertada" | Pull-down ausente/aberto naquela entrada |
| Chave dispara 2× | Mau contato mecânico (o debounce de 8 ms já cobre o normal) |
| Funciona na bancada, falha com cabo longo | Resistores série de 100 Ω nos clocks + GND junto dos sinais |

---

*Anterior: [compilacao_e_gravacao.md](compilacao_e_gravacao.md) ·
Esquema elétrico: [painel_frontal.md](painel_frontal.md)*
