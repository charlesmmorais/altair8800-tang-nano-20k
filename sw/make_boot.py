#!/usr/bin/env python3
"""
make_boot.py - Gera boot.hex (64K linhas, 1 byte/linha) para a RAM do Altair.

Uso:
    python3 make_boot.py                  -> boot.hex com "Kill the Bit"
    python3 make_boot.py programa.bin     -> boot.hex com o binario (ORG 0)
    python3 make_boot.py programa.bin 0xE000  -> binario carregado em 0xE000

Ex.: para rodar o Altair BASIC 4K, obtenha o binario (nao incluido por
licenca) e gere o hex com ORG 0x0000.
"""
import sys

KILL_THE_BIT = bytes([
    0x21, 0x00, 0x00,        # 0000 LXI  H,0000
    0x16, 0x80,              # 0003 MVI  D,80h
    0x01, 0x0E, 0x00,        # 0005 LXI  B,000Eh   ; velocidade
    0x1A,                    # 0008 LDAX D? (na verdade: atraso, ver nota)
    0x1A,                    # 0009
    0x1A,                    # 000A
    0x1A,                    # 000B
    0x09,                    # 000C DAD  B
    0xD2, 0x08, 0x00,        # 000D JNC  0008
    0xDB, 0xFF,              # 0010 IN   FFh       ; sense switches
    0xAA,                    # 0012 XRA  D
    0x0F,                    # 0013 RRC
    0x57,                    # 0014 MOV  D,A
    0xC3, 0x08, 0x00,        # 0015 JMP  0008
])

def main():
    mem = bytearray(65536)
    if len(sys.argv) >= 2:
        org = int(sys.argv[2], 0) if len(sys.argv) >= 3 else 0
        data = open(sys.argv[1], "rb").read()
        mem[org:org + len(data)] = data
        print(f"{sys.argv[1]}: {len(data)} bytes @ {org:04X}")
    else:
        mem[0:len(KILL_THE_BIT)] = KILL_THE_BIT
        print("boot.hex: Kill the Bit (24 bytes @ 0000)")

    with open("boot.hex", "w") as f:
        for b in mem:
            f.write(f"{b:02x}\n")
    print("boot.hex gerado (65536 linhas).")

if __name__ == "__main__":
    main()
