import Base
import ./usb_crc.bend as U
import ./table16.bend as T
import ./LAWS.bend as L

# proof by computation: the checker evaluates the decision procedure for all 256 table entries
def L.table_matches_reference():
  {==}

def L.table_size():
  {==}

def L.check_value():
  {==}

# induction on xs: the empty message is reflexivity, one byte more is the hypothesis for the tail
def L.run_append(xs, ys, c):
  match xs:
    case Nil{}:
      {==}
    case Con{h, t}:
      L.run_append(t, ys, U.step(c, h))
