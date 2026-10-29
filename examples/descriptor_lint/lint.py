#!/usr/bin/env python3
"""lint.py: check USB descriptors dumped by harness.c (descriptor_lint example, 32_21_tinyusb).

Reads the hex lines on stdin (or a file) and checks what a host checks during enumeration, plus
full-speed limits: lengths and types, wTotalLength, bNumInterfaces, unique endpoint addresses,
max packet sizes, interface association (IAD) ranges, string descriptors (UTF-16LE, referenced
indices exist), the BOS total length, and that HID report descriptors are well formed
(item sizes, balanced collections). Prints one line per problem; exit 1 when there is any.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

EP_LIMIT_FS = {0: 1023, 1: 1023, 2: 64, 3: 64}  # control(n/a), iso, bulk, interrupt (full speed)


def walk(buf: bytes, errs: list[str], what: str) -> list[bytes]:
    """Split a descriptor block into descriptors; every bLength must be >= 2 and fit."""
    out, off = [], 0
    while off < len(buf):
        n = buf[off]
        if n < 2 or off + n > len(buf):
            errs.append(f"{what}: bad bLength {n} at offset {off}")
            break
        out.append(buf[off:off + n])
        off += n
    return out


def check_device(d: bytes, errs: list[str]) -> list[int]:
    if len(d) != 18 or d[0] != 18 or d[1] != 1:
        errs.append(f"device: length/type {d[0] if d else '-'}/{d[1] if len(d) > 1 else '-'} (want 18/1)")
        return []
    if d[7] not in (8, 16, 32, 64):
        errs.append(f"device: bMaxPacketSize0 {d[7]} not 8/16/32/64")
    if d[17] < 1:
        errs.append("device: bNumConfigurations 0")
    return [d[14], d[15], d[16]]  # iManufacturer, iProduct, iSerialNumber


def check_hid_report(r: bytes, errs: list[str], tag: str) -> None:
    off, depth = 0, 0
    while off < len(r):
        b = r[off]
        if b == 0xFE:  # long item
            if off + 1 >= len(r):
                errs.append(f"{tag}: truncated long item")
                return
            off += 3 + r[off + 1]
            continue
        size = (0, 1, 2, 4)[b & 3]
        if off + 1 + size > len(r):
            errs.append(f"{tag}: item 0x{b:02x} at {off} runs past the end")
            return
        tag_type = b & 0xFC
        if tag_type == 0xA0:
            depth += 1
        elif tag_type == 0xC0:
            depth -= 1
            if depth < 0:
                errs.append(f"{tag}: End Collection without Collection at {off}")
                return
        off += 1 + size
    if depth != 0:
        errs.append(f"{tag}: {depth} collection(s) not closed")


def check_config(c: bytes, errs: list[str]) -> list[int]:
    strings: list[int] = []
    if len(c) < 9 or c[1] != 2:
        errs.append("config: not a configuration descriptor")
        return strings
    total = c[2] | c[3] << 8
    if total != len(c):
        errs.append(f"config: wTotalLength {total} != dumped length {len(c)}")
    descs = walk(c, errs, "config")
    if sum(len(d) for d in descs) != total:
        errs.append("config: descriptors do not add up to wTotalLength")
    strings.append(c[6])
    ifaces, eps, iads = set(), {}, []
    cur_if = None
    for d in descs[1:]:
        t = d[1]
        if t == 4:  # interface
            if len(d) != 9:
                errs.append(f"interface: bLength {len(d)} != 9")
                continue
            cur_if = d[2]
            ifaces.add(d[2])
            strings.append(d[8])
        elif t == 5:  # endpoint
            if len(d) not in (7, 9):  # 9 = audio 1.0 endpoint
                errs.append(f"endpoint: bLength {len(d)}")
                continue
            addr, attr, mps = d[2], d[3] & 3, (d[4] | d[5] << 8) & 0x7FF
            if addr & 0x0F == 0:
                errs.append(f"endpoint 0x{addr:02x} in interface {cur_if}: endpoint 0 is reserved")
            if addr in eps and eps[addr] != cur_if:  # alternate settings of one interface may reuse it
                errs.append(f"endpoint 0x{addr:02x} used by interfaces {eps[addr]} and {cur_if}")
            eps.setdefault(addr, cur_if)
            if mps > EP_LIMIT_FS[attr] and attr != 1:
                errs.append(f"endpoint 0x{addr:02x}: wMaxPacketSize {mps} > full-speed limit {EP_LIMIT_FS[attr]}")
            if mps == 0 and attr != 1:
                errs.append(f"endpoint 0x{addr:02x}: wMaxPacketSize 0")
        elif t == 0x0B:  # interface association
            if len(d) != 8:
                errs.append(f"IAD: bLength {len(d)} != 8")
                continue
            iads.append((d[2], d[3]))
            strings.append(d[7])
    if len(ifaces) != c[4]:
        errs.append(f"config: bNumInterfaces {c[4]} but {len(ifaces)} interface numbers {sorted(ifaces)}")
    if ifaces and sorted(ifaces) != list(range(len(ifaces))):
        errs.append(f"config: interface numbers not 0..n-1: {sorted(ifaces)}")
    for first, count in iads:
        if count < 1 or any(i not in ifaces for i in range(first, first + count)):
            errs.append(f"IAD first {first} count {count} names missing interfaces")
    return strings


def check_string(i: int, s: bytes, errs: list[str]) -> None:
    if len(s) < 2 or s[0] != len(s) or s[1] != 3 or len(s) % 2:
        errs.append(f"string {i}: bad header/length")
        return
    if i == 0:
        if len(s) < 4:
            errs.append("string 0: no language id")
        return
    try:
        s[2:].decode("utf-16-le")
    except UnicodeDecodeError:
        errs.append(f"string {i}: not UTF-16LE")


def check_bos(b: bytes, errs: list[str]) -> None:
    if len(b) < 5 or b[0] != 5 or b[1] != 0x0F:
        errs.append("BOS: bad header")
        return
    if (b[2] | b[3] << 8) != len(b):
        errs.append("BOS: wTotalLength mismatch")
    caps = walk(b[5:], errs, "BOS")
    if len(caps) != b[4]:
        errs.append(f"BOS: bNumDeviceCaps {b[4]} but {len(caps)} capabilities")


def lint(lines: list[str]) -> tuple[list[str], str]:
    errs: list[str] = []
    dev = cfg = bos = None
    strs: dict[int, bytes] = {}
    hid: dict[int, bytes] = {}
    for ln in lines:
        parts = ln.split()
        if not parts:
            continue
        if parts[0] == "DEV":
            dev = bytes.fromhex(parts[1])
        elif parts[0] == "CFG":
            cfg = bytes.fromhex(parts[1])
        elif parts[0] == "BOS":
            bos = bytes.fromhex(parts[1])
        elif parts[0] == "STR":
            strs[int(parts[1])] = bytes.fromhex(parts[2])
        elif parts[0] == "HIDREP":
            hid[int(parts[1])] = bytes.fromhex(parts[2] if len(parts) > 2 else "")
    if dev is None or cfg is None:
        return ["no DEV/CFG lines (harness did not run?)"], ""
    refs = check_device(dev, errs) + check_config(cfg, errs)
    for i, s in strs.items():
        check_string(i, s, errs)
    if 0 not in strs:
        errs.append("string 0 (language ids) missing")
    for i in sorted({r for r in refs if r}):
        if i not in strs:
            errs.append(f"string index {i} referenced but tud_descriptor_string_cb returns NULL")
    if bos is not None:
        check_bos(bos, errs)
    for i, r in hid.items():
        check_hid_report(r, errs, f"HID report {i}")
    vid, pid = dev[8] | dev[9] << 8, dev[10] | dev[11] << 8
    product = strs.get(dev[15], b"\x02\x03")[2:].decode("utf-16-le", "replace") if len(dev) == 18 else "?"
    summary = (f"{vid:04x}:{pid:04x} '{product}' {cfg[4]} interface(s), config {len(cfg)} B, "
               f"{len(strs)} strings{', BOS' if bos else ''}{f', {len(hid)} HID report(s)' if hid else ''}")
    return errs, summary


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dump", nargs="?", type=Path, help="harness output (default: stdin)")
    ap.add_argument("--name", default="device", help="label for the output lines")
    a = ap.parse_args()
    text = a.dump.read_text() if a.dump else sys.stdin.read()
    errs, summary = lint(text.splitlines())
    for e in errs:
        print(f"FAIL {a.name}: {e}")
    if not errs:
        print(f"ok   {a.name}: {summary}")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
