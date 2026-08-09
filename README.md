# HyperBus / HyperRAM model

This project provides a cycle-scheduled HyperRAM slave model: a SystemVerilog
pin wrapper (`hyperram/hyperram.sv`) backed by a C++ protocol and memory core.
The `tb.sv` testbench compares basic transactions with the included Infineon
reference model and adds directed checks for model-specific behavior.

## Run

```sh
CCACHE_DISABLE=1 make run
CCACHE_DISABLE=1 make test-read-stall
```

`CCACHE_DISABLE=1` avoids a host-specific ccache filesystem issue.
`test-read-stall` is a standalone deterministic fixture for the optional
inter-word refresh-collision behavior.

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
