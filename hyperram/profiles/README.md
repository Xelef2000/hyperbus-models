# HyperRAM chip profiles

`profile_config.cpp` is the single configuration file for built-in HyperRAM
chips and test fixtures. Each `ChipProfile` entry supplies reset registers,
feature flags, protocol timing, memory geometry, and DQ/RWDS pin timing.

Select one from the SystemVerilog wrapper:

```systemverilog
hyperram #(.CHIP_PROFILE("s27ks0642_200mhz")) memory (...);
```

Add a production chip by adding a named entry here. If its CR0 latency mapping
or normal/additional-latency multiplier differs, implement a dedicated
`LatencyPolicy` in `chip_profiles.cpp` and attach it to the
entry. `test_*` entries are test fixtures rather than device definitions.
