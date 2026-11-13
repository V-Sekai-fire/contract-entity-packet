import EntityPacket.Gen
open EntityPacket

def HEADER : String :=
  "hex,gid,pumx,pumy,pumz,velx,vely,velz,accx,accy,accz,hlc,class_owner,sub_index,rotx,roty,rotz,payload"

def NAMES : Array String := (HEADER.splitOn ",").toArray

def nibble (c : Char) : Option Nat :=
  let n := c.toNat
  if 48 <= n && n <= 57 then some (n - 48) else if 97 <= n && n <= 102 then some (n - 87) else none

def unhex (s : String) : Option Bytes := Id.run do
  let cs := s.toList.toArray
  if cs.size % 2 != 0 then return none
  let mut out : Bytes := #[]
  for i in [0:cs.size / 2] do
    match nibble cs[2 * i]!, nibble cs[2 * i + 1]! with
    | some a, some b => out := out.push (UInt8.ofNat (a * 16 + b))
    | _, _ => return none
  return some out

def fieldsOf (d : Packet) : Array Int :=
  #[Int.ofNat d.gid.toNat, d.posUm.1.toInt, d.posUm.2.1.toInt, d.posUm.2.2.toInt,
    d.vel.1.toInt, d.vel.2.1.toInt, d.vel.2.2.toInt,
    d.accel.1.toInt, d.accel.2.1.toInt, d.accel.2.2.toInt,
    Int.ofNat d.hlc.toNat, Int.ofNat d.classOwner.toNat, Int.ofNat d.subIndex.toNat,
    d.rot.1.toInt, d.rot.2.1.toInt, d.rot.2.2.toInt]

/-- `none` when the row decodes from its `hex` to the listed values and encodes back to the same `hex`. -/
def rowError (line : String) : Option String := Id.run do
  let c := (line.splitOn ",").toArray
  if c.size != NAMES.size then return some s!"{c.size} columns, expected {NAMES.size}"
  let some b := unhex c[0]! | return some "hex is not lowercase hexadecimal"
  if b.size != SIZE then return some s!"hex holds {b.size} bytes, expected {SIZE}"
  let d := decode b
  let want := fieldsOf d
  for i in [0:want.size] do
    if c[i + 1]! != toString want[i]! then
      return some s!"{NAMES[i + 1]!} is listed as {c[i + 1]!}, hex decodes to {want[i]!}"
  if c[17]! != hex d.payload then return some s!"payload is listed as {c[17]!}, hex decodes to {hex d.payload}"
  if hex (encode d) != c[0]! then return some s!"hex encodes back to {hex (encode d)}"
  return none

def flipBit (line : String) (bit : Nat) : String :=
  match line.splitOn "," with
  | h :: rest =>
    match unhex h with
    | some b => ",".intercalate (hex (b.set! (bit / 8) (b[bit / 8]! ^^^ UInt8.ofNat (1 <<< (bit % 8)))) :: rest)
    | none => line
  | [] => line

def main (args : List String) : IO UInt32 := do
  let plant := args.contains "plant"
  let path := (args.filter (· != "plant")).headD "packet_golden_full.csv"
  let text ← IO.FS.readFile path
  let lines := ((text.splitOn "\n").filter (· != "")).toArray
  if lines.size == 0 || lines[0]! != HEADER then
    IO.println s!"golden_check FAIL {path}: the header row is not {HEADER}"
    return 1
  let mut rows := lines.extract 1 lines.size
  if plant then rows := rows.set! 0 (flipBit rows[0]! (OFF_ROT * 8))
  let mut fails := 0
  if rows.size != 64 then
    IO.println s!"golden_check FAIL {path}: {rows.size} rows, expected 64"
    fails := fails + 1
  for i in [0:rows.size] do
    if let some e := rowError rows[i]! then
      IO.println s!"golden_check FAIL row {i}: {e}"
      fails := fails + 1
    else if (rows[i]!.splitOn ",").head! != hex (encode (mk i)) then
      IO.println s!"golden_check FAIL row {i}: hex is not the generator's packet {i}"
      fails := fails + 1
  let mut flips := 0
  let mut missed := 0
  if !plant && fails == 0 then
    for r in rows do
      for bit in [0:SIZE * 8] do
        flips := flips + 1
        if (rowError (flipBit r bit)).isNone then missed := missed + 1
    IO.println s!"planted: {flips - missed} of {flips} single-bit flips of a row's hex are caught"
  if fails > 0 || missed > 0 then
    IO.println s!"golden_check FAIL: {fails} failing, {missed} flips missed{if plant then " (one bit planted in row 0)" else ""}"
    return 1
  IO.println s!"golden_check: PASS, {rows.size} rows of {path} decode to their listed fields and encode back to their hex"
  return 0
