# HyperBus implementation checklist

Reference: *Infineon HyperBus Specification — Low Signal Count, High
Performance DDR Bus*. This checklist tracks a cycle-accurate HyperBus
implementation. The current C++/SystemVerilog model is a **slave** model;
the master section is deliberately left unchecked for a future, separate
model.

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
- [ ] Implement and validate differential-clock (`CK`/`CK#`) behavior.
- [ ] Enforce legal clock-stop and `CS#` assertion/deassertion conditions.
- [ ] Model interface timing constraints: setup/hold, output delay, clock duty cycle, and bus turnaround.

### Command/address phase

- [x] Capture the six command/address (CA) bytes.
- [x] Decode the CA read/write bit.
- [x] Decode the memory address fields needed for basic accesses.
- [x] Drive a profile-configured RWDS latency indication during CA.
- [ ] Decode and honor the CA address-space bit (memory versus register space).
- [ ] Decode and honor the CA burst-type bit (linear versus wrapped burst).
- [ ] Reject or report reserved/invalid CA encodings.
- [ ] Model command/address timing and RWDS latency indication during CA.
- [ ] Add support to model chips with 0 latency writes

### Read transactions

- [x] Perform basic memory reads using CR0-selected fixed initial latency.
- [x] Drive read data on `DQ[7:0]`.
- [x] Generate a basic toggling `RWDS` read strobe.
- [x] Continue a basic sequential (linear) read stream until `CS#` ends the transaction.
- [x] Return `8'hff` for uninitialized memory bytes.
- [x] Select one or two CR0-defined latency counts in fixed-latency mode.
- [ ] Request additional latency dynamically in variable-latency mode.
- [ ] Implement protocol-accurate RWDS/data edge alignment and read turnaround.
- [ ] Implement variable latency between read words and RWDS error indication.
- [ ] Implement wrapped and hybrid burst reads, including supported wrap lengths.
- [ ] Implement complete word-oriented read semantics and legal transaction termination behavior.

### Write transactions

- [x] Perform basic memory writes using CR0-selected fixed initial latency.
- [x] Honor `RWDS` as a per-byte write mask during basic writes.
- [x] Release RWDS after write CA so the host can provide its mask preamble.
- [x] Continue a basic sequential (linear) write stream until `CS#` ends the transaction.
- [x] Select one or two CR0-defined latency counts in fixed-latency mode.
- [ ] Request additional latency dynamically in variable-latency mode.
- [ ] Implement writes without initial latency where configured/supported.
- [ ] Implement wrapped and hybrid burst writes, including supported wrap lengths.
- [ ] Implement complete word-oriented write semantics and all byte-mask corner cases.
- [ ] Implement write-to-read timing (`tRWR`) and bus turnaround requirements.

### Memory and register spaces

- [x] Store basic memory contents and make them observable through subsequent reads.
- [x] Parameterize ID and configuration-register reset values as a device profile.
- [ ] Model the complete advertised memory density/address range and address rollover behavior.
- [x] Implement basic register-space reads (ID0/ID1/CR0/CR1).
- [x] Implement basic register-space writes (CR0/CR1; IDs are read-only).
- [x] Implement profile-configured device-ID registers.
- [x] Implement volatile CR0/CR1 storage; CR0 latency fields are active.
- [x] Apply CR0 latency changes to subsequent transactions.

### Reset, power, and device state

- [x] Provide a model reset path that returns the bus state machine to idle.
- [ ] Model power-on reset timing and default register values.
- [ ] Model hardware reset behavior and recovery timing.
- [ ] Preserve/reset memory contents according to the selected device behavior.
- [ ] Implement active, standby, deep-power-down, and hybrid-sleep states as applicable.
- [ ] Implement entry/exit commands and timing for low-power states.

### Robustness and verification

- [x] Compare a basic read/write sequence against the Infineon reference model in the testbench.
- [ ] Report protocol violations with actionable diagnostics.
- [ ] Add directed tests for CA fields, register space, latency modes, masks, bursts, reset, and power states.
- [ ] Add randomized transaction and back-to-back transaction tests against the reference model.
- [ ] Add assertions/coverage for edge alignment, ownership, and all state transitions.

## Master model (future separate model)

### Physical interface and clocking

- [ ] Drive `CS#`, differential `CK`/`CK#`, `DQ[7:0]`, and `RWDS` with correct ownership changes.
- [ ] Generate legal DDR clocking, including start/stop behavior and duty-cycle requirements.
- [ ] Observe setup/hold, output-enable, and turnaround timing.
- [ ] Support clock-rate selection and the required 4×-clock internal scheduling.

### Command generation

- [ ] Generate all six CA bytes.
- [ ] Encode read/write, memory/register-space, burst-type, and address fields.
- [ ] Support legal CS# framing and transaction termination.
- [ ] Support linear, wrapped, and hybrid bursts.

### Read engine

- [ ] Issue memory and register reads.
- [ ] Sample DQ using RWDS with protocol-correct edge alignment.
- [ ] Interpret RWDS during CA to select normal or additional initial latency.
- [ ] Handle variable inter-word latency and read error indication.
- [ ] Support arbitrary legal read lengths and byte/word alignment rules.

### Write engine

- [ ] Issue memory and register writes.
- [ ] Drive write data with DDR timing.
- [ ] Drive RWDS byte masks for initial-latency writes.
- [ ] Support writes without initial latency where configured/supported.
- [ ] Enforce write-to-read turnaround timing.

### Configuration, reset, and power

- [ ] Discover device capabilities and read device-ID registers.
- [ ] Read and program configuration registers.
- [ ] Adapt transactions to configured latency, burst, and drive settings.
- [ ] Execute and recover from reset and power-state transitions.

### Robustness and verification

- [ ] Detect timeouts, invalid RWDS behavior, protocol errors, and reset/power interruptions.
- [ ] Provide a transaction-level interface with completion and error reporting.
- [ ] Verify directed, randomized, and back-to-back operations against the slave/reference model.
- [ ] Add assertions and coverage for all bus ownership and protocol state transitions.
