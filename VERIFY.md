# Verifying the packet

Moved out of `README.md` when the forty-line rule went in. The README states the layout; this
page is how you check that everything downstream still agrees with it.

```sh
lake exe packet_demo    # Plausible roundtrip + size, 50000-vector sweep
lake exe packet_emit    # writes packet_golden.csv and the C and Python codecs

# the committed copies must be the ones the emitter writes
diff packet_golden.csv build/packet_golden.csv
diff packet_golden_full.csv build/packet_golden_full.csv
diff xr_grid_entity_packet.h build/xr_grid_entity_packet.h
diff xr_grid_entity_packet.py build/xr_grid_entity_packet.py

# differential: the C the emitter wrote must produce the Lean bytes
cc -std=c11 -I build test/golden.c -o build/golden
./build/golden build/packet_golden.csv     # PACKET DIFFERENTIAL PASS

# every field of every golden row: decode the hex, compare, encode back
lake exe golden_check                      # golden_check: PASS
lake exe golden_check plant                # must fail: one bit flipped in row 0

# differential: the engine's C++ XRGridEntityPacket.decode must match
godot --headless --script packet_diff.gd   # PACKET DIFFERENTIAL PASS

# differential: the Python the emitter wrote, run where it is vendored
cd ../../1-transport/ingest-python && pixi run check   # 64/64
```

Last run: Plausible clean, 50000/50000 roundtrip, the C++ decode matching the spec on 64
golden vectors, and the emitted C and Python encoders each matching all 64 byte for byte.

The two differentials are the point rather than the roundtrip. A roundtrip closing proves the
encoder and decoder here are inverses of each other; it says nothing about whether the engine
that has to read these bytes agrees. Assert the property where it is consumed.

## Golden rows with every field

`packet_golden.csv` lists the position, velocity and acceleration of each packet and two payload bytes. Other repositories read it by column position, so its columns and its 64 rows do not change. `packet_golden_full.csv` is a second file from the same run of `packet_emit`, with the same 64 packets in the same order and the same `hex`, and one column for every field of `Packet`:

`hex,gid,pumx,pumy,pumz,velx,vely,velz,accx,accy,accz,hlc,class_owner,sub_index,rotx,roty,rotz,payload`

`payload` is the 40 payload bytes as 80 lowercase hex characters. `rotx`, `roty` and `rotz` are the three wire slots in order (swing X, swing Z, twist about Y), as `SWING_TWIST.md` describes. The two reserved bytes are not a column; they are the last four characters of `hex` and are zero.

`lake exe golden_check [path]` reads the committed file, or the path it is given. For each row it decodes `hex`, compares each decoded field with the text in its column (the decimal text must be equal, so a leading zero or a plus sign is a failure), compares the payload, encodes the decoded packet and compares the result with `hex`. The last step is what catches a nonzero reserved byte. It also requires the header row, 64 rows, and that row `n` holds the `hex` of the generator's packet `n`. The check has its own list of the columns and does not share a formatter with the emitter, so a column written in the wrong order by one of them is a failure.

The control: on a passing file it flips each of the 800 bits of each row's `hex` in turn, 51,200 flips, and each one must be rejected. `lake exe golden_check plant` flips one bit (bit 0 of the first `rot` byte of row 0) before the check and must exit with status 1.

All 18 columns take 64 different values in the 64 rows, so no field is constant. The coverage is narrow: `gid`, `hlc`, `class_owner` and `sub_index` stay under 446, so their upper two bytes are zero in every row, and `vel`, `accel` and `rot` stay within 72 codes of -32767, so no row holds a positive Int16. The generator is not changed here, because a change would change `packet_golden.csv`.

The swing-twist converters have their own check, `lake exe rot_check`, described in `SWING_TWIST.md`.
