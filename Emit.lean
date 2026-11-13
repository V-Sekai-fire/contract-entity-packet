import EntityPacket.Gen
import EntityPacket.EmitC
import EntityPacket.EmitPy
import EntityPacket.EmitPredict
open EntityPacket

-- Three outputs, and they are the same claim three times.
--
-- `packet_golden.csv` says what the bytes are for 64 known packets; `xr_grid_entity_packet.h`
-- says how to make them in C and `xr_grid_entity_packet.py` how to make them in Python.
-- Emitting all of them from one run is what lets `test/golden.c` and the Python pair's
-- conformance gate hold the codecs to the first: a codec generated from the spec is a claim
-- about provenance, and only the golden vectors make it a claim about bytes.
--
-- The Python codec exists because a second implementation of the wire is worth nothing if it
-- reads the layout off the same table by hand. See EmitPy.lean.
def main : IO Unit := do
  IO.FS.createDirAll "build"
  let mut out := s!"hex,gid,pumx,pumy,pumz,velx,vely,velz,accx,accy,accz,pay0,pay{PAYLOAD_LEN - 1}\n"
  for n in [0:64] do
    let p := mk n
    let b := encode p
    out := out ++ s!"{hex b},{p.gid},{p.posUm.1},{p.posUm.2.1},{p.posUm.2.2},{p.vel.1},{p.vel.2.1},{p.vel.2.2},{p.accel.1},{p.accel.2.1},{p.accel.2.2},{p.payload[0]!},{p.payload[PAYLOAD_LEN - 1]!}\n"
  IO.FS.writeFile "build/packet_golden.csv" out
  IO.println s!"wrote build/packet_golden.csv (64 vectors)"

  let mut full := "hex,gid,pumx,pumy,pumz,velx,vely,velz,accx,accy,accz,hlc,class_owner,sub_index,rotx,roty,rotz,payload\n"
  for n in [0:64] do
    let p := mk n
    full := full ++ s!"{hex (encode p)},{p.gid},{p.posUm.1},{p.posUm.2.1},{p.posUm.2.2},{p.vel.1},{p.vel.2.1},{p.vel.2.2},{p.accel.1},{p.accel.2.1},{p.accel.2.2},{p.hlc},{p.classOwner},{p.subIndex},{p.rot.1},{p.rot.2.1},{p.rot.2.2},{hex p.payload}\n"
  IO.FS.writeFile "build/packet_golden_full.csv" full
  IO.println s!"wrote build/packet_golden_full.csv (64 vectors, every field)"

  IO.FS.writeFile "build/xr_grid_entity_packet.h" cHeader
  IO.println s!"wrote build/xr_grid_entity_packet.h ({SIZE} bytes, payload at {PAYLOAD_OFFSET})"

  IO.FS.writeFile "build/xr_grid_entity_packet.py" pyModule
  IO.println s!"wrote build/xr_grid_entity_packet.py ({SIZE} bytes, payload at {PAYLOAD_OFFSET})"
  IO.FS.writeFile "build/entity_predict.h" predictHeader
  IO.println "wrote build/entity_predict.h (makima displacement kernel, 128 bit products)"
  IO.FS.writeFile "build/predict_golden.csv" predictGolden
  IO.println "wrote build/predict_golden.csv (512 vectors)"
