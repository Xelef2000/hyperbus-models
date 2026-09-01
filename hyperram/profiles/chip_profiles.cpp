#include "profile_config.hpp"

namespace hyperram_profile {
namespace {
class HyperramLatencyPolicy final : public LatencyPolicy {
  public:
    unsigned cycles_from_cr0(std::uint16_t cr0) const override {
        switch ((cr0 >> 4) & 0xfU) {
          case 0x0: return 5; case 0x1: return 6; case 0x2: return 7; case 0x3: return 8;
          case 0x4: return 9; case 0x5: return 10; case 0x6: return 11; case 0x7: return 12;
          case 0x8: return 13; case 0x9: return 14; case 0xa: return 15; case 0xb: return 16;
          case 0xe: return 3; case 0xf: return 4; default: return 7;
        }
    }
    InitialLatency initial_latency(std::uint16_t cr0, bool ca_rwds_high, bool refresh_active) const override {
        const bool additional = ca_rwds_high || refresh_active;
        const auto cycles = cycles_from_cr0(cr0);
        return {additional ? cycles * 2U : cycles, additional};
    }
};
} // namespace
const LatencyPolicy& standard_latency_policy() { static const HyperramLatencyPolicy policy; return policy; }
const ChipProfile* find(std::string_view name) {
    std::size_t count = 0; const auto* profiles = configured_profiles(count);
    for (std::size_t i = 0; i < count; ++i) if (profiles[i].name == name) return &profiles[i];
    return nullptr;
}
std::string_view supported_names() { return "s27ks0642_200mhz, test_default, test_main, test_read_stall, test_zero_latency, test_geometry, test_read_timing, test_timing"; }
} // namespace hyperram_profile
