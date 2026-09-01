#pragma once

#include <cstddef>

#include "chip_profile.hpp"

namespace hyperram_profile {

const LatencyPolicy& standard_latency_policy();
const ChipProfile* configured_profiles(std::size_t& count);

} // namespace hyperram_profile
