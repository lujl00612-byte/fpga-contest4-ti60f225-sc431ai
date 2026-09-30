"""Temporary SRAM configuration of a Ti60 bitstream over FT4232 channel B.

Uses FTDI D2XX/MPSSE because this machine's Efinity installation is mixed-version.
Never accesses SPI flash. Run without --program to check IDCODE only.
"""
import argparse
import ctypes as c
from pathlib import Path
import sys
import time

EXPECTED_ID = 0x10660A79


class D2XX:
    def __init__(self):
        self.dll = c.WinDLL("ftd2xx.dll")
        self.handle = c.c_void_p()
        self._check(self.dll.FT_Open(1, c.byref(self.handle)), "FT_Open(B)")
        self._check(self.dll.FT_ResetDevice(self.handle), "FT_ResetDevice")
        self._check(self.dll.FT_SetUSBParameters(self.handle, 65536, 65536), "FT_SetUSBParameters")
        self._check(self.dll.FT_SetLatencyTimer(self.handle, 2), "FT_SetLatencyTimer")
        self._check(self.dll.FT_SetTimeouts(self.handle, 5000, 5000), "FT_SetTimeouts")
        self._check(self.dll.FT_SetBitMode(self.handle, 0, 0), "FT_SetBitMode(reset)")
        time.sleep(0.05)
        self._check(self.dll.FT_SetBitMode(self.handle, 0x0B, 0x02), "FT_SetBitMode(MPSSE)")
        time.sleep(0.05)
        # Disable loopback, disable /5 divider, disable adaptive clocking.
        # 60 MHz / (2 * (4+1)) = 6 MHz JTAG clock.
        self.write(bytes([0x85, 0x8A, 0x97, 0x86, 4, 0, 0x80, 0x08, 0x0B]))

    @staticmethod
    def _check(status, operation):
        if status != 0:
            raise RuntimeError(f"{operation}: FT_STATUS={status}")

    def write(self, data):
        buf = c.create_string_buffer(data)
        done = c.c_ulong()
        self._check(self.dll.FT_Write(self.handle, buf, len(data), c.byref(done)), "FT_Write")
        if done.value != len(data):
            raise RuntimeError(f"short FT_Write {done.value}/{len(data)}")

    def read(self, size):
        buf = c.create_string_buffer(size)
        done = c.c_ulong()
        self._check(self.dll.FT_Read(self.handle, buf, size, c.byref(done)), "FT_Read")
        if done.value != size:
            raise RuntimeError(f"short FT_Read {done.value}/{size}")
        return buf.raw

    def close(self):
        if self.handle:
            self.dll.FT_SetBitMode(self.handle, 0, 0)
            self.dll.FT_Close(self.handle)
            self.handle = None


class JTAG:
    def __init__(self, ftdi):
        self.ftdi = ftdi

    def tms(self, bits, final_tdi=0):
        assert 1 <= len(bits) <= 7
        data = sum(bit << i for i, bit in enumerate(bits)) | (final_tdi << 7)
        self.ftdi.write(bytes([0x4B, len(bits) - 1, data]))

    def reset(self):
        self.tms([1, 1, 1, 1, 1, 0])

    def ir(self, opcode):
        # Run-Test/Idle -> Shift-IR; five-bit Titanium IR, LSB first.
        self.tms([1, 1, 0, 0])
        self.ftdi.write(bytes([0x1B, 3, opcode & 0x0F]))
        self.tms([1], (opcode >> 4) & 1)
        self.tms([1, 0])

    def idcode(self):
        self.reset()
        self.ir(0x03)
        self.tms([1, 0, 0])
        self.ftdi.write(bytes([0x28, 3, 0, 0x87]))
        value = int.from_bytes(self.ftdi.read(4), "little")
        self.tms([1, 1, 0])
        return value

    def status(self):
        # Titanium 32-bit JTAG status instruction, as used by Efinity.
        self.reset()
        self.ir(0x0C)
        self.tms([1, 0, 0])
        self.ftdi.write(bytes([0x28, 3, 0, 0x87]))
        value = int.from_bytes(self.ftdi.read(4), "little")
        self.tms([1, 1, 0])
        return value

    def configure(self, bitstream):
        # Match the vendor's volatile JTAG sequence: PROGRAM twice on Ti60,
        # padded bitstream in Shift-DR, then ENTERUSER and extra clocks.
        self.reset()
        self.ir(0x04)
        time.sleep(0.01)
        self.reset()
        self.ir(0x04)
        self.tms([1, 0, 0])
        data = bytearray(20)
        with bitstream.open("rt", encoding="ascii") as source:
            data.extend(int(line[:2], 16) for line in source if line.strip())
        data.extend(b"\0" * (-len(data) % 4096))
        # 0x11 clocks bytes MSB first on TDI. Efinity builds each byte's
        # bit sequence from its eight-character binary spelling (MSB first).
        for offset in range(0, len(data), 4096):
            block = data[offset:offset + 4096]
            self.ftdi.write(bytes([0x11, 0xFF, 0x0F]) + block)
        self.tms([1, 1, 0])
        time.sleep(0.1)
        self.ir(0x07)
        self.tms([1, 0, 0])
        self.ftdi.write(bytes([0x19, 11, 0]) + bytes(12))
        self.ftdi.write(bytes([0x1B, 3, 0]))
        self.tms([1, 1, 0])
        self.reset()
        time.sleep(0.2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--program", action="store_true")
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--bit", type=Path)
    args = parser.parse_args()
    if args.program and (args.bit is None or not args.bit.is_file()):
        parser.error("--program needs an existing --bit file")
    ftdi = D2XX()
    try:
        jtag = JTAG(ftdi)
        before = jtag.idcode()
        print(f"Ti60 IDCODE before: 0x{before:08X}", flush=True)
        if before != EXPECTED_ID:
            raise RuntimeError("unexpected JTAG IDCODE; configuration aborted")
        if args.status:
            print(f"Ti60 JTAG status: 0x{jtag.status():08X}", flush=True)
        if args.program:
            print(f"Sending volatile JTAG configuration from {args.bit}", flush=True)
            jtag.configure(args.bit)
            after = jtag.idcode()
            print(f"Ti60 IDCODE after: 0x{after:08X}", flush=True)
            if after != EXPECTED_ID:
                raise RuntimeError("IDCODE check after configuration failed")
            if args.status:
                print(f"Ti60 JTAG status after: 0x{jtag.status():08X}", flush=True)
    finally:
        ftdi.close()


if __name__ == "__main__":
    sys.exit(main())
