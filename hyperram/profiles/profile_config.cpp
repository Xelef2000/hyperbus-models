#include "profile_config.hpp"

namespace hyperram_profile {
namespace {
#define P(NAME, CR0, FIXED, VAR, REFRESH_I, REFRESH_B, ZMEM, ZREG, ZRWDS, RWR, CSS, RESET, DPD, DPDIN, DPDO, CSDPD, HS, HSIN, HSOUT, CSHS, DIFF, CAS, CAH, WS, WH, DENSITY, ROLL, IWVAR, IWSTALL, CKH, CKL, DQ, RWDS, DQOFF, RWDSOFF, DQVALID, RWDSSTROBE) \
    {NAME, standard_latency_policy(), 0x0c81, 0x0001, CR0, 0xffc1, FIXED, VAR, REFRESH_I, REFRESH_B, ZMEM, ZREG, ZRWDS, RWR, CSS, RESET, false, DPD, DPDIN, DPDO, CSDPD, HS, HSIN, HSOUT, CSHS, DIFF, CAS, CAH, WS, WH, DENSITY, ROLL, IWVAR, IWSTALL, CKH, CKL, DQ, RWDS, DQOFF, RWDSOFF, DQVALID, RWDSSTROBE}
const ChipProfile profiles[] = {
    P("s27ks0642_200mhz", 0x8f2f, true, false, 0, 0, false, false, false, 0, 0, 0, false, 0, 0, 0, false, 0, 0, 0, false, 0, 0, 0, 0, 0, true, false, 0, 0, 0, 5000, 5000, 5000, 5000, 5000, 5000),
    P("test_default", 0x8f8f, false, false, 0, 0, false, false, false, 0, 0, 0, false, 0, 0, 0, false, 0, 0, 0, false, 1, 1, 1, 1, 0, true, false, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    P("test_main", 0x8f8f, false, true, 1000, 100, false, false, false, 28, 0, 8, true, 8, 16, 12, true, 8, 16, 12, true, 1, 1, 1, 1, 0, true, false, 0, 0, 0, 5000, 5000, 5000, 5000, 5000, 5000),
    P("test_read_stall", 0x8f8f, false, true, 0, 0, false, false, false, 0, 0, 0, false, 0, 0, 0, false, 0, 0, 0, false, 0, 0, 0, 0, 0, true, true, 2, 0, 0, 0, 0, 0, 0, 0, 0),
    P("test_zero_latency", 0x8f8f, false, false, 0, 0, true, true, false, 0, 0, 0, false, 0, 0, 0, false, 0, 0, 0, false, 0, 0, 0, 0, 0, true, false, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    P("test_geometry", 0x8f8f, false, false, 0, 0, false, false, false, 0, 0, 0, false, 0, 0, 0, false, 0, 0, 0, false, 0, 0, 0, 0, 8, false, false, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    P("test_read_timing", 0x8f8f, false, false, 0, 0, false, false, false, 0, 0, 0, false, 0, 0, 0, false, 0, 0, 0, false, 0, 0, 0, 0, 0, true, false, 0, 0, 0, 0, 0, 0, 0, 2500, 0),
    P("test_timing", 0x8f8f, false, false, 0, 0, false, false, false, 6, 4, 0, false, 0, 0, 0, false, 0, 0, 0, false, 3, 2, 3, 2, 0, true, false, 0, 4, 4, 0, 0, 0, 0, 0, 0)
};
#undef P
} // namespace
const ChipProfile* configured_profiles(std::size_t& count) {
    count = sizeof(profiles) / sizeof(profiles[0]);
    return profiles;
}
} // namespace hyperram_profile
