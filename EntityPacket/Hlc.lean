import EntityPacket.Codec

namespace EntityPacket

/-! # Hybrid Logical Clock

The traditional one: Kulkarni, Demirbas, Madappa, Avva and Leone, "Logical Physical Clocks",
OPODIS 2014. A timestamp is a pair `(l, c)`. `l` is the largest physical time this node has seen,
from its own clock or from any message. `c` is a counter that orders events while `l` stands
still. Pairs compare `l` first, then `c`.

On the wire the pair is one `UInt64`, as in the paper: the high 48 bits are `l` in milliseconds
since the Unix epoch (good until the year 10889) and the low 16 bits are `c`. Comparing the
packed integers is comparing the pairs.

Two rules, with `pt` the node's physical clock in milliseconds:

* Local or send event. `l' = l; l = max l' pt;` if `l = l'` then `c = c + 1` else `c = 0`.
* Receive `(lm, cm)`. `l' = l; l = max l' lm pt;` if all of `l`, `l'`, `lm` agree then
  `c = max c cm + 1`; if only `l = l'` then `c = c + 1`; if only `l = lm` then `c = cm + 1`;
  otherwise `c = 0`.

The counter has 16 bits and the paper bounds it by the clock skew, not by an unbounded run, so a
node that would overflow it refuses to stamp (`none`) rather than wrap, because a wrapped counter
puts a later event before an earlier one. -/

def HLC_C_BITS : Nat := 16
def HLC_C_MAX : Nat := 65535
/-- The most `l` can hold: 2^48 - 1 milliseconds. -/
def HLC_L_MAX : Nat := 281474976710655

structure Hlc where
 l : Nat -- milliseconds, below 2^48
 c : Nat -- below 2^16
 deriving Repr, BEq, DecidableEq

namespace Hlc

def zero : Hlc := ⟨0, 0⟩

/-- Pack to the wire word: `l` in the high 48 bits, `c` in the low 16. -/
def pack (h : Hlc) : UInt64 := UInt64.ofNat (h.l * 65536 + h.c)

def unpack (w : UInt64) : Hlc := ⟨w.toNat / 65536, w.toNat % 65536⟩

/-- The order the paper defines: `l` first, then `c`. -/
def lt (a b : Hlc) : Bool := a.l < b.l || (a.l == b.l && a.c < b.c)

/-- Stamp a local or send event at physical time `pt`. -/
def send (h : Hlc) (pt : Nat) : Option Hlc :=
 let l := max h.l pt
 let c := if l == h.l then h.c + 1 else 0
 if l > HLC_L_MAX || c > HLC_C_MAX then none else some ⟨l, c⟩

/-- Stamp the receipt of a message carrying `m`, at physical time `pt`. -/
def recv (h m : Hlc) (pt : Nat) : Option Hlc :=
 let l := max (max h.l m.l) pt
 let c :=
 if l == h.l && l == m.l then max h.c m.c + 1
 else if l == h.l then h.c + 1
 else if l == m.l then m.c + 1
 else 0
 if l > HLC_L_MAX || c > HLC_C_MAX then none else some ⟨l, c⟩

end Hlc
end EntityPacket
