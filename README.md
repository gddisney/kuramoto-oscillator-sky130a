# jev_kuramoto

`jev_kuramoto` is a hardened hard macro for SkyWater SKY130 (`sky130_fd_sc_hd`). This package contains two views:

| File | What it is |
|---|---|
| `jev_kuramoto.lef` | Abstract physical view (LEF 5.7) for place and route |
| `jev_kuramoto.vh` | Verilog blackbox. Its signal ports match `rtl/jev_kuramoto.v` |
| `jev_kuramoto.v` / `jev_kuramoto.vhd` | Generated RTL in Verilog and VHDL |
| `jev_kuramoto_tb.v` / `jev_kuramoto_tb.vhd` | Self-checking testbenches (16 golden vectors) |
| `kuramoto_mesh.wgsl` | WebGPU reference model of the Kuramoto clock mesh |

## Macro summary

| Property | Value |
|---|---|
| Class | `BLOCK` |
| Size | 548.32 µm × 560.32 µm (origin 0, 0) |
| Signal pins | 140 (43 input bits, 97 output bits) |
| Power | `VPWR` and `VGND`, 6 vertical met4 straps each, running y = 10.64 to 549.68 µm |
| Pin layers | met2 on the north (36) and south (64) edges, met3 on the east (29) and west (11) edges |
| Obstructions | nwell, li1, and met1 cover the core. met2 to met5 are partly blocked; see `OBS` in the LEF |

## Ports

| Port | Dir | Width | Notes |
|---|---|---|---|
| `clk` | in | 1 | Clock |
| `rst` | in | 1 | Reset |
| `src0` to `src3` | in | 1 each | Four source inputs |
| `src_en` | in | 4 | Enable for each source |
| `omega_we` | in | 1 | Write enable for `omega_d` |
| `omega_d` | in | 32 | Write data for omega (frequency) |
| `phase_out` | out | 32 | Phase value |
| `freq_out` | out | 32 | Frequency value |
| `wrap` | out | 4 | Phase-wrap flag for each source |
| `near` | out | 6 | Close-enough phase flags (6 bits) |
| `fault` | out | 4 | Fault flag for each source |
| `lost` | out | 4 | Lost flag for each source |
| `locked` | out | 4 | Locked flag for each source |
| `glitch` | out | 4 | Glitch flag for each source |
| `coherent` | out | 1 | Group coherence flag |
| `quorum` | out | 1 | Quorum flag |
| `ec_tick` | out | 1 | Tick output |
| `status` | out | 4 | Status word |
| `VPWR`, `VGND` | inout | 1 | Only when `USE_POWER_PINS` is defined |

<img width="2400" height="2500" alt="image" src="https://github.com/user-attachments/assets/3e87b4c5-d055-4208-ad92-d122f773ebaa" />


## How it works

This section was traced from the gate netlist in `jev_kuramoto.v`. Phases are 32-bit, so one full turn is 2^32.

**Four oscillator nodes.** Each node has a phase `th` and a frequency `om`. Every clock, the phase advances by `om`, plus a phase correction from its neighbors and from its external source. After reset, the phases are 0, 5/16, 10/16, and 15/16 of a turn. The frequencies are `10000000`, `10F5C28F`, `0F333333`, and `107AE148`, which works out to about one turn per 16 clocks with a few percent spread. Writing `omega_we`/`omega_d` loads a new frequency into all four nodes (`om`).

**Coupling.** Each node adds 1/16 of the signed, wrapped phase error to every neighbor it listens to, and 1/256 of that error to its frequency. That makes it a second-order (phase plus frequency) loop. The coupling is linear in the wrapped error, not a sine. If a node is ahead of every neighbor it isn't near, and it isn't locked to a source, it advances at half speed (`sl`) so the others can catch up.

**External sources.** Each `src` input goes through a 3-flop synchronizer, and its rising edge is detected. When `src_en` is set, an edge is accepted if the node's phase is within a quarter turn of zero, or if the node isn't locked yet. An accepted edge pulls the phase 1/4 of the way to zero and the frequency by 1/256 of the error.
- `locked` sets when an accepted edge lands within 1/16 turn of zero. It clears when the source is lost.
- `lost` fires after 255 clocks without an accepted edge.
- `glitch` fires when a locked node sees an edge more than a quarter turn off. That edge is rejected.

**Health and voting.**
- `near` holds 6 bits, one per node pair (01, 02, 03, 12, 13, 23). A bit is set when that pair is within 1/16 turn (22.5 degrees).
- `quorum` means some three nodes are all near each other.
- `coherent` means all six pairs are near.
- `fault[i]` means a quorum exists and node i is near nobody.

**Self-repair.** The `jev_listen` ROMs pick each node's neighbors from the fault vector, so a faulty node is dropped from everyone's coupling. A node that is locked to its own source ignores its neighbors. The `jev_strobe` ROM picks the lowest-numbered healthy node as the clock master. If all four nodes are faulty, it holds.

**Outputs.**
- `wrap[i]` pulses when node i's phase passes a full turn.
- `ec_tick` is the master node's wrap, gated by quorum. It's the fault-tolerant clock tick.
- `phase_out` and `freq_out` show node 0.
- `status` is registered, so it lags one clock. Its bits are `{ec_tick, any fault, any lost, quorum}`, from bit 3 down to bit 0.

## RTL

The RTL comes from the WASMApollo EDA (heapvm vgpu apollo), generated from the typed fabric `jev_kuramoto`. The Verilog and VHDL are the same design.

| Property | Value |
|---|---|
| LUT4 cells | 151 |
| Word PEs | 584 |
| Registers | 62 |
| Combinational depth | 10 levels |
| Clocking | Single `clk`. Every register latches on the rising edge from the settled levels |
| Reset | `rst` is synchronous, active high, and loads the fabric's initial state |

### Microcode ROMs

The fabric includes five small controller ROMs. Each maps a 4-bit controller state to a 3-bit select code (LSB first).

- `jev_listen0` to `jev_listen3`: one per source. States 0 to 6 select the subsets `abc, bc, ac, c, ab, b, a`, with codes `111` down to `001`. States 7 to 15 select `none` (`000`).
- `jev_strobe`: a strobe pattern over 16 states, n0 n1 n0 n2 n0 n1 n0 n3, repeated, with state 15 = `hold` (`100`).

## Simulation

Both testbenches are self-checking. Each vector holds `rst` for one cycle, runs 64 cycles, and then compares every output against the fabric's golden model (RefSim).

```sh
# Verilog (Icarus)
iverilog -o tb jev_kuramoto.v jev_kuramoto_tb.v && vvp tb
# expected: PASS jev_kuramoto: 16 vectors

# VHDL (GHDL)
ghdl -a jev_kuramoto.vhd jev_kuramoto_tb.vhd && ghdl -e jev_kuramoto_tb && ghdl -r jev_kuramoto_tb
```

The Verilog testbench was run with Icarus Verilog and passes all 16 vectors. The VHDL testbench has not been run yet.

## Reference model (`kuramoto_mesh.wgsl`)

`kuramoto_mesh.wgsl` is a WebGPU compute kernel that simulates the clocking idea behind the macro. It runs in software. It is not the RTL. Every logic node has its own local clock phase \(\theta_i\). Kuramoto coupling pulls that phase toward the other nodes, and the node's own advance slows down while the group is out of phase. A node is safe to latch once the coherence reaches a threshold.

Each step computes:

```
r      = |(1/N) * sum_j e^{i*theta_j}|           # phase coherence, 0..1
S_i    = 1 / (1 + decel * (1 - r))              # slow down while incoherent
theta' = theta_i + dt * (omega_i * S_i + (Kc/N) * sum_j sin(theta_j - theta_i))
```

| Entry point | What it does |
|---|---|
| `step` | Reads `theta_in`, writes `theta_out`, so every node steps from the same snapshot |
| `commit` | Copies `theta_out` back to `theta_in` (ping-pong) |

| Binding / override | Meaning | Default |
|---|---|---|
| `@binding(0) theta_in` | Current phases (rad) | n/a |
| `@binding(1) theta_out` | Next phases (rad) | n/a |
| `@binding(2) omega` | Natural frequency for each node | n/a |
| `N` | Node count | `0` (must be set) |
| `kc` | Coupling strength | `0.0` |
| `dt` | Integration step | `0.02` |
| `decel` | Gain for the slowing term | `8.0` |

To run it, dispatch `step` and then `commit` once per time step, each with `ceil(N/64)` workgroups. Read back `theta_in` to compute `r`.

Notes:
- The mesh is all-to-all, so `r` is the global coherence and every node's latch opens at the same moment. A real netlist would couple each node only to its predecessors.
- Each step costs O(N²), because every node loops over all N phases. That's fine for a few thousand nodes. Larger meshes should compute `sum cos` and `sum sin` once per step and reuse them, which makes it O(N), since \(\sum_j \sin(\theta_j-\theta_i)\) can be written from those two sums.
- Phases are never wrapped back into \([-\pi,\pi)\). In `f32` they lose precision over long runs, so wrap them in `commit`.
- With the defaults `kc = 0.0` and `N = 0`, nothing happens. Set both.
- The mapping from this model to the macro's four `src` inputs and its `locked`, `near`, `coherent`, and `quorum` flags isn't spelled out in these files. `jev_kuramoto.v` is the source of truth.

## Using the macro

### In RTL

```verilog
`include "jev_kuramoto.vh"

jev_kuramoto u_jev (
`ifdef USE_POWER_PINS
  .VPWR(vccd1),
  .VGND(vssd1),
`endif
  .clk(clk), .rst(rst),
  .src0(s0), .src1(s1), .src2(s2), .src3(s3),
  .src_en(src_en),
  .omega_we(omega_we), .omega_d(omega_d),
  .phase_out(phase_out), .freq_out(freq_out),
  .wrap(wrap), .near(near), .fault(fault), .lost(lost),
  .locked(locked), .glitch(glitch),
  .coherent(coherent), .quorum(quorum), .ec_tick(ec_tick),
  .status(status)
);
```

Define `USE_POWER_PINS` for power-aware simulation and LVS. Leave it undefined for plain RTL simulation.

### In OpenLane / OpenROAD

Add the LEF and blackbox to your top-level config, for example:

```json
"EXTRA_LEFS": ["dir::macros/jev_kuramoto.lef"],
"EXTRA_GDS_FILES": ["dir::macros/jev_kuramoto.gds"],
"VERILOG_FILES_BLACKBOX": ["dir::macros/jev_kuramoto.vh"]
```

Then connect `VPWR` and `VGND` to the power grid through the met4 straps. The GDS is not part of this package, so you need it from the hardening run before you can stream out.

## Other PDKs

The `VPWR`/`VGND` names belong to the hardened SKY130 view. To target another public PDK, synthesize `rtl/jev_kuramoto.v` there and use that PDK's supply names. The LEF only applies to SKY130.
