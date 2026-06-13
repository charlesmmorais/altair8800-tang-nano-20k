# Manual de compilação e gravação — Tang Nano 20K

Este guia leva do código-fonte ao Altair rodando na placa, passo a passo.
Tempo estimado: 30–45 min na primeira vez (incluindo instalação das
ferramentas).

## Sumário

1. [O que você precisa](#1-o-que-você-precisa)
2. [Instalando o Gowin EDA](#2-instalando-o-gowin-eda)
3. [Criando o projeto](#3-criando-o-projeto)
4. [Adicionando os arquivos](#4-adicionando-os-arquivos)
5. [O boot.hex (passo crítico)](#5-o-boothex-passo-crítico)
6. [Síntese e Place & Route](#6-síntese-e-place--route)
7. [Gravando na placa](#7-gravando-na-placa)
8. [Primeiro teste](#8-primeiro-teste)
9. [Carregando outros programas](#9-carregando-outros-programas)
10. [Solução de problemas](#10-solução-de-problemas)

---

## 1. O que você precisa

| Item | Observação |
|------|------------|
| Sipeed Tang Nano 20K | FPGA Gowin **GW2AR-LV18QN88C8/I7** |
| Cabo USB-C | de **dados** (não só carga) |
| Gowin EDA | Standard ou Education (gratuita) — v1.9.9 ou superior |
| openFPGALoader | opcional, alternativa livre para gravar |
| Python 3 | só para gerar/converter o `boot.hex` |
| Terminal serial | PuTTY, Tera Term, `minicom`, `picocom`... |

> A simulação com Icarus Verilog é opcional — o projeto já vem testado
> (núcleo: 11/11; sistema: 16/16; serial: PASS).

## 2. Instalando o Gowin EDA

1. Acesse o site da Gowin Semiconductor → **Developer Zone → EDA**.
2. Baixe a versão **Education** (não exige licença e suporta o GW2AR-18)
   ou a **Standard** (exige licença gratuita, solicitada no próprio site
   informando o MAC da sua máquina — chega por e-mail em 1–2 dias).
3. Instale normalmente:
   - **Windows**: executável, próximo-próximo-concluir.
   - **Linux**: extraia o `.tar.gz` (ex.: em `~/gowin`) e rode `IDE/bin/gw_ide`.
     Pode ser necessário `sudo apt install libfreetype6 libfontconfig1`.
4. Abra o IDE uma vez para confirmar que ele lista a família **GW2AR** em
   *New Project* (se não listar, a versão é antiga demais — atualize).

> **Linux + USB**: para o programmer enxergar a placa sem `sudo`, crie a
> regra udev (ver [seção 7.2](#72-alternativa-openfpgaloader), o
> openFPGALoader traz o arquivo pronto).

## 3. Criando o projeto

1. **File → New → FPGA Design Project**, nome sugerido: `altair8800`.
2. Na seleção de dispositivo, filtre e escolha **exatamente**:

   ```
   Família : GW2AR
   Device  : GW2AR-18 C8/I7
   Package : QFN88 (QN88)
   Part No : GW2AR-LV18QN88C8/I7
   ```

   > Esse part number está serigrafado no chip da Tang Nano 20K. Se
   > escolher outro speed grade ou package, o `.cst` não vai casar com os
   > pinos e o P&R falha.

3. Conclua o assistente. O Gowin cria a pasta do projeto com `impl/` dentro.

## 4. Adicionando os arquivos

1. Clique com o direito em **src** (painel Design) → *Add Files...* e
   adicione os 5 fontes Verilog:

   ```
   src/i8080.v
   src/ram64k.v
   src/uart.v
   src/panel_io.v
   src/altair_top.v
   ```

2. Adicione também o arquivo de constraints físicos:

   ```
   constraints/tang_nano_20k.cst
   ```

3. Defina o top module: **Project → Configuration → Synthesize →
   Top Module/Entity** = `altair_top` (em geral o Gowin detecta sozinho;
   confirme).

4. Ainda em *Project → Configuration*:
   - **Synthesize → Verilog Language**: `Verilog 2001` (ou System Verilog,
     ambos funcionam);
   - **Place & Route → Dual-Purpose Pin**: marque **"Use DONE as regular
     IO"** e **"Use MSPI as regular IO"** apenas se o P&R reclamar de pinos
     reservados (com o `.cst` deste projeto normalmente não é necessário).

## 5. O boot.hex (passo crítico)

A RAM de 64 KB é inicializada na configuração do FPGA pelo `$readmemh`
do `ram64k.v`:

```verilog
initial $readmemh("boot.hex", mem);
```

O Gowin resolve esse caminho **relativo ao diretório de implementação**,
que varia conforme a versão. Para não errar, faça uma destas duas opções:

**Opção A — copiar para os lugares prováveis (simples):**

```bash
cp sw/boot.hex <pasta_do_projeto>/
cp sw/boot.hex <pasta_do_projeto>/impl/
```

**Opção B — caminho absoluto (à prova de falhas):**

Edite a linha do `ram64k.v` apontando direto para o arquivo:

```verilog
initial $readmemh("C:/projetos/altair8800/sw/boot.hex", mem);  // Windows
initial $readmemh("/home/charles/altair/sw/boot.hex", mem);    // Linux
```

> **Como saber se deu errado**: a síntese conclui sem erro, mas a RAM
> sintetiza zerada (opcode `00` = NOP em tudo) e a placa liga "morta",
> com os LEDs de endereço contando sem parar. Veja também o log da
> síntese: o Gowin emite um *warning* de "file not found" fácil de passar
> despercebido.

O repositório já traz o `sw/boot.hex` com o **Kill the Bit**. Para gerar
de novo ou trocar o programa, veja a [seção 9](#9-carregando-outros-programas).

## 6. Síntese e Place & Route

1. Na aba **Process**, dê duplo-clique em **Synthesize**.
   Resultado esperado: 0 erros. Warnings de "signal has no load" em alguns
   bits de status são normais.
2. Duplo-clique em **Place & Route**.
3. Confira o relatório (`impl/pnr/*.rpt`):
   - **BSRAM**: ~32 blocos (64 KB) — toda a RAM do Altair em block RAM;
   - **Logic**: < 10 % do chip;
   - **Timing**: o design fecha folgado a 27 MHz (caminho crítico é a ALU
     do 8080, bem abaixo do limite).

Ao final, o bitstream fica em:

```
impl/pnr/altair8800.fs
```

## 7. Gravando na placa

### 7.1 Pelo Gowin Programmer

1. Conecte a Tang Nano 20K pelo USB-C.
2. No IDE: **Tools → Programmer** (ou duplo-clique em *Program Device*).
3. O cable **Gowin USB Cable (FT2CH)** deve aparecer; clique em *Scan
   Device* — deve listar o `GW2AR-18C`.
4. Na coluna **Operation**, escolha:
   - **`SRAM Program`** — grava na SRAM do FPGA. Rápido, ideal para
     testes, **perde ao desligar**;
   - **`embFlash Erase, Program`** — grava na flash interna. O Altair
     passa a iniciar sozinho ao ligar a placa. Use este quando estiver
     satisfeito.
5. Em **FS File**, aponte para `impl/pnr/altair8800.fs` e clique em
   **Program/Configure** (raio verde).

### 7.2 Alternativa: openFPGALoader

Ferramenta livre, ótima no Linux (também existe para Windows/macOS):

```bash
# instalar (Debian/Ubuntu)
sudo apt install openfpgaloader
# ou compilar a versão mais recente do github trabucayre/openFPGALoader

# regra udev (uma vez só, para gravar sem sudo)
sudo cp 99-openfpgaloader.rules /etc/udev/rules.d/ && sudo udevadm control --reload

# gravar na SRAM (teste rápido)
openFPGALoader -b tangnano20k impl/pnr/altair8800.fs

# gravar na flash interna (permanente)
openFPGALoader -b tangnano20k -f impl/pnr/altair8800.fs
```

## 8. Primeiro teste

A placa **não precisa do painel** para funcionar (o pino das chaves tem
pull-down e o sistema dá autorun):

1. Grave o bitstream. Os 6 LEDs onboard começam a piscar em sequência —
   é o bit do **Kill the Bit** circulando em D7..D2.
2. Abra um terminal serial na porta USB da placa, **115200 8N1**
   (Windows: `COMx`; Linux: `/dev/ttyUSB1` ou `/dev/ttyACM0`).
   O Kill the Bit não usa a serial, mas o console fica pronto para
   programas que usem as portas `10h`/`11h` (88-2SIO).
3. Pressione **S1**: o sistema reseta e reinicia do endereço `0000h`.

Com o painel montado (ver [montagem_painel.md](montagem_painel.md)):
acione **STOP** — o LED **WAIT** acende e os LEDs de endereço congelam.
**RUN** retoma. Esse é o teste de fumaça do painel.

## 9. Carregando outros programas

O `sw/make_boot.py` gera o `boot.hex` a partir de qualquer binário 8080:

```bash
# regenerar o Kill the Bit
python3 sw/make_boot.py

# carregar um binário em 0000h (ex.: Altair BASIC 4K)
python3 sw/make_boot.py basic4k.bin

# carregar com origem específica
python3 sw/make_boot.py monitor.bin 0xE000
```

Depois copie o novo `boot.hex` para o lugar do passo 5 e **rode a síntese
de novo** (o conteúdo da RAM entra no bitstream).

> O binário do BASIC não acompanha o projeto por direitos autorais, mas é
> fácil de achar em sites de preservação de software. O BASIC 4K espera o
> terminal na 88-2SIO em `10h`/`11h` — exatamente o que este projeto
> implementa. Na primeira pergunta (`MEMORY SIZE?`), só dê Enter.
>
> Alternativa histórica: digite programas direto pelo painel com
> STOP → EXAMINE → DEPOSIT/DEPOSIT NEXT → RUN, sem ressintetizar nada.

## 10. Solução de problemas

| Sintoma | Causa provável | Correção |
|---------|----------------|----------|
| Síntese ok, placa "morta", LEDs de endereço contando sem parar | `boot.hex` não encontrado → RAM zerada (NOPs) | Seção 5: copie o hex ou use caminho absoluto; procure "file not found" no log |
| P&R falha com erro de pino | Device/package errado no projeto | Recrie com `GW2AR-LV18QN88C8/I7` QN88 |
| P&R reclama de pino dual-purpose | Pino do `.cst` conflita com função de boot | Configuration → Dual-Purpose Pin → liberar o pino indicado |
| Programmer não acha a placa | Cabo só de carga, driver, permissão USB | Trocar cabo; Windows: driver FTDI; Linux: regra udev / grupo `plugdev` |
| Gravou mas perde ao desligar | Gravação foi em SRAM | Regravar com `embFlash Erase, Program` (ou `-f` no openFPGALoader) |
| Serial não responde | Porta/baud errados | 115200 8N1; na Tang Nano 20K a UART do BL616 costuma ser a **segunda** porta COM/tty enumerada |
| LEDs do painel acesos aleatórios | RCLK/SRCLK trocados ou cadeia invertida | Conferir pinos 73/74/75 e a ordem dos CIs (ver manual de montagem) |
| Chaves não respondem | `/PL` e `CP` trocados, ou falta pull-down | Conferir pinos 76/80/85 e os 10 kΩ |
| Timing report com falha | Edição no código criou caminho longo | Manter `ce` (clock-enable) — não dividir o clock criando clock derivado |

---

*Próximo passo: [montagem_painel.md](montagem_painel.md) — construção
física do painel e cabeamento até a placa.*
