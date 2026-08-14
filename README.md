# HyperBus / HyperRAM model

This project provides cycle-scheduled C++ HyperRAM slave and controller
models, each exposed through a SystemVerilog pin wrapper. The directed tests
exercise the C++ protocol and memory cores.

## Run

```sh
CCACHE_DISABLE=1 make run
CCACHE_DISABLE=1 make test-read-stall
CCACHE_DISABLE=1 make test-random
CCACHE_DISABLE=1 make test-controller
CCACHE_DISABLE=1 make test-controller-zero-latency
CCACHE_DISABLE=1 make test-controller-read-stall
CCACHE_DISABLE=1 make test-controller-read-timing
CCACHE_DISABLE=1 make test-controller-read-error
CCACHE_DISABLE=1 make test-controller-geometry
CCACHE_DISABLE=1 make test-controller-timing
# Run the complete directed, stall, and randomized suite.
CCACHE_DISABLE=1 make test
```

`CCACHE_DISABLE=1` avoids a host-specific ccache filesystem issue.
`test-read-stall` is a standalone deterministic fixture for the optional
inter-word refresh-collision behavior. `test-random` executes 24
deterministic randomized, variable-length normal-latency write bursts with
minimal CS# gaps and checks every touched word against the C++ model.

`test-controller` brings up the new controller transaction shell with the
HyperRAM slave on shared pins. `test-controller-zero-latency` validates a
profile whose memory-write data begins immediately after CA and does not use
RWDS byte masks. `test-controller-read-stall` validates a refresh-collision
inter-word RWDS stall. `test-controller-read-timing` validates qualified RWDS
sampling with DQ intentionally delayed relative to the strobe.
`test-controller-read-error` injects missing read strobes and verifies safe
controller recovery without publishing partial data.
`test-controller-geometry` verifies finite-memory boundary handling and
pre-pin out-of-range rejection.
`test-controller-timing` checks non-default CS#, CK, and turnaround timing
deadlines. The complete `make test` target includes all directed tests.

## Controller model scaffold

`controller/hyperbus_controller.sv` is the SystemVerilog wrapper for the new
cycle-scheduled C++ master core in `controller/hyperbus_controller_model.cpp`.
It uses `clk` for the simple request/response interface and `clk_4x` for
future pin scheduling. Its intentionally small interface provides:

- a request channel (`request_*`) describing read/write, memory/register
  space, linear/wrapped mode, address, and word count;
- streaming write-data/mask and read-data channels; and
- a response channel with an explicit error bit.

At this stage, aligned linear memory bursts emit one CA sequence, select normal
or additional fixed latency from CA RWDS, and transfer any positive number of
RWDS-framed 16-bit words through the simple read/response channels. Equivalent
Normal-latency writes drive an RWDS-low preamble followed by masked DDR data;
profiles that enable zero-latency memory/register writes instead start data
directly after CA with profile-controlled RWDS ownership.
The controller can pause CK between payload words when its local read or write
channel stalls, selects HyperRAM register space with CA[46], and derives its
initial latency from a CR0 shadow updated by successful CR0 writes. It also
selects linear versus wrapped/hybrid slave addressing with CA[45]. Malformed
length/alignment requests receive distinct validation errors. The full
interface contract is documented in `controller/README.md`.

## Implemented behavior

- Single-ended or validated differential `CK`/`CK#` operation.
- Six-byte CA capture; memory/register space, read/write, linear, wrapped,
  and hybrid bursts.
- CR0/CR1 plus ID register access, masked register writes, and read-only IDs.
- Fixed and initial variable latency, refresh-driven additional latency, and
  optional refresh-collision stalls between completed read words.
- DDR word writes with per-byte RWDS masks, including all-masked word address
  progression; profile-controlled zero-latency writes.
- Reset recovery, deep power-down, hybrid sleep, CS# recovery, clock framing,
  and 4×-tick CA/write setup and hold checks.
- Profile-controlled finite memory density with wrap or strict rejection.
- Independent DQ data-valid, RWDS strobe, output-enable/disable, clock-duty,
  and CA/write setup/hold timing values.

## Main `hyperram` configuration parameters

| Parameter group | Purpose |
|---|---|
| `IDENTIFICATION_*`, `CONFIGURATION_*` | Device ID and volatile register reset values. |
| `FIXED_LATENCY_RWDS_HIGH`, `VARIABLE_LATENCY_SUPPORTED` | Initial-latency policy. |
| `REFRESH_*`, `INTER_WORD_*` | Refresh scheduling and optional read-burst stalls. |
| `ZERO_LATENCY_*` | Supported zero-latency write modes. |
| `T_RWR_*`, `T_CSS_*`, `T_*_SETUP/HOLD_*` | Transaction and sampled-input timing, in 4× ticks. |
| `T_CK_HIGH_MIN_4X_TICKS`, `T_CK_LOW_MIN_4X_TICKS` | Minimum CK high/low phase widths while CS# is Low; zero disables each check. |
| `DIFFERENTIAL_CLOCK_MODE` | Selects complementary `CK`/`CK#` validation; `0` selects single-ended CK. |
| `MEMORY_DENSITY_BYTES`, `ADDRESS_ROLLOVER` | Finite memory geometry; zero density is unbounded. |
| `T_*OUTPUT*`, `T_DQ_DATA_VALID_DELAY`, `T_RWDS_STROBE_DELAY` | Physical output timing at the SV pins. |
| `*_POWER_DOWN_*`, `*_HYBRID_SLEEP_*` | Low-power feature enable and timing. |

## Current limits

Timing checks are quantized to the 4× scheduler. The model does not yet
provide exhaustive reserved-CA validation or every device-specific register
definition. `TODO.md` tracks these remaining items.

### Clocking and turnaround timing

During an active transaction, each CK phase can be qualified with
`T_CK_HIGH_MIN_4X_TICKS` and `T_CK_LOW_MIN_4X_TICKS`. A phase shorter than
the configured minimum is rejected as a clock protocol error; a zero setting
leaves the phase unconstrained. CA and write input setup/hold use their
separate `T_CA_*` and `T_WRITE_*` controls. At the pin boundary, DQ and RWDS
ownership/data are independently delayed using the `T_*OUTPUT*`,
`T_DQ_DATA_VALID_DELAY`, and `T_RWDS_STROBE_DELAY` parameters. This models
the CA-to-write RWDS release, read DQ/RWDS ownership, and CS# output release
without conflating logical protocol state with physical pin delay.

### Inter-word read stalls

When `VARIABLE_LATENCY_SUPPORTED`,
`INTER_WORD_VARIABLE_LATENCY_SUPPORTED`, and a nonzero
`INTER_WORD_STALL_EDGES` are enabled, a refresh collision after Byte B of a
read word enters a stall. DQ remains at the previous byte, RWDS is held High
for the configured number of DDR edges, and the next word resumes with a
Low-RWDS idle phase followed by Byte A. Address progression occurs only after
the complete preceding word.

### Protocol diagnostics

The model records every rejected protocol condition in a cumulative counter
and retains the most recent diagnostic. These DPI-C functions are intended
for testbenches and scoreboards:

| Function | Result |
|---|---|
| `hyperram_model_protocol_errors()` | Cumulative number of rejected conditions since reset. |
| `hyperram_model_last_error_code()` | Most recent error category, using the values below. |
| `hyperram_model_last_error_tick()` | 4× scheduler tick at which that error was observed. |
| `hyperram_model_last_error_address()` | Related HyperBus address, or `32'hffff_ffff` when the condition has no address. |

| Code | Category |
|---:|---|
| 0 | No error since reset |
| 1 | Invalid clock or `CK`/`CK#` pair |
| 2 | Invalid CS# assertion/deassertion framing |
| 3 | Transaction timing or DDR-edge ordering violation |
| 4 | CA/write setup or hold violation |
| 5 | Transaction ended after only Byte A of a word |
| 6 | Unsupported register-space command/address |
| 7 | Attempt to write a read-only register |
| 8 | Strict finite-memory address outside the configured density |
| 9 | Transaction attempted while a low-power/recovery state rejects traffic |

An error does not terminate simulation. The slave either continues at the
defined safe boundary or ignores the unsupported transaction, letting the
testbench report the rejected condition without masking later failures.

## Verification

`tb.sv` contains directed checks for CA decoding, register reads/writes,
initial and refresh-selected latency, all normal-latency byte-mask
combinations, linear/wrapped/hybrid bursts, zero-latency writes, reset, deep
power-down, hybrid sleep, clock framing, finite-memory behavior, and pin
turnaround. It also contains immediate assertions for logical bus ownership
and read-RWDS edge alignment, plus state/transition coverage that requires
all reset, DPD, and hybrid-sleep arcs to be observed.

The directed tests check the C++ model's RWDS ownership and normal-latency
write-mask handling directly.
