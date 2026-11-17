import Std.Tactic.BVDecide

namespace EntityPacket

/-- What kind of thing a packet is about: the top byte of `classOwner` (`(class << 24) | owner`).

    Defined here once. The C and Python emitters read this list, so a reader can no longer disagree with the
    spec about what a number means. A number that is not listed is not a class: `Class.ofByte?` says `none` and
    a receiver drops the packet, because guessing a meaning would be quietly wrong.

    `subIndex` is read through the class: for an object class it is the part of the object (0 is the whole), for
    `command` it is the command type. The payload is read through the class too. -/
inductive Class where
  /-- Never a real packet: a zeroed buffer decodes to this and is refused. -/
  | unset
  /-- A player's avatar root. -/
  | avatar
  /-- A tracked part of a player: head, hands, hips, by `subIndex`. -/
  | trackedPart
  /-- A simulated persona that is not a player. -/
  | persona
  /-- A thing that moves and has a mesh: `payload` holds the mesh's digest and scale. -/
  | prop
  /-- A camera. -/
  | camera
  /-- A light. -/
  | light
  /-- A transform with nothing to draw (a Blender empty, a group, a collection). -/
  | node
  /-- A command that fits in one packet: `subIndex` is the command's type, `payload` the command. -/
  | command
  deriving DecidableEq, Repr

/-- The wire byte of each class. These numbers are the contract: never reuse or renumber one. -/
def Class.toByte : Class → UInt8
  | .unset => 0
  | .avatar => 1
  | .trackedPart => 2
  | .persona => 3
  | .prop => 4
  | .camera => 5
  | .light => 6
  | .node => 7
  | .command => 128

def Class.ofByte? : UInt8 → Option Class
  | 0 => some .unset
  | 1 => some .avatar
  | 2 => some .trackedPart
  | 3 => some .persona
  | 4 => some .prop
  | 5 => some .camera
  | 6 => some .light
  | 7 => some .node
  | 128 => some .command
  | _ => none

/-- Every class, in wire order: what the emitters walk. -/
def Class.all : List Class :=
  [.unset, .avatar, .trackedPart, .persona, .prop, .camera, .light, .node, .command]

/-- The packet field for a class and an owner. The owner is 24 bits; a larger one has no encoding. -/
def classOwner (c : Class) (owner : UInt32) : Option UInt32 :=
  if owner < 0x1000000 then some ((c.toByte.toUInt32 <<< 24) ||| owner) else none

def splitClassOwner (w : UInt32) : Option (Class × UInt32) :=
  (Class.ofByte? (w >>> 24).toUInt8).map fun c => (c, w &&& 0xFFFFFF)

/-- A class survives its byte. -/
theorem Class.ofByte_toByte (c : Class) : Class.ofByte? c.toByte = some c := by
  cases c <;> rfl

/-- Two classes never share a byte. -/
theorem Class.toByte_injective : Function.Injective Class.toByte := by
  intro a b h
  have := congrArg Class.ofByte? h
  rw [Class.ofByte_toByte, Class.ofByte_toByte] at this
  exact Option.some.inj this

/-- The list names every class once, so the emitters cannot leave one out. -/
theorem Class.all_complete (c : Class) : c ∈ Class.all := by
  cases c <;> simp [Class.all]

theorem Class.all_nodup : Class.all.Nodup := by decide

/-- Whatever `ofByte?` accepts, `toByte` gives the byte back: no byte has two readings. -/
theorem Class.toByte_ofByte (b : UInt8) (c : Class) (h : Class.ofByte? b = some c) : c.toByte = b := by
  unfold Class.ofByte? at h
  split at h <;> first | (cases h; rfl) | cases h

/-- A byte that is not a class decodes to nothing. -/
theorem Class.ofByte_none (b : UInt8) (h : b ∉ Class.all.map Class.toByte) : Class.ofByte? b = none := by
  cases hb : Class.ofByte? b with
  | none => rfl
  | some c =>
    exact absurd (by simpa [Class.toByte_ofByte b c hb] using List.mem_map_of_mem (f := Class.toByte) (Class.all_complete c)) h

/-- Class and owner survive the field, for every class and every 24-bit owner. -/
theorem splitClassOwner_classOwner (c : Class) (o : UInt32) (h : o < 0x1000000) :
    ∃ w, classOwner c o = some w ∧ splitClassOwner w = some (c, o) := by
  refine ⟨(c.toByte.toUInt32 <<< 24) ||| o, by simp [classOwner, h], ?_⟩
  have key : (((c.toByte.toUInt32 <<< 24) ||| o) >>> 24).toUInt8 = c.toByte := by
    cases c <;> simp [Class.toByte] <;> bv_decide
  have low : (((c.toByte.toUInt32 <<< 24) ||| o) &&& 0xFFFFFF) = o := by
    cases c <;> simp [Class.toByte] <;> bv_decide
  simp [splitClassOwner, key, low, Class.ofByte_toByte]

/-- A packet whose class byte is not listed is refused, whatever its owner. -/
theorem splitClassOwner_unlisted (w : UInt32) (h : (w >>> 24).toUInt8 ∉ Class.all.map Class.toByte) :
    splitClassOwner w = none := by
  simp [splitClassOwner, Class.ofByte_none _ h]

-- Written down, not derived: these numbers are on the wire, so a change to one must fail the build.
#guard Class.all.map Class.toByte == [0, 1, 2, 3, 4, 5, 6, 7, 128]
#guard (List.range 256).all fun n => (Class.ofByte? n.toUInt8).isSome == (n ∈ [0, 1, 2, 3, 4, 5, 6, 7, 128])
#guard splitClassOwner 0x80000009 == some (.command, 9)
#guard splitClassOwner 0x09000001 == none
#guard classOwner .avatar 0x1000000 == none
#guard classOwner .prop 7 == some 0x04000007

/-! ### The `command` class reads the packet differently

A command has no position, velocity, acceleration or rotation, so those bytes carry its data. The fields that every
class shares stay where they are: `gid`, `hlc`, `classOwner`, `subIndex` and the reserved tail. Data is the bytes
`COMMAND_DATA_A_OFF ..+ COMMAND_DATA_A_LEN` followed by `COMMAND_DATA_B_OFF ..+ COMMAND_DATA_B_LEN`, read as one run.
`subIndex` is split in two: the low 16 bits are the command type and the high 16 bits are how many bytes of the run
are used. -/
def COMMAND_DATA_A_OFF : Nat := 4
def COMMAND_DATA_A_LEN : Nat := 36
def COMMAND_DATA_B_OFF : Nat := 56
def COMMAND_DATA_B_LEN : Nat := 42
def COMMAND_DATA_LEN : Nat := COMMAND_DATA_A_LEN + COMMAND_DATA_B_LEN

-- The two runs stay clear of the shared fields (gid 0-3, hlc 40-47, class_owner 48-51, sub_index 52-55, reserved 98-99).
#guard COMMAND_DATA_LEN == 78
#guard COMMAND_DATA_A_OFF + COMMAND_DATA_A_LEN == 40
#guard COMMAND_DATA_B_OFF + COMMAND_DATA_B_LEN == 98
#guard COMMAND_DATA_A_OFF >= 4 && COMMAND_DATA_B_OFF >= 56

def commandSubIndex (type used : UInt32) : Option UInt32 :=
  if type < 0x10000 && used <= COMMAND_DATA_LEN.toUInt32 then some ((used <<< 16) ||| type) else none

def splitCommandSubIndex (w : UInt32) : Option (UInt32 × UInt32) :=
  if (w >>> 16) <= COMMAND_DATA_LEN.toUInt32 then some (w &&& 0xFFFF, w >>> 16) else none

#guard commandSubIndex 101 78 == some 0x004E0065
#guard commandSubIndex 101 79 == none
#guard commandSubIndex 0x10000 1 == none
#guard splitCommandSubIndex 0x004E0065 == some (101, 78)
#guard splitCommandSubIndex 0x004F0065 == none

theorem commandSubIndex_roundtrip (t u : UInt32) (h : t < 0x10000) (hu : u ≤ 78) :
    ∃ w, commandSubIndex t u = some w ∧ splitCommandSubIndex w = some (t, u) := by
  refine ⟨(u <<< 16) ||| t, by simp [commandSubIndex, COMMAND_DATA_LEN, COMMAND_DATA_A_LEN, COMMAND_DATA_B_LEN, h, hu], ?_⟩
  have h1 : (((u <<< 16) ||| t) >>> 16) = u := by bv_decide
  have h2 : (((u <<< 16) ||| t) &&& 0xFFFF) = t := by bv_decide
  simp [splitCommandSubIndex, h1, h2, COMMAND_DATA_LEN, COMMAND_DATA_A_LEN, COMMAND_DATA_B_LEN, hu]

/-- The class names as the emitters write them: the constructor name in snake case, upper case for C. -/
def Class.cName : Class → String
  | .unset => "unset" | .avatar => "avatar" | .trackedPart => "tracked_part" | .persona => "persona"
  | .prop => "prop" | .camera => "camera" | .light => "light" | .node => "node" | .command => "command"

private def upper (s : String) : String := s.map Char.toUpper

/-- C: one `#define` per class, read off the same list the proofs are about. -/
def classesC : String :=
  "/* class byte of class_owner: (class << 24) | owner. A byte not listed here is not a class; drop the packet. */\n" ++
  String.intercalate "\n" (Class.all.map fun c => s!"#define XR_PACKET_CLASS_{upper c.cName} {c.toByte.toNat}") ++ "\n" ++
  s!"/* the command class: data runs at {COMMAND_DATA_A_OFF} (len {COMMAND_DATA_A_LEN}) and {COMMAND_DATA_B_OFF} (len {COMMAND_DATA_B_LEN}); sub_index = (used << 16) | type */\n" ++
  s!"#define XR_PACKET_COMMAND_DATA_A_OFF {COMMAND_DATA_A_OFF}\n#define XR_PACKET_COMMAND_DATA_A_LEN {COMMAND_DATA_A_LEN}\n" ++
  s!"#define XR_PACKET_COMMAND_DATA_B_OFF {COMMAND_DATA_B_OFF}\n#define XR_PACKET_COMMAND_DATA_B_LEN {COMMAND_DATA_B_LEN}\n"

/-- Python: an `IntEnum`, and the two functions that split and make the field. -/
def classesPy : String :=
  "class Class(IntEnum):\n" ++
  "    \"\"\"The class byte of class_owner, (class << 24) | owner. A byte not listed is not a class: drop the packet.\"\"\"\n" ++
  String.intercalate "\n" (Class.all.map fun c => s!"    {upper c.cName} = {c.toByte.toNat}") ++ "\n\n" ++
  s!"# the command class: data runs at {COMMAND_DATA_A_OFF} and {COMMAND_DATA_B_OFF}; sub_index = (used << 16) | type\n" ++
  s!"COMMAND_DATA_A_OFF = {COMMAND_DATA_A_OFF}\nCOMMAND_DATA_A_LEN = {COMMAND_DATA_A_LEN}\n" ++
  s!"COMMAND_DATA_B_OFF = {COMMAND_DATA_B_OFF}\nCOMMAND_DATA_B_LEN = {COMMAND_DATA_B_LEN}\n"

end EntityPacket
