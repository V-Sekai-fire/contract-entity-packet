# contract-entity-packet

The Lean 4 source of truth for the fabric's fixed-size, all-integral entity packet, with property tests and emitted codecs.

## Layout

Bytes 0-3 `gid`, 4-27 position (three Int64, micrometres), 28-33 `vel` (three Int16 against `V_MAX_UM_PER_TICK`), 34-39 `accel` (three Int16 against `A_MAX_UM_PER_TICK2`, twice the velocity scale, micrometres per tick squared), 40-43 `hlc`, 44-47 `class_owner`, 48-51 `sub_index`, 52-57 `rot`, 58-97 payload (40 bytes), 98-99 reserved. Senders write zero to the reserved bytes and receivers ignore them. There is no version field: the dev stage has no backwards compatibility requirement.

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
