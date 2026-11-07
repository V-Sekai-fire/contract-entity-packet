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

/-- The code decodes at or above the true magnitude: `|code| * A_MAX >= |a| * 32767`. -/
def covers (enc : Int → Int16) (a : Int) : Bool :=
  (enc a).toInt.natAbs * A_MAX_UM_PER_TICK2 >= a.natAbs * 32767
def accelSample (n : Nat) : Int :=
  Int.ofNat ((n * 2654435761) % (2 * A_MAX_UM_PER_TICK2 / 2 + 1)) - Int.ofNat (A_MAX_UM_PER_TICK2 / 2)
def main : IO UInt32 := do
  let mut bad := 0
  for n in [0:50000] do
    if roundtrips n && sizeInvariant n && reservedZero n then pure () else bad := bad + 1
  IO.println s!"entity packet codec: {50000 - bad}/50000 roundtrip+size, {bad} gaps"
  let mut upBad := 0
  let mut nearBad := 0
  for n in [0:50000] do
    let a := accelSample n
    if !covers accelCodeUp a then upBad := upBad + 1
    if !covers accelCodeNearest a then nearBad := nearBad + 1
  IO.println s!"acceleration code rounded up: {50000 - upBad}/50000 cover the true magnitude, {upBad} under"
  IO.println s!"planted round-to-nearest: {nearBad}/50000 under (must be more than 0)"
  if bad > 0 || upBad > 0 || nearBad == 0 then
    IO.println "packet_demo FAIL"
    return 1
  return 0
