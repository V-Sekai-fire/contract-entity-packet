import EntityPacket.Gen
import Plausible
open EntityPacket Plausible

/-- The roundtrip property: decode ∘ encode = id on every field.
    This is the property that would have caught the missing payload write. -/
def roundtrips (n : Nat) : Bool :=
  let p := mk n
  let d := decode (encode p)
  d.gid == p.gid
    && d.posUm == p.posUm
    && d.vel == p.vel
    && d.accel == p.accel
    && d.hlc == p.hlc
    && d.classOwner == p.classOwner
    && d.subIndex == p.subIndex
    && d.rot == p.rot
    && d.payload == p.payload

/-- The packet is always exactly 100 bytes. -/
def sizeInvariant (n : Nat) : Bool := (encode (mk n)).size == SIZE
/-- The reserved bytes at the tail are written as zero. -/
def reservedZero (n : Nat) : Bool :=
  let b := encode (mk n)
  (List.range RESERVED_LEN).all (fun i => b[OFF_RESERVED + i]! == 0)

#eval Testable.check (∀ n : Nat, roundtrips n = true)
#eval Testable.check (∀ n : Nat, sizeInvariant n = true)

def main : IO Unit := do
  let mut bad := 0
  for n in [0:50000] do
    if roundtrips n && sizeInvariant n && reservedZero n then pure () else bad := bad + 1
  IO.println s!"entity packet codec: {50000 - bad}/50000 roundtrip+size, {bad} gaps"
