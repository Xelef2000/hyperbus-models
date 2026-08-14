# HyperBus implementation checklist

Reference: *Infineon HyperBus Specification — Low Signal Count, High
Performance DDR Bus*. This checklist tracks a cycle-accurate HyperBus
implementation. The project now contains separate C++/SystemVerilog slave and
master models. Master checkmarks describe the transaction-level controller's
implemented behavior; unchecked items remain necessary for cycle-accurate
support of every compliant slave profile.

## Cycle-accuracy acceptance criterion

A feature is complete only when the model matches the specification on every
clock edge for **all valid transactions** covered by that feature: pin
ownership and values (`CS#`, `CK`/`CK#`, `DQ`, and `RWDS`), latency, DDR edge
alignment, legal termination, and the resulting memory/register/device state.
Matching only the final read or written value is insufficient. Each checked
item below reflects currently implemented basic behavior, not a claim that the
overall transaction class is cycle-accurate yet.

## Slave model

### Physical interface and clocking

- [x] Provide bidirectional `DQ[7:0]` pins.
- [x] Provide bidirectional `RWDS` pin.
- [x] Respond to `CS#` assertion and release driven outputs on deassertion.
- [x] Accept `CK` and `CK#` pins at the SystemVerilog wrapper boundary.
- [x] Track whether a 4×-clock event coincides with a rising or falling main-clock edge.
- [x] Support profile-selectable single-ended and validated differential (`CK`/`CK#`) clocking.
- [x] Enforce legal idle-low clock state at `CS#` assertion/deassertion.
- [x] Model interface timing constraints: setup/hold, output delay, clock duty cycle, and bus turnaround.
- [x] Enforce profile-configured 4×-tick setup/hold windows for CA and write DQ/RWDS inputs.

### Command/address phase

- [x] Capture the six command/address (CA) bytes.
- [x] Decode the CA read/write bit.
- [x] Decode the memory address fields needed for basic accesses.
- [x] Drive a profile-configured RWDS latency indication during CA.
- [x] Decode and honor the CA address-space bit (memory versus register space).
- [x] Decode and honor the CA burst-type bit (linear versus wrapped burst).
- [x] Reject unsupported register-space CA targets and read-only ID writes.
- [x] Model command/address timing and RWDS latency indication during CA.
- [x] Add support to model chips with 0 latency writes.

### Read transactions

- [x] Perform basic memory reads using CR0-selected fixed initial latency.
- [x] Drive read data on `DQ[7:0]`.
- [x] Generate a basic toggling `RWDS` read strobe.
- [x] Continue a basic sequential (linear) read stream until `CS#` ends the transaction.
- [x] Return `8'hff` for uninitialized memory bytes.
- [x] Select one or two CR0-defined latency counts in fixed-latency mode.
- [x] Request additional latency during a profile-configured refresh-busy interval.
- [x] Implement protocol-accurate RWDS/data edge alignment and read turnaround.
- [x] Implement profile-configured refresh-collision stalls between completed read words.
- [x] Implement basic CR0-configured wrapped burst reads.
- [x] Implement basic CR0-configured hybrid burst reads (one wrapped window, then linear).
- [x] Implement complete word-oriented read semantics and legal transaction termination behavior.

### Write transactions

- [x] Perform basic memory writes using CR0-selected fixed initial latency.
- [x] Honor `RWDS` as a per-byte write mask during basic writes.
- [x] Capture and commit normal writes as complete 16-bit DDR words.
- [x] Detect wrong-edge and truncated-word data transfers as protocol errors.
- [x] Release RWDS after write CA so the host can provide its mask preamble.
- [x] Continue a basic sequential (linear) write stream until `CS#` ends the transaction.
- [x] Select one or two CR0-defined latency counts in fixed-latency mode.
- [x] Request additional latency during a profile-configured refresh-busy interval.
- [x] Implement profile-configured zero-latency writes for memory and register space.
- [x] Implement basic CR0-configured wrapped burst writes.
- [x] Implement basic CR0-configured hybrid burst writes (one wrapped window, then linear).
- [x] Implement complete word-oriented write semantics and all byte-mask corner cases.
- [x] Verify all four normal-latency memory RWDS byte-mask combinations and masked-word address advance.
- [x] Detect profile-configured transaction recovery (`tRWR`) violations.
- [x] Implement profile-specific bus-turnaround requirements.

### Memory and register spaces

- [x] Store basic memory contents and make them observable through subsequent reads.
- [x] Parameterize ID and configuration-register reset values as a device profile.
- [x] Support profile-controlled finite memory density and linear address rollover.
- [x] Reject strict-profile out-of-range memory reads and writes deterministically.
- [x] Implement basic register-space reads (ID0/ID1/CR0/CR1).
- [x] Implement basic register-space writes (CR0/CR1; IDs are read-only).
- [x] Implement profile-configured device-ID registers.
- [x] Implement volatile CR0/CR1 storage; CR0 latency fields are active.
- [x] Apply CR0 latency changes to subsequent transactions.
- [x] Apply RWDS masks before CR0/CR1 side effects such as DPD and hybrid sleep.

### Reset, power, and device state

- [x] Provide a model reset path that returns the bus state machine to idle.
- [x] Model profile-configured reset recovery timing and default register values.
- [x] Model hardware reset behavior and recovery timing.
- [x] Preserve/reset memory contents according to the selected device profile.
- [x] Model active/standby and profile-configured deep-power-down/hybrid-sleep states.
- [x] Implement profile-configured deep-power-down entry, CS#-pulse exit, and recovery timing.

### Robustness and verification

- [x] Verify a basic read/write sequence in the C++ model testbench.
- [x] Report protocol violations with actionable diagnostics.
- [x] Add directed tests for CA fields, register space, latency modes, masks, bursts, reset, and power states.
- [x] Add randomized and back-to-back transaction tests for the C++ model.
- [x] Add assertions/coverage for edge alignment, ownership, and all state transitions.

## Master model

### Physical interface and clocking

- [x] Drive `CS#`, complementary `CK`/`CK#`, `DQ[7:0]`, and `RWDS` with correct basic ownership changes.
- [x] Generate legal basic DDR clocking, including CK-Low start/stop behavior.
- [x] Enforce profile CS#, CA/write setup/hold, CK duty-cycle, and turnaround timing.
- [ ] Model physical output-enable/disable and board-level output-delay calibration.
- [x] Use the required 4×-clock internal scheduler for pin-level sequencing.
- [ ] Validate profile-selected single-ended versus differential clock operation.

### Command generation

- [x] Generate all six CA bytes.
- [x] Encode read/write, memory/register-space, burst-type, and address fields.
- [x] Support legal basic CS# framing and transaction termination.
- [x] Support linear, wrapped, and slave-configured hybrid bursts.
- [ ] Validate reserved CA encodings and device-specific command restrictions.

### Read engine

- [x] Issue memory and register reads.
- [x] Sample DQ using RWDS with basic DDR edge alignment.
- [x] Interpret RWDS during CA to select normal or additional CR0-controlled initial latency.
- [x] Handle profile-gated variable inter-word latency and RWDS read stalls.
- [x] Safely abort malformed read ordering and bounded missing Byte-A/Byte-B strobes.
- [ ] Handle all device-specific read error indications and timeout recovery policies.
- [x] Support arbitrary positive 16-bit-word read lengths and reject unaligned byte addresses.
- [x] Enforce finite memory geometry and profile-controlled address rollover policy.
- [x] Profile-qualify read RWDS and delay DQ capture relative to the strobe.

### Write engine

- [x] Issue memory and register writes.
- [x] Drive basic DDR write data timing.
- [x] Drive RWDS byte masks for initial-latency writes.
- [x] Support configured zero-latency memory and register writes.
- [x] Enforce write-to-read turnaround timing.
- [x] Support profile-required write data setup/hold and termination timing.

### Configuration, reset, and power

- [x] Read device-ID registers through the transaction interface.
- [x] Read and program configuration registers.
- [x] Adapt transactions to CR0-controlled latency and wrapped/hybrid burst settings.
- [x] Expose a complete slave-profile configuration surface, including future timing, refresh, power, geometry, and clocking options.
- [ ] Discover capabilities automatically and validate the configured profile against ID/register values.
- [ ] Adapt transactions to variable-latency, refresh, drive-strength, and all timing settings.
- [x] Enforce profile-configured reset recovery before discovery or traffic.
- [ ] Execute deep-power-down and hybrid-sleep entry/exit transactions and recovery.

### Robustness and verification

- [ ] Detect timeouts, invalid RWDS behavior, protocol errors, and reset/power interruptions.
- [x] Provide a transaction-level interface with completion and error reporting.
- [x] Verify directed normal-latency, zero-latency, register, linear, and wrapped operations against the slave model.
- [ ] Add randomized and back-to-back controller operations against the C++ slave model.
- [ ] Add assertions and coverage for all bus ownership and protocol state transitions.
