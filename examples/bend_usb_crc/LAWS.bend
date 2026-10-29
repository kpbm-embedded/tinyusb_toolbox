import Base
import ./usb_crc.bend as U
import ./table16.bend as T

# the 256-entry table shipped in Pico-PIO-USB (table16.bend is generated from its usb_crc.c) equals the
# bitwise CRC-16/USB of every byte value
law table_matches_reference:
  {U.table_ok(T.table16(), 0n) == True{} : Bool}

# ... and it has exactly 256 entries (a byte indexes it)
law table_size:
  {U.count(T.table16()) == 256n : Nat}

# the catalogue check value of CRC-16/USB
law check_value:
  {U.crc16(U.check_input()) == 46280 : U32}

# streaming: chunked buffers (a packet split over several FIFO reads) give the same register as one buffer
law run_append:
  for xs: List<U32>
  for ys: List<U32>
  for c: U32
  {U.run(List.append(&1, U32, xs, ys), c) == U.run(ys, U.run(xs, c)) : U32}
