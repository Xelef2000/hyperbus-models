# Controller model interface

`hyperbus_controller` is a cycle-scheduled HyperBus master model. Its current
transaction shell uses `clk` for request/response sequencing and `clk_4x` for
pin sampling and future DDR scheduling.

## Request contract

`request_valid_i` and `request_ready_o` use a standard ready/valid handshake.
The request is accepted only on a rising `clk` edge where both are High.

| Signal | Meaning |
|---|---|
| `request_write_i` | `1` for a write; `0` for a read. |
| `request_register_space_i` | `1` selects register space; `0` selects memory space. |
| `request_linear_burst_i` | `1` requests linear addressing; `0` requests wrapped addressing. |
| `request_address_i` | Byte address. It must be 16-bit-word aligned (`bit 0 = 0`). |
| `request_words_i` | Number of 16-bit words, from 1 through 65,535. |

Writes use `write_valid_i/write_ready_o`; `write_mask_i[1]` masks Byte A and
`write_mask_i[0]` masks Byte B. Reads use `read_valid_o/read_ready_i`, with
`read_last_o` marking the final word. Each payload handshake transfers exactly
one 16-bit word.

## Response contract

`response_valid_o` remains asserted until `response_ready_i` is High on a
rising `clk` edge. `response_error_o` is High for every nonzero code.

| `response_code_o` (4 bits) | Meaning |
|---:|---|
| 0 | Successful completion of an implemented linear memory transaction. |
| 1 | Valid request, but the pin-level operation is not implemented yet. |
| 2 | `request_words_i` was zero. |
| 3 | `request_address_i` was not 16-bit aligned. |
| 4 | Inter-word RWDS stall timeout. |
| 5 | Out-of-order RWDS transition during a read. |
| 6 | Missing read Byte-A or Byte-B strobe timeout. |
| 7 | Delayed DQ capture timeout. |
| 8 | Memory request exceeds a non-rolling configured capacity. |

## Implemented pin operation

An aligned, nonzero, linear memory read (`request_write_i=0`,
`request_register_space_i=0`, `request_linear_burst_i=1`) progresses through
`Idle → Validate → WaitRead → WaitPinEnd → Respond → Idle`. The controller asserts CS# while
CK is Low, drives six CA bytes on alternating CK edges with DQ stable through
each edge, releases DQ, and deasserts CS# with CK Low. The CA encodes
`request_address_i` as a byte address, converted to the HyperBus 16-bit word
address field.

The controller samples RWDS after CA. It decodes the initial-latency code in
its CR0 shadow (`CONFIGURATION_REGISTER0_RESET[7:4]` at reset): Low selects
that normal count and High selects twice that count. The count is converted
from CK cycles to DDR edges before CK continues. A successful masked write to
register-space word address `0x800` updates the CR0 shadow after that write's
data word completes, so the changed setting affects only later transactions.
The controller captures Byte A on the next RWDS rising transition and Byte B
on the following falling transition, and presents the combined word on the
read channel. `read_valid_o` remains asserted until
`read_ready_i` accepts the word. For a non-final word, CK is held Low until
that handshake and then resumes for the next word. For the final word, the
controller stops CK with the low idle polarity, deasserts CS#, and presents
response code zero.

## Implemented write operation

An aligned linear memory write follows the same CA and initial-latency
sequence. After CA, the controller takes RWDS ownership and drives it Low for
the complete latency period as the write-mask preamble. At the end of latency,
`write_ready_o` is asserted. Each `write_valid_i/write_ready_o` handshake
latches one word and its masks, then the controller drives Byte A on rising CK
and Byte B on falling CK. `write_mask_i[1]` controls Byte A and
`write_mask_i[0]` controls Byte B; a High bit masks that byte. Between words,
CK is held Low while the controller retains DQ/RWDS ownership; RWDS is held
Low until the next word is supplied. It releases both pins only after the
final word, terminates with CK Low and CS# High, then produces the successful
response.

The controller currently supports arbitrary-length linear and wrapped memory
and register-space reads and writes with configuration-controlled initial
latency. CA[45] is selected by `request_linear_burst_i`; the attached slave
uses CR0 to choose its wrapped-window size and whether a wrapped transaction
becomes hybrid (one wrapped window followed by linear addressing).
Register-space CA[46] is set from `request_register_space_i`; supported
register locations and any device-specific write effects are defined by the
attached slave profile.

## Controller configuration

| Parameter | Meaning |
|---|---|
| `CONFIGURATION_REGISTER0_RESET` | CR0 reset value used for the first transaction and restored by reset. Its latency code must match the attached HyperRAM device. |
| `IDENTIFICATION_REGISTER*_RESET`, `CONFIGURATION_REGISTER1_RESET` | Device register-reset profile, reserved for upcoming controller-side discovery and power-state handling. |
| `FIXED_LATENCY_RWDS_HIGH`, `VARIABLE_LATENCY_SUPPORTED`, `REFRESH_*` | Initial- and variable-latency/refresh profile. The controller samples CA RWDS and supports profile-gated inter-word read stalls. |
| `ZERO_LATENCY_MEMORY_WRITES`, `ZERO_LATENCY_REGISTER_WRITES`, `ZERO_LATENCY_WRITE_RWDS_LOW` | Implemented zero-latency write capability and RWDS ownership profile. |
| `T_RWR_*`, `T_CSS_*`, `T_CA_*`, `T_WRITE_*`, `T_CK_*` | Implemented controller scheduler deadlines for turnaround, CS# setup, CA/write setup/hold, and CK high/low phase widths. |
| `T_RESET_RECOVERY_*`, `*_POWER_DOWN_*`, `*_HYBRID_SLEEP_*` | Reset and low-power timing/capability profile; controller sequencing is pending. |
| `DIFFERENTIAL_CLOCK_MODE` | Single-ended/differential clock profile; output validation is pending. |
| `MEMORY_DENSITY_BYTES`, `ADDRESS_ROLLOVER` | Implemented memory geometry profile. A nonzero, non-rolling capacity rejects a request crossing its final byte before CS# assertion; rolling devices permit it. |
| `INTER_WORD_VARIABLE_LATENCY_SUPPORTED`, `INTER_WORD_STALL_EDGES`, `READ_STALL_TIMEOUT_EDGES` | Read-burst stall profile and controller-side bound. A nonzero timeout reports response code 4 if an observed stall remains asserted too long. |
| `T_READ_RWDS_QUALIFY_4X_TICKS`, `T_READ_DQ_SAMPLE_DELAY_4X_TICKS`, `READ_SAMPLE_TIMEOUT_4X_TICKS` | Read-pin sampler profile. These qualify an RWDS transition, defer DQ capture, and bound a pending capture in 4× ticks. |
| `INITIAL_READ_STROBE_TIMEOUT_4X_TICKS`, `READ_BYTE_B_TIMEOUT_4X_TICKS`, `UNEXPECTED_RWDS_FATAL` | Malformed-read recovery profile. Bounds missing Byte A/Byte B strobes and optionally treats an out-of-order RWDS transition as fatal. |

The configuration surface deliberately mirrors the slave wrapper. CR0 latency,
the zero-latency write parameters, the scheduler timing fields, the read-stall
fields, and the read-pin sampler fields affect controller behavior today; every
other parameter is retained as an explicit profile requirement, not an
implicit assumption about the attached device.

## Zero-latency writes

When the selected memory or register-space profile enables zero-latency
writes, the controller bypasses the initial-latency clocks after CA. It holds
CK Low until a write payload is available, then places Byte A and Byte B on the
next DDR edges. RWDS byte masks are disabled in this mode. `ZERO_LATENCY_WRITE_RWDS_LOW`
selects whether the controller drives RWDS Low or releases it for the data
phase.

## Controller timing profile

The controller schedules its own pin transitions in 4×-clock ticks. It waits
for `T_CSS_4X_TICKS` before the first CA edge; keeps each CA and write value
stable for the configured setup/hold periods; enforces
`T_CK_HIGH_MIN_4X_TICKS` and `T_CK_LOW_MIN_4X_TICKS`; and withholds the next
request until `T_RWR_4X_TICKS` has elapsed after CS# is released. Zero-valued
profile fields retain the model's safe default scheduler spacing.

## Variable-latency read stalls

For profiles enabling both `VARIABLE_LATENCY_SUPPORTED` and
`INTER_WORD_VARIABLE_LATENCY_SUPPORTED`, the controller recognizes the
slave's inter-word RWDS stall indication after a completed, accepted read
word. It continues CK without generating a new read word until RWDS recovers,
then resumes the burst. This is distinct from `read_ready_i` backpressure,
which holds CK Low only after a completed word. `READ_STALL_TIMEOUT_EDGES`
sets a nonzero bound for an observed stall; response code 4 denotes expiry.

## Read-pin sampling profile

The default profile (`T_READ_RWDS_QUALIFY_4X_TICKS=0` and
`T_READ_DQ_SAMPLE_DELAY_4X_TICKS=0`) uses ideal simultaneous RWDS/DQ edge
sampling, preserving the basic integration behavior. A non-default profile
first recognizes a relevant RWDS transition, requires it to remain at its new
level for `T_READ_RWDS_QUALIFY_4X_TICKS` 4× sampler ticks (the transition tick
counts as the first observation), and captures DQ after the configured
`T_READ_DQ_SAMPLE_DELAY_4X_TICKS`. This lets a board/device profile place the
sample inside DQ's valid window when strobe and data have different output
delays. `READ_SAMPLE_TIMEOUT_4X_TICKS` prevents an excessively delayed pending
capture from keeping a transaction alive indefinitely; expiry uses response
code 4. `test-controller-read-timing` covers a slave whose DQ changes 2500 ps
after RWDS.

## Read error recovery

`INITIAL_READ_STROBE_TIMEOUT_4X_TICKS` bounds the wait for Byte A, and
`READ_BYTE_B_TIMEOUT_4X_TICKS` bounds the wait for Byte B after Byte A has
been captured. Zero disables the corresponding bound. With
`UNEXPECTED_RWDS_FATAL` enabled (the default), a transition that does not
match the expected next byte strobe terminates the transfer with response code
5; either strobe timeout uses response code 6. A delayed DQ sample that
exceeds `READ_SAMPLE_TIMEOUT_4X_TICKS` uses response code 7. All three paths
discard a partial word, release DQ and RWDS, force CK Low, deassert CS#, and
apply `T_RWR_4X_TICKS` before another request is accepted.

`test-controller-read-error` injects absent Byte-A and Byte-B transitions and
checks code 6 plus the resulting idle pin state.

## Memory geometry

`MEMORY_DENSITY_BYTES=0` retains an unbounded simulation address space. For a
nonzero finite capacity with `ADDRESS_ROLLOVER=0`, the controller validates the
entire requested byte range during request validation. An invalid memory
request returns response code 8 with no CS#, CK, DQ, or RWDS activity. Register
space is not subject to this capacity check. With `ADDRESS_ROLLOVER=1`, the
controller permits a boundary-crossing transfer; the attached slave applies
its configured modulo-address mapping to each transfer byte.

`test-controller-geometry` covers an exact-boundary burst, pre-pin rejection
of a crossing burst, and a register-space access on an eight-byte device.
