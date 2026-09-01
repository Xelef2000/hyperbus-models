#pragma once

#include <cstdint>
#include <string_view>

namespace hyperram_profile {

struct InitialLatency { unsigned clock_cycles; bool additional_latency; };
class LatencyPolicy {
  public:
    virtual ~LatencyPolicy() = default;
    virtual unsigned cycles_from_cr0(std::uint16_t cr0) const = 0;
    virtual InitialLatency initial_latency(std::uint16_t cr0, bool ca_rwds_high,
                                           bool refresh_active) const = 0;
};
struct ChipProfile {
    std::string_view name; const LatencyPolicy& latency;
    std::uint16_t identification_register0, identification_register1;
    std::uint16_t configuration_register0, configuration_register1;
    bool fixed_latency_rwds_high, variable_latency_supported;
    unsigned refresh_interval_4x_ticks, refresh_busy_4x_ticks;
    bool zero_latency_memory_writes, zero_latency_register_writes, zero_latency_write_rwds_low;
    unsigned t_rwr_4x_ticks, t_css_4x_ticks, t_reset_recovery_4x_ticks;
    bool reset_clears_memory, deep_power_down_supported;
    unsigned t_dpd_entry_4x_ticks, t_dpd_exit_4x_ticks, t_csdpd_4x_ticks;
    bool hybrid_sleep_supported;
    unsigned t_hs_entry_4x_ticks, t_hs_exit_4x_ticks, t_cshs_4x_ticks;
    bool differential_clock_mode;
    unsigned t_ca_setup_4x_ticks, t_ca_hold_4x_ticks, t_write_setup_4x_ticks, t_write_hold_4x_ticks;
    std::uint32_t memory_density_bytes; bool address_rollover;
    bool inter_word_variable_latency_supported; unsigned inter_word_stall_edges;
    unsigned t_ck_high_min_4x_ticks, t_ck_low_min_4x_ticks;
    std::uint64_t t_dq_output_delay_ps, t_rwds_output_delay_ps;
    std::uint64_t t_dq_output_disable_delay_ps, t_rwds_output_disable_delay_ps;
    std::uint64_t t_dq_data_valid_delay_ps, t_rwds_strobe_delay_ps;
};
const ChipProfile* find(std::string_view name);
std::string_view supported_names();
} // namespace hyperram_profile
