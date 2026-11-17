import EntityPacket.Hlc
open EntityPacket

/-- The traditional rules, checked on a deterministic sweep and on worked cases. The control is a
    receive rule with one planted defect (it forgets the message's counter when all three times
    tie); the properties must reject it, or they prove nothing. -/

private def next (s : Nat) : Nat := (s * 6364136223846793005 + 1442695040888963407) % 18446744073709551616

private def recvBroken (h m : Hlc) (pt : Nat) : Option Hlc :=
  let l := max (max h.l m.l) pt
  let c := if l == h.l && l == m.l then h.c + 1  -- planted: drops `max h.c m.c`
    else if l == h.l then h.c + 1
    else if l == m.l then m.c + 1
    else 0
  if l > HLC_L_MAX || c > HLC_C_MAX then none else some ⟨l, c⟩

/-- Cases that share `l` often, so the counter rules are exercised and not only the clock. -/
private def cases (n : Nat) : List (Hlc × Hlc × Nat) := Id.run do
  let mut s := 12345
  let mut out := []
  for _ in [0:n] do
    s := next s
    let base := 1780000000000 + (s / 7) % 50
    s := next s
    let hl := base + (s / 11) % 3
    s := next s
    let ml := base + (s / 13) % 3
    s := next s
    let pt := base + (s / 17) % 3
    s := next s
    let hc := (s / 19) % 40
    s := next s
    let mc := (s / 23) % 40
    out := (⟨hl, hc⟩, ⟨ml, mc⟩, pt) :: out
  return out

private def fail (what : String) : IO Unit := do
  IO.eprintln s!"hlc_check: FAIL {what}"
  IO.Process.exit 1

def main : IO Unit := do
  let cs := cases 20000
  -- pack and unpack are inverses, and the packed order is the pair order
  for (h, m, _) in cs do
    unless Hlc.unpack (Hlc.pack h) == h do fail s!"unpack (pack {repr h})"
    unless (Hlc.pack h < Hlc.pack m) == Hlc.lt h m do fail s!"packed order differs from pair order for {repr h} {repr m}"
  -- send: strictly after the old stamp, never behind the physical clock
  for (h, _, pt) in cs do
    match Hlc.send h pt with
    | none => fail "send refused a small counter"
    | some r =>
      unless Hlc.lt h r do fail s!"send did not advance {repr h}"
      unless r.l ≥ pt do fail s!"send fell behind pt {pt}"
      unless r.l == max h.l pt do fail "send moved l beyond max l pt"
  -- receive: after both the node's stamp and the message's, l is the largest of the three times
  for (h, m, pt) in cs do
    match Hlc.recv h m pt with
    | none => fail "recv refused a small counter"
    | some r =>
      unless Hlc.lt h r && Hlc.lt m r do fail s!"recv not after both: {repr h} {repr m} pt {pt} gave {repr r}"
      unless r.l == max (max h.l m.l) pt do fail "recv l is not the largest of the three"
  -- the control: the planted defect must be caught by the same property
  let caught := cs.any fun (h, m, pt) =>
    match recvBroken h m pt with
    | some r => !(Hlc.lt h r && Hlc.lt m r)
    | none => false
  unless caught do fail "the planted receive defect was NOT caught, so the property proves nothing"
  -- worked cases
  unless Hlc.send ⟨100, 3⟩ 100 == some ⟨100, 4⟩ do fail "same ms: counter +1"
  unless Hlc.send ⟨100, 3⟩ 101 == some ⟨101, 0⟩ do fail "clock moved: counter resets"
  unless Hlc.send ⟨100, 3⟩ 90 == some ⟨100, 4⟩ do fail "clock behind: l stays, counter +1"
  unless Hlc.recv ⟨100, 3⟩ ⟨100, 9⟩ 100 == some ⟨100, 10⟩ do fail "three-way tie: max counter + 1"
  unless Hlc.recv ⟨100, 3⟩ ⟨105, 2⟩ 100 == some ⟨105, 3⟩ do fail "message ahead: its counter + 1"
  unless Hlc.recv ⟨100, 3⟩ ⟨99, 50⟩ 100 == some ⟨100, 4⟩ do fail "own l ties pt: counter + 1"
  unless Hlc.recv ⟨100, 3⟩ ⟨99, 50⟩ 200 == some ⟨200, 0⟩ do fail "clock ahead of both: reset"
  -- overflow refuses, it does not wrap
  unless Hlc.send ⟨100, 65535⟩ 100 == none do fail "a full counter wrapped"
  unless Hlc.send ⟨100, 65535⟩ 101 == some ⟨101, 0⟩ do fail "a full counter should reset when the clock moves"
  unless Hlc.pack ⟨HLC_L_MAX, 65535⟩ == 0xFFFFFFFFFFFFFFFF do fail "top of range is all ones"
  IO.println s!"hlc_check: PASS ({cs.length} sweep cases, 4 properties, control caught, 10 worked cases)"
