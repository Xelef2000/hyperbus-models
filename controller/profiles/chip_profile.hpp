#pragma once

#include <cstdint>
#include <string_view>

namespace controller_profile {
struct InitialLatency { unsigned clock_cycles; bool additional_latency; };
class LatencyPolicy {
  public:
    virtual ~LatencyPolicy() = default;
    virtual unsigned cycles_from_cr0(std::uint16_t cr0) const = 0;
    virtual InitialLatency initial_latency(std::uint16_t cr0, bool ca_rwds_high) const = 0;
};
struct ChipProfile {
    std::string_view name; const LatencyPolicy& latency;
    std::uint16_t id0, id1, cr0, cr1;
    bool auto_profile_discovery, adopt_discovered_cr0;
    bool zero_latency_memory_writes, zero_latency_register_writes, zero_latency_write_rwds_low;
    bool variable_latency_supported, inter_word_variable_latency_supported;
    unsigned read_stall_timeout_edges;
    unsigned t_rwr_4x_ticks, t_css_4x_ticks, t_reset_recovery_4x_ticks;
    unsigned t_ca_setup_4x_ticks, t_ca_hold_4x_ticks, t_write_setup_4x_ticks, t_write_hold_4x_ticks;
    unsigned t_ck_high_min_4x_ticks, t_ck_low_min_4x_ticks;
    unsigned rwds_qualify_4x_ticks, dq_sample_delay_4x_ticks, read_sample_timeout_4x_ticks;
    unsigned initial_read_strobe_timeout_4x_ticks, read_byte_b_timeout_4x_ticks;
    bool unexpected_rwds_fatal; std::uint32_t memory_density_bytes; bool address_rollover;
};
const ChipProfile* find(std::string_view name);
std::string_view supported_names();
} // namespace controller_profile
