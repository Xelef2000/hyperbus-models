# HyperBus controller chip profiles

`profile_config.cpp` is the single configuration file for built-in controller
profiles. Each entry defines controller-side CR0 latency interpretation, pin
scheduler timing, read sampling/error handling, geometry validation, and
controller capability assumptions.

Select one independently from the HyperRAM profile:

```systemverilog
hyperbus_controller #(.CHIP_PROFILE("generic_hyperram_controller")) controller (...);
```

The controller does not require the attached HyperRAM to use the same profile
name. Pair compatible profiles for normal integration and use different ones
for discovery or error-path testing. Add a controller-specific `LatencyPolicy`
in `chip_profiles.cpp` when a controller needs a different
CR0 mapping or additional-latency rule.
