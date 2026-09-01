#include "profile_config.hpp"

namespace controller_profile {
namespace {
#define P(NAME, CR0, ZMEM, ZREG, ZRWDS, VAR, IWVAR, STALL, RWR, CSS, RESET, CAS, CAH, WS, WH, CKH, CKL, QUAL, DQD, SAMPLE, IA, IB, FATAL, DENSITY, ROLL) \
    {NAME, standard_latency_policy(), 0x0c81, 0x0001, CR0, 0xffc1, false, false, ZMEM, ZREG, ZRWDS, VAR, IWVAR, STALL, RWR, CSS, RESET, CAS, CAH, WS, WH, CKH, CKL, QUAL, DQD, SAMPLE, IA, IB, FATAL, DENSITY, ROLL}
const ChipProfile profiles[] = {
    P("generic_hyperram_controller", 0x8f8f, false, false, false, false, false, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, true, 0, true),
    P("test_zero_latency", 0x8f8f, true, true, false, false, false, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, true, 0, true),
    P("test_read_stall", 0x8f8f, false, false, false, true, true, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, true, 0, true),
    P("test_read_timing", 0x8f8f, false, false, false, false, false, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 8, 0, 0, true, 0, true),
    P("test_read_error", 0x8f8f, false, false, false, false, false, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 6, 6, true, 0, true),
    P("test_geometry", 0x8f8f, false, false, false, false, false, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, false, 8, false),
    P("test_timing", 0x8f8f, false, false, false, false, false, 64, 6, 4, 0, 3, 2, 3, 2, 4, 4, 0, 0, 64, 0, 0, true, 0, true)
};
#undef P
} // namespace
const ChipProfile* configured_profiles(std::size_t& count) {
    count = sizeof(profiles) / sizeof(profiles[0]);
    return profiles;
}
} // namespace controller_profile
