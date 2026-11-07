import EntityPacket
open EntityPacket

def next (s : UInt64) : UInt64 := s * 6364136223846793005 + 1442695040888963407

def unit (s : UInt64) : Float := (s >>> 11).toFloat / 9007199254740992.0 * 2.0 - 1.0

def randQuats (n : Nat) : Array Quat := Id.run do
  let mut s : UInt64 := 88172645463325252
  let mut out := #[]
  for _ in [0:n] do
    s := next s
    let a := unit s
    s := next s
    let b := unit s
    s := next s
    let c := unit s
    s := next s
    let d := unit s
    out := out.push (Quat.normalize ⟨a, b, c, d⟩)
  return out

def angErr (a b : Quat) : Float :=
  let d := Quat.mul a (Quat.conj b)
  2.0 * Float.atan2 (Float.sqrt (d.x * d.x + d.y * d.y + d.z * d.z)) (Float.abs d.w)

def axisAngle (ax ay az ang : Float) : Quat :=
  ⟨ax * Float.sin (ang / 2), ay * Float.sin (ang / 2), az * Float.sin (ang / 2), Float.cos (ang / 2)⟩

def special : Array Quat :=
  let h := PI / 2
  #[Quat.identity, axisAngle 1 0 0 h, axisAngle 1 0 0 (-h), axisAngle 0 1 0 h, axisAngle 0 1 0 (-h),
    axisAngle 0 0 1 h, axisAngle 0 0 1 (-h), axisAngle 1 0 0 PI, axisAngle 0 0 1 PI,
    axisAngle 0 1 0 PI, Quat.mul (axisAngle 1 0 0 PI) (axisAngle 0 1 0 1.0),
    Quat.mul (axisAngle 0 0 1 (PI - 1e-6)) (axisAngle 0 1 0 3.1),
    Quat.mul (axisAngle 1 0 0 1e-7) (axisAngle 0 1 0 (-PI + 1e-7))]

def maxErr (rt : Quat → Quat) (qs : Array Quat) : Float × Nat :=
  qs.foldl (fun (m, bad) q =>
    let e := angErr (rt q) q
    if e.isNaN then (m, bad + 1) else (if e > m then e else m, bad)) (0.0, 0)

def linearGap (a b : Int16) : Int := (a.toInt - b.toInt).natAbs

def circularGap (a b : Int16) : Int :=
  let d := (a.toInt - b.toInt) % 65536
  if d > 32768 then 65536 - d else d

def codeGap (a b : Int16 × Int16 × Int16) : Int :=
  max (linearGap a.1 b.1) (max (linearGap a.2.1 b.2.1) (circularGap a.2.2 b.2.2))

def BOUND : Float := 2e-4

def main : IO UInt32 := do
  let qs := randQuats 100000 ++ special
  let mut fails := 0
  let check (name : String) (ok : Bool) (detail : String) : IO Nat := do
    IO.println s!"{if ok then "PASS" else "FAIL"} {name}: {detail}"
    pure (if ok then 0 else 1)
  let (e, nan) := maxErr (fun q => decodeRot (encodeRot q)) qs
  fails := fails + (← check "round trip quat" (e < BOUND && nan == 0) s!"max error {e} rad over {qs.size}, bound {BOUND}, nan {nan}")
  let (eb, nanb) := maxErr (fun q => (decodeRotBasis (encodeRotBasis (Basis.ofQuat q))).toQuat) qs
  fails := fails + (← check "round trip basis" (eb < BOUND && nanb == 0) s!"max error {eb} rad, nan {nanb}")
  let gap := qs.foldl (fun m q => max m (codeGap (encodeRot q) (encodeRotBasis (Basis.ofQuat q)))) 0
  fails := fails + (← check "basis and quat codes agree" (gap <= 1) s!"max gap {gap} LSB")
  let gapNeg := qs.foldl (fun m q => max m (codeGap (encodeRot q) (encodeRot q.neg))) 0
  fails := fails + (← check "q and -q" (gapNeg <= 1) s!"max gap {gapNeg} LSB")
  let dev := qs.foldl (fun m q => let d := Float.abs ((decodeRot (encodeRot q)).norm - 1.0); if d > m then d else m) 0.0
  fails := fails + (← check "decode is unit" (dev < 1e-9) s!"max deviation {dev}")
  let id := encodeRot Quat.identity
  fails := fails + (← check "identity" (id == (0, 0, 0)) s!"{id.1} {id.2.1} {id.2.2}")
  let tw := encodeRot (axisAngle 0 1 0 (PI / 2))
  fails := fails + (← check "twist 90 about Y" (tw.1 == 0 && tw.2.1 == 0 && circularGap tw.2.2 16384 <= 1) s!"{tw.1} {tw.2.1} {tw.2.2}")
  let sx := encodeRot (axisAngle 1 0 0 (PI / 2))
  fails := fails + (← check "swing 90 about X" (linearGap sx.1 16384 <= 1 && sx.2.1 == 0 && sx.2.2 == 0) s!"{sx.1} {sx.2.1} {sx.2.2}")
  let sz := encodeRot (axisAngle 0 0 1 (PI / 2))
  fails := fails + (← check "swing 90 about Z" (sz.1 == 0 && linearGap sz.2.1 16384 <= 1 && sz.2.2 == 0) s!"{sz.1} {sz.2.1} {sz.2.2}")
  let (e1, _) := maxErr (fun q => let c := encodeRot q; Quat.mul (twistFromCode c.2.2) (swingFromCodes c.1 c.2.1)) qs
  fails := fails + (← check "planted: swing and twist swapped is caught" (e1 > BOUND) s!"max error {e1}")
  let (e2, _) := maxErr (fun q => let c := encodeRot q; decodeRot (c.1, c.2.1, 0)) qs
  fails := fails + (← check "planted: twist dropped is caught" (e2 > BOUND) s!"max error {e2}")
  let (e3, _) := maxErr (fun q => decodeRot (encodeRot (Quat.mul (axisAngle 1 0 0 1e-3) q))) qs
  fails := fails + (← check "planted: 1 mrad offset is caught" (e3 > BOUND) s!"max error {e3}")
  IO.println s!"rot check: {fails} failing"
  pure (if fails == 0 then 0 else 1)
