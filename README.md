# contract-entity-packet

The Lean 4 source of truth for the fabric's fixed-size, all-integral entity packet, with property tests and emitted codecs.

## Layout

Bytes 0-3 `gid`, 4-27 position (three Int64, micrometres), 28-33 `vel` (three Int16 against `V_MAX_UM_PER_TICK`), 34-39 `accel` (three Int16 against `A_MAX_UM_PER_TICK2`, twice the velocity scale, micrometres per tick squared), 40-43 `hlc`, 44-47 `class_owner`, 48-51 `sub_index`, 52-57 `rot`, 58-97 payload (40 bytes), 98-99 reserved. Senders write zero to the reserved bytes and receivers ignore them. There is no version field: the dev stage has no backwards compatibility requirement.

## Classes

The top byte of `class_owner` is a class, and the low 24 bits are the owner. `EntityPacket/Classes.lean` lists the classes once; the C header and the Python module are emitted from that list. A byte that is not listed is not a class, and a receiver drops the packet.

| Byte | Class | What it is | `sub_index` |
|---|---|---|---|
| 0 | `unset` | never a real packet; a zeroed buffer | 0 |
| 1 | `avatar` | a player's avatar root | 0 |
| 2 | `tracked_part` | head, hands, hips of a player | the part |
| 3 | `pedestrian` | a simulated walker that is not a player | 0 |
| 4 | `prop` | a moving thing with a mesh; the payload names the mesh and scale | the part, 0 is the whole |
| 5 | `camera` | a camera | 0 |
| 6 | `light` | a light | 0 |
| 7 | `node` | a transform with nothing to draw | 0 |
| 128 | `command` | a command that fits in one packet | the command type |

The numbers are the contract: never reuse or renumber one, only append. The proofs show that a class survives its byte, that no byte has two readings, that class and owner survive the field for every 24 bit owner, and that an unlisted byte decodes to nothing. `#guard` lines pin the numbers so that renumbering one fails the build.

## What it is for

The packet carries no floats, so Lean models it exactly and Plausible roundtrip properties find codec gaps without an engine rebuild. `EntityPacket/Codec.lean` names each offset once; the encoder, the decoder and the C and Python emitters all read it. The emitted `xr_grid_entity_packet.h` and `xr_grid_entity_packet.py` are committed so a repository that vendors this one gets a codec without running Lean. Edit `Codec.lean` and replace them with what `packet_emit` writes rather than editing either by hand. `packet_golden.csv` and `packet_golden_full.csv` are committed the same way: 64 known packets as hex, the second with a column for every field, checked by `lake exe golden_check`.

## Prediction kernel

`EntityPacket/Predict.lean` is a dead-reckoning kernel in whole numbers: the Makima curve through the `vel` samples of an acked snapshot at ticks L-2, L-1 and L and the packet's own at L+lag, summed over the lag, in micrometres. `entity_predict.h` is emitted from it, with 128 bit products. It does not change the wire. A decoder that uses it holds three acked snapshots of `vel` per entity per client. `lake exe predict_check` runs its properties.

## Build, test and emit

```sh
lake exe packet_demo
lake exe packet_emit
```

`VERIFY.md` holds the differentials that keep the C codec, the Python codec and the engine in agreement with this specification.

## Licence

MIT; see `LICENSE`.
