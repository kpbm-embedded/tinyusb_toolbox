import Base

# CRC-16/USB as USB 2.0 data packets use it: poly x^16+x^15+x^2+1 bit-reflected (0xA001 = 40961),
# register starts at 0xFFFF (65535), the packet carries the inverted register. Check value of
# "123456789": 0xB4C8 = 46280.

# reference: one bit per step, LSB first, as the USB spec describes the shift register
def bit_pick(low: Bool, sh: U32) -> U32:
  match low:
    case True{}:
      (sh .^. 40961 : U32)
    case False{}:
      sh

def bit_step(+c: U32) -> U32:
  bit_pick(U32.is_ne((c .&. 1 : U32), 0), (c >> 1n : U32))

def bits(n: Nat, c: U32) -> U32:
  match n:
    case 0n:
      c
    case 1n+p:
      bits(p, bit_step(c))

def byte_ref(b: U32) -> U32:
  bits(8n, b)

# firmware version (Pico-PIO-USB update_usb_crc16): crc = (crc >> 8) ^ table[(crc ^ data) & 0xFF]
# decision procedure: walking the table, entry i equals the bitwise CRC of byte i
def table_ok(tbl: List<U32>, +i: Nat) -> Bool:
  match tbl:
    case Nil{}:
      True{}
    case Con{h, t}:
      U32.is_eq(h, byte_ref(U32.from_nat(i))) && table_ok(t, 1n+i)

def count(xs: List<U32>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{h, t}:
      1n+count(t)

# streaming register update (no final inversion), and the packet CRC
def step(+c: U32, h: U32) -> U32:
  (byte_ref(((c .^. h) .&. 255 : U32)) .^. (c >> 8n) : U32)

def run(xs: List<U32>, c: U32) -> U32:
  match xs:
    case Nil{}:
      c
    case Con{h, t}:
      run(t, step(c, h))

def crc16(xs: List<U32>) -> U32:
  (run(xs, 65535) .^. 65535 : U32)

def check_input() -> List<U32>:
  [49, 50, 51, 52, 53, 54, 55, 56, 57]

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("crc16_usb(123456789) = " ++ U32.show(crc16(check_input())))
