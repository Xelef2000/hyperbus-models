#include <cstdint>
#include <unordered_map>

#include "profiles/chip_profile.hpp"

// Minimal cycle-accurate HyperRAM behavioural core.  It supports the memory
// address space, fixed initial latency, and linear read/write bursts.
class HyperramModel {
  public:
    void reset();
    void tick();
    void tick_4x(bool reset_n, bool clk, bool cs_n, bool ck, bool ck_n, std::uint8_t dq,
                 bool rwds);
    void set_device_profile(std::uint16_t id0, std::uint16_t id1,
                            std::uint16_t config0, std::uint16_t config1,
                            bool fixed_latency_rwds_high,
                            bool variable_latency_supported,
                            unsigned refresh_interval_4x_ticks,
                            unsigned refresh_busy_4x_ticks,
                            bool zero_latency_memory_writes,
                            bool zero_latency_register_writes,
                            bool zero_latency_write_rwds_low,
                            unsigned t_rwr_4x_ticks,
                            unsigned t_css_4x_ticks,
                            unsigned t_reset_recovery_4x_ticks,
                            bool reset_clears_memory,
                            bool deep_power_down_supported,
                            unsigned t_dpd_entry_4x_ticks,
                            unsigned t_dpd_exit_4x_ticks,
                            unsigned t_csd_pd_4x_ticks,
                            bool hybrid_sleep_supported,
                            unsigned t_hs_entry_4x_ticks,
                            unsigned t_hs_exit_4x_ticks,
                            unsigned t_cshs_4x_ticks,
                            bool differential_clock_mode,
                            unsigned t_ca_setup_4x_ticks,
                            unsigned t_ca_hold_4x_ticks,
                            unsigned t_write_setup_4x_ticks,
                            unsigned t_write_hold_4x_ticks,
                            bool inter_word_variable_latency_supported,
                            unsigned inter_word_stall_edges,
                            unsigned t_ck_high_min_4x_ticks,
                            unsigned t_ck_low_min_4x_ticks);
    bool select_profile(const char* name);
    std::uint64_t output_timing(unsigned index) const;
    void set_zero_latency_support(bool memory_writes, bool register_writes,
                                  bool rwds_low);
    void set_memory_geometry(std::uint32_t bytes, bool rollover);
    void set_interword_latency_for_test(bool enabled, unsigned stall_edges);
    void force_refresh_collision_for_test();

    bool dq_oe() const;
    std::uint8_t dq_o() const;
    bool rwds_oe() const;
    bool rwds_o() const;
    std::uint8_t debug_read_byte(std::uint32_t address) const;
    std::uint16_t debug_configuration_register0() const;
    std::uint16_t debug_configuration_register1() const;
    bool debug_refresh_active() const;
    unsigned debug_device_state() const;
    unsigned debug_bus_state() const;
    unsigned debug_protocol_errors() const;
    unsigned debug_last_error_code() const;
    std::uint64_t debug_last_error_tick() const;
    std::uint32_t debug_last_error_address() const;

  private:
    enum class MainClockEdge { None, Rising, Falling };
    enum class BusState { Idle, CommandAddress, Latency, Read, ReadStall, Write, Ignore };
    enum class DeviceState {
        ResetRecovery, Active, DeepPowerDownEntry, DeepPowerDown,
        DeepPowerDownRecovery, HybridSleepEntry, HybridSleep,
        HybridSleepRecovery
    };
    enum class WordPhase { ByteA, ByteB };
    enum class ErrorCode : unsigned {
        None, Clock, ChipSelect, Timing, InputTiming, TruncatedWord,
        UnsupportedCommand, ReadOnlyRegister, AddressRange, PowerState
    };

    static constexpr unsigned CommandAddressBytes = 6;
    struct DeviceProfile {
        std::uint16_t identification_register0 = 0x0c81;
        std::uint16_t identification_register1 = 0x0001;
        std::uint16_t configuration_register0 = 0x8f2f;
        std::uint16_t configuration_register1 = 0xffc1;
        bool fixed_latency_rwds_high = true;
        bool variable_latency_supported = false;
        unsigned refresh_interval_4x_ticks = 0;
        unsigned refresh_busy_4x_ticks = 0;
        bool zero_latency_memory_writes = false;
        bool zero_latency_register_writes = false;
        bool zero_latency_write_rwds_low = false;
        unsigned t_rwr_4x_ticks = 0;
        unsigned t_css_4x_ticks = 0;
        unsigned t_reset_recovery_4x_ticks = 0;
        bool reset_clears_memory = false;
        bool deep_power_down_supported = false;
        unsigned t_dpd_entry_4x_ticks = 0;
        unsigned t_dpd_exit_4x_ticks = 0;
        unsigned t_csd_pd_4x_ticks = 0;
        bool hybrid_sleep_supported = false;
        unsigned t_hs_entry_4x_ticks = 0;
        unsigned t_hs_exit_4x_ticks = 0;
        unsigned t_cshs_4x_ticks = 0;
        bool differential_clock_mode = false;
        unsigned t_ca_setup_4x_ticks = 0;
        unsigned t_ca_hold_4x_ticks = 0;
        unsigned t_write_setup_4x_ticks = 0;
        unsigned t_write_hold_4x_ticks = 0;
        std::uint32_t memory_density_bytes = 0; // 0 means unbounded.
        bool address_rollover = true;
        bool inter_word_variable_latency_supported = false;
        unsigned inter_word_stall_edges = 0;
        unsigned t_ck_high_min_4x_ticks = 0;
        unsigned t_ck_low_min_4x_ticks = 0;
    };

    void reset_transaction();
    void apply_reset(bool clear_memory);
    void update_device_state(bool reset_n, bool cs_n);
    void update_refresh_state();
    void report_error(ErrorCode code, std::uint32_t address = 0xffffffffU);
    void update_input_stability(std::uint8_t dq, bool rwds);
    void complete_pending_input(std::uint8_t dq, bool rwds);
    void accept_bus_edge(std::uint8_t dq, bool rwds, bool rising_edge);
    void process_bus_edge(std::uint8_t dq, bool rwds, bool rising_edge);
    void begin_transfer();
    std::uint8_t read_data_byte();
    std::uint8_t read_register_byte(std::uint32_t word_address,
                                    bool byte_b) const;
    void write_data_byte(std::uint8_t dq, bool rwds, bool rising_edge);
    void write_register_byte(std::uint32_t word_address, bool byte_b,
                             std::uint8_t value);
    void advance_data_byte();
    unsigned wrapped_burst_words_from_cr0() const;
    std::uint8_t read_byte(std::uint32_t address) const;
    bool supported_register_address(std::uint32_t word_address) const;
    bool write_memory_byte(std::uint32_t address, std::uint8_t value);
    bool normalize_memory_address(std::uint32_t& address) const;

    std::uint64_t cycles_ = 0;
    std::uint64_t cycles_4x_ = 0;
    std::uint64_t main_clk_rising_edges_ = 0;
    std::uint64_t main_clk_falling_edges_ = 0;
    bool previous_main_clk_ = false;
    MainClockEdge main_clk_edge_ = MainClockEdge::None;

    BusState bus_state_ = BusState::Idle;
    bool previous_ck_ = false;
    bool previous_ck_n_ = true;
    std::uint64_t last_ck_transition_4x_tick_ = 0;
    std::uint8_t previous_dq_ = 0;
    bool previous_rwds_ = false;
    std::uint64_t last_dq_change_4x_tick_ = 0;
    std::uint64_t last_rwds_change_4x_tick_ = 0;
    struct PendingInput {
        bool valid = false;
        std::uint8_t dq = 0;
        bool rwds = false;
        bool rising_edge = false;
        std::uint64_t edge_4x_tick = 0;
        unsigned hold_4x_ticks = 0;
    } pending_input_;
    bool differential_clock_invalid_ = false;
    bool previous_cs_n_ = true;
    unsigned ca_bytes_received_ = 0;
    bool ca_expected_rising_edge_ = true;
    bool first_ca_seen_ = false;
    bool cs_asserted_with_ck_low_ = true;
    std::uint64_t cs_assert_4x_tick_ = 0;
    std::uint64_t last_transaction_end_4x_tick_ = 0;
    bool have_completed_transaction_ = false;
    unsigned latency_edges_remaining_ = 0;
    unsigned read_stall_edges_remaining_ = 0;
    std::uint64_t command_address_ = 0;
    std::uint32_t word_address_ = 0;
    std::uint32_t wrapped_burst_base_word_ = 0;
    unsigned wrapped_burst_words_ = 0;
    unsigned wrapped_burst_words_transferred_ = 0;
    bool byte_b_ = false;
    WordPhase word_phase_ = WordPhase::ByteA;
    std::uint8_t pending_byte_a_ = 0;
    bool pending_byte_a_masked_ = false;
    bool dpd_entry_armed_ = false;
    bool hybrid_sleep_entry_armed_ = false;
    bool read_transfer_ = false;
    bool register_space_ = false;
    bool linear_burst_ = true;
    bool hybrid_burst_ = false;
    bool write_masks_enabled_ = true;
    bool additional_latency_ = false;
    bool refresh_active_ = false;
    DeviceState device_state_ = DeviceState::Active;
    bool previous_reset_n_ = true;
    std::uint64_t device_state_deadline_4x_tick_ = 0;
    std::uint64_t dpd_wake_cs_assert_4x_tick_ = 0;
    bool dpd_wake_cs_active_ = false;
    std::uint64_t hybrid_sleep_wake_cs_assert_4x_tick_ = 0;
    bool hybrid_sleep_wake_cs_active_ = false;
    unsigned protocol_errors_ = 0;
    ErrorCode last_error_code_ = ErrorCode::None;
    std::uint64_t last_error_tick_ = 0;
    std::uint32_t last_error_address_ = 0xffffffffU;
    std::uint64_t next_refresh_start_4x_tick_ = 0;
    std::uint64_t refresh_busy_until_4x_tick_ = 0;
    // Reset values for the device-specific register-space profile.  The
    // registers are stored now so future register transactions can use them.
    DeviceProfile device_profile_;
    const hyperram_profile::ChipProfile* selected_profile_ = nullptr;
    std::uint16_t identification_register0_ = 0;
    std::uint16_t identification_register1_ = 0;
    std::uint16_t configuration_register0_ = 0;
    std::uint16_t configuration_register1_ = 0;
    std::unordered_map<std::uint32_t, std::uint8_t> memory_;

    bool dq_oe_ = false;
    std::uint8_t dq_o_ = 0;
    bool rwds_oe_ = false;
    bool rwds_o_ = false;
};

bool HyperramModel::select_profile(const char* name)
{
    const auto* profile = hyperram_profile::find(name ? name : "");
    if (!profile)
        return false;
    selected_profile_ = profile;
    set_device_profile(profile->identification_register0, profile->identification_register1,
        profile->configuration_register0, profile->configuration_register1,
        profile->fixed_latency_rwds_high, profile->variable_latency_supported,
        profile->refresh_interval_4x_ticks, profile->refresh_busy_4x_ticks,
        profile->zero_latency_memory_writes, profile->zero_latency_register_writes,
        profile->zero_latency_write_rwds_low, profile->t_rwr_4x_ticks,
        profile->t_css_4x_ticks, profile->t_reset_recovery_4x_ticks,
        profile->reset_clears_memory, profile->deep_power_down_supported,
        profile->t_dpd_entry_4x_ticks, profile->t_dpd_exit_4x_ticks,
        profile->t_csdpd_4x_ticks, profile->hybrid_sleep_supported,
        profile->t_hs_entry_4x_ticks, profile->t_hs_exit_4x_ticks,
        profile->t_cshs_4x_ticks, profile->differential_clock_mode,
        profile->t_ca_setup_4x_ticks, profile->t_ca_hold_4x_ticks,
        profile->t_write_setup_4x_ticks, profile->t_write_hold_4x_ticks,
        profile->inter_word_variable_latency_supported, profile->inter_word_stall_edges,
        profile->t_ck_high_min_4x_ticks, profile->t_ck_low_min_4x_ticks);
    set_memory_geometry(profile->memory_density_bytes, profile->address_rollover);
    return true;
}

std::uint64_t HyperramModel::output_timing(unsigned index) const
{
    if (!selected_profile_)
        return 5000;
    switch (index) {
      case 0: return selected_profile_->t_dq_output_delay_ps;
      case 1: return selected_profile_->t_rwds_output_delay_ps;
      case 2: return selected_profile_->t_dq_output_disable_delay_ps;
      case 3: return selected_profile_->t_rwds_output_disable_delay_ps;
      case 4: return selected_profile_->t_dq_data_valid_delay_ps;
      case 5: return selected_profile_->t_rwds_strobe_delay_ps;
      default: return 0;
    }
}

void HyperramModel::reset()
{
    apply_reset(true);
    device_state_ = DeviceState::Active;
    previous_reset_n_ = true;
}

void HyperramModel::apply_reset(bool clear_memory)
{
    cycles_ = 0;
    cycles_4x_ = 0;
    main_clk_rising_edges_ = 0;
    main_clk_falling_edges_ = 0;
    previous_main_clk_ = false;
    main_clk_edge_ = MainClockEdge::None;
    last_ck_transition_4x_tick_ = 0;
    protocol_errors_ = 0;
    last_error_code_ = ErrorCode::None;
    last_error_tick_ = 0;
    last_error_address_ = 0xffffffffU;
    have_completed_transaction_ = false;
    last_transaction_end_4x_tick_ = 0;
    if (clear_memory)
        memory_.clear();
    identification_register0_ = device_profile_.identification_register0;
    identification_register1_ = device_profile_.identification_register1;
    configuration_register0_ = device_profile_.configuration_register0;
    configuration_register1_ = device_profile_.configuration_register1;
    refresh_active_ = false;
    next_refresh_start_4x_tick_ = device_profile_.refresh_interval_4x_ticks;
    refresh_busy_until_4x_tick_ = 0;
    reset_transaction();
}

void HyperramModel::set_device_profile(std::uint16_t id0, std::uint16_t id1,
                                       std::uint16_t config0,
                                       std::uint16_t config1,
                                       bool fixed_latency_rwds_high,
                                       bool variable_latency_supported,
                                       unsigned refresh_interval_4x_ticks,
                                       unsigned refresh_busy_4x_ticks,
                                       bool zero_latency_memory_writes,
                                       bool zero_latency_register_writes,
                                       bool zero_latency_write_rwds_low,
                                       unsigned t_rwr_4x_ticks,
                                       unsigned t_css_4x_ticks,
                                       unsigned t_reset_recovery_4x_ticks,
                                       bool reset_clears_memory,
                                       bool deep_power_down_supported,
                                       unsigned t_dpd_entry_4x_ticks,
                                       unsigned t_dpd_exit_4x_ticks,
                                       unsigned t_csd_pd_4x_ticks,
                                       bool hybrid_sleep_supported,
                                       unsigned t_hs_entry_4x_ticks,
                                       unsigned t_hs_exit_4x_ticks,
                                       unsigned t_cshs_4x_ticks,
                                       bool differential_clock_mode,
                                       unsigned t_ca_setup_4x_ticks,
                                       unsigned t_ca_hold_4x_ticks,
                                       unsigned t_write_setup_4x_ticks,
                                       unsigned t_write_hold_4x_ticks,
                                       bool inter_word_variable_latency_supported,
                                       unsigned inter_word_stall_edges,
                                       unsigned t_ck_high_min_4x_ticks,
                                       unsigned t_ck_low_min_4x_ticks)
{
    device_profile_.identification_register0 = id0;
    device_profile_.identification_register1 = id1;
    device_profile_.configuration_register0 = config0;
    device_profile_.configuration_register1 = config1;
    device_profile_.fixed_latency_rwds_high = fixed_latency_rwds_high;
    device_profile_.variable_latency_supported = variable_latency_supported;
    device_profile_.refresh_interval_4x_ticks = refresh_interval_4x_ticks;
    device_profile_.refresh_busy_4x_ticks = refresh_busy_4x_ticks;
    device_profile_.zero_latency_memory_writes = zero_latency_memory_writes;
    device_profile_.zero_latency_register_writes = zero_latency_register_writes;
    device_profile_.zero_latency_write_rwds_low = zero_latency_write_rwds_low;
    device_profile_.t_rwr_4x_ticks = t_rwr_4x_ticks;
    device_profile_.t_css_4x_ticks = t_css_4x_ticks;
    device_profile_.t_reset_recovery_4x_ticks = t_reset_recovery_4x_ticks;
    device_profile_.reset_clears_memory = reset_clears_memory;
    device_profile_.deep_power_down_supported = deep_power_down_supported;
    device_profile_.t_dpd_entry_4x_ticks = t_dpd_entry_4x_ticks;
    device_profile_.t_dpd_exit_4x_ticks = t_dpd_exit_4x_ticks;
    device_profile_.t_csd_pd_4x_ticks = t_csd_pd_4x_ticks;
    device_profile_.hybrid_sleep_supported = hybrid_sleep_supported;
    device_profile_.t_hs_entry_4x_ticks = t_hs_entry_4x_ticks;
    device_profile_.t_hs_exit_4x_ticks = t_hs_exit_4x_ticks;
    device_profile_.t_cshs_4x_ticks = t_cshs_4x_ticks;
    device_profile_.differential_clock_mode = differential_clock_mode;
    device_profile_.t_ca_setup_4x_ticks = t_ca_setup_4x_ticks;
    device_profile_.t_ca_hold_4x_ticks = t_ca_hold_4x_ticks;
    device_profile_.t_write_setup_4x_ticks = t_write_setup_4x_ticks;
    device_profile_.t_write_hold_4x_ticks = t_write_hold_4x_ticks;
    device_profile_.inter_word_variable_latency_supported =
        inter_word_variable_latency_supported;
    device_profile_.inter_word_stall_edges = inter_word_stall_edges;
    device_profile_.t_ck_high_min_4x_ticks = t_ck_high_min_4x_ticks;
    device_profile_.t_ck_low_min_4x_ticks = t_ck_low_min_4x_ticks;
}

void HyperramModel::set_zero_latency_support(bool memory_writes,
                                             bool register_writes,
                                             bool rwds_low)
{
    device_profile_.zero_latency_memory_writes = memory_writes;
    device_profile_.zero_latency_register_writes = register_writes;
    device_profile_.zero_latency_write_rwds_low = rwds_low;
}

void HyperramModel::set_memory_geometry(std::uint32_t bytes, bool rollover)
{
    device_profile_.memory_density_bytes = bytes;
    device_profile_.address_rollover = rollover;
}

void HyperramModel::set_interword_latency_for_test(bool enabled,
                                                    unsigned stall_edges)
{
    device_profile_.inter_word_variable_latency_supported = enabled;
    device_profile_.inter_word_stall_edges = stall_edges;
}

void HyperramModel::force_refresh_collision_for_test()
{
    refresh_active_ = true;
    refresh_busy_until_4x_tick_ = cycles_4x_ + 1000;
}

void HyperramModel::reset_transaction()
{
    bus_state_ = BusState::Idle;
    ca_bytes_received_ = 0;
    ca_expected_rising_edge_ = true;
    first_ca_seen_ = false;
    latency_edges_remaining_ = 0;
    read_stall_edges_remaining_ = 0;
    command_address_ = 0;
    word_address_ = 0;
    wrapped_burst_base_word_ = 0;
    wrapped_burst_words_ = 0;
    wrapped_burst_words_transferred_ = 0;
    byte_b_ = false;
    read_transfer_ = false;
    register_space_ = false;
    linear_burst_ = true;
    hybrid_burst_ = false;
    write_masks_enabled_ = true;
    word_phase_ = WordPhase::ByteA;
    pending_byte_a_ = 0;
    pending_byte_a_masked_ = false;
    dpd_entry_armed_ = false;
    hybrid_sleep_entry_armed_ = false;
    differential_clock_invalid_ = false;
    pending_input_.valid = false;
    additional_latency_ = false;
    dq_oe_ = false;
    dq_o_ = 0;
    rwds_oe_ = false;
    rwds_o_ = false;
}

void HyperramModel::update_device_state(bool reset_n, bool cs_n)
{
    // Reset is asynchronous to a transaction: it immediately aborts bus
    // activity and restores volatile state.  Memory retention is profile
    // controlled because it differs between device classes and test modes.
    if (!reset_n) {
        if (previous_reset_n_)
            apply_reset(device_profile_.reset_clears_memory);
        device_state_ = DeviceState::ResetRecovery;
        reset_transaction();
        previous_reset_n_ = false;
        return;
    }
    if (!previous_reset_n_) {
        device_state_deadline_4x_tick_ = cycles_4x_ +
            device_profile_.t_reset_recovery_4x_ticks;
        device_state_ = device_profile_.t_reset_recovery_4x_ticks == 0
            ? DeviceState::Active : DeviceState::ResetRecovery;
    }
    previous_reset_n_ = true;

    if (device_state_ == DeviceState::ResetRecovery &&
        cycles_4x_ >= device_state_deadline_4x_tick_)
        device_state_ = DeviceState::Active;
    if (device_state_ == DeviceState::DeepPowerDownEntry &&
        cycles_4x_ >= device_state_deadline_4x_tick_)
        device_state_ = DeviceState::DeepPowerDown;
    if (device_state_ == DeviceState::DeepPowerDownRecovery &&
        cycles_4x_ >= device_state_deadline_4x_tick_) {
        device_state_ = DeviceState::Active;
        configuration_register0_ |= 0x8000U;
    }
    if (device_state_ == DeviceState::HybridSleepEntry &&
        cycles_4x_ >= device_state_deadline_4x_tick_)
        device_state_ = DeviceState::HybridSleep;
    if (device_state_ == DeviceState::HybridSleepRecovery &&
        cycles_4x_ >= device_state_deadline_4x_tick_) {
        device_state_ = DeviceState::Active;
        configuration_register1_ &= static_cast<std::uint16_t>(~0x0020U);
    }

    // A CS# Low pulse of at least tCSDPD is the profile-defined DPD exit
    // request.  No CA/data is consumed while the device is asleep.
    if (device_state_ == DeviceState::DeepPowerDown) {
        if (!cs_n && previous_cs_n_) {
            dpd_wake_cs_assert_4x_tick_ = cycles_4x_;
            dpd_wake_cs_active_ = true;
        }
        if (cs_n && !previous_cs_n_ && dpd_wake_cs_active_) {
            if (cycles_4x_ - dpd_wake_cs_assert_4x_tick_ >=
                device_profile_.t_csd_pd_4x_ticks) {
                device_state_ = DeviceState::DeepPowerDownRecovery;
                device_state_deadline_4x_tick_ = cycles_4x_ +
                    device_profile_.t_dpd_exit_4x_ticks;
            } else {
                report_error(ErrorCode::PowerState);
            }
            dpd_wake_cs_active_ = false;
        }
    }

    // Hybrid sleep preserves memory and uses the same qualified-CS# wake
    // shape as the supplied device profile, but has independent timings and
    // does not alter CR0.  The CR1 request bit clears after wake recovery.
    if (device_state_ == DeviceState::HybridSleep) {
        if (!cs_n && previous_cs_n_) {
            hybrid_sleep_wake_cs_assert_4x_tick_ = cycles_4x_;
            hybrid_sleep_wake_cs_active_ = true;
        }
        if (cs_n && !previous_cs_n_ && hybrid_sleep_wake_cs_active_) {
            if (cycles_4x_ - hybrid_sleep_wake_cs_assert_4x_tick_ >=
                device_profile_.t_cshs_4x_ticks) {
                device_state_ = DeviceState::HybridSleepRecovery;
                device_state_deadline_4x_tick_ = cycles_4x_ +
                    device_profile_.t_hs_exit_4x_ticks;
            } else {
                report_error(ErrorCode::PowerState);
            }
            hybrid_sleep_wake_cs_active_ = false;
        }
    }
}

void HyperramModel::update_refresh_state()
{
    const unsigned interval = device_profile_.refresh_interval_4x_ticks;
    const unsigned duration = device_profile_.refresh_busy_4x_ticks;
    if (!device_profile_.variable_latency_supported || interval == 0 ||
        duration == 0)
        return;

    while (cycles_4x_ >= next_refresh_start_4x_tick_) {
        refresh_active_ = true;
        refresh_busy_until_4x_tick_ = cycles_4x_ + duration;
        next_refresh_start_4x_tick_ += interval;
    }
    if (refresh_active_ && cycles_4x_ >= refresh_busy_until_4x_tick_)
        refresh_active_ = false;
}

void HyperramModel::report_error(ErrorCode code, std::uint32_t address)
{
    ++protocol_errors_;
    last_error_code_ = code;
    last_error_tick_ = cycles_4x_;
    last_error_address_ = address;
}

void HyperramModel::tick()
{
    ++cycles_;
}

void HyperramModel::update_input_stability(std::uint8_t dq, bool rwds)
{
    if (dq != previous_dq_) {
        previous_dq_ = dq;
        last_dq_change_4x_tick_ = cycles_4x_;
    }
    if (rwds != previous_rwds_) {
        previous_rwds_ = rwds;
        last_rwds_change_4x_tick_ = cycles_4x_;
    }
}

void HyperramModel::complete_pending_input(std::uint8_t dq, bool rwds)
{
    if (!pending_input_.valid || cycles_4x_ - pending_input_.edge_4x_tick <
        pending_input_.hold_4x_ticks)
        return;
    if (dq != pending_input_.dq || rwds != pending_input_.rwds)
        report_error(ErrorCode::InputTiming);
    else
        process_bus_edge(pending_input_.dq, pending_input_.rwds,
                         pending_input_.rising_edge);
    pending_input_.valid = false;
}

void HyperramModel::accept_bus_edge(std::uint8_t dq, bool rwds, bool rising_edge)
{
    unsigned setup = 0;
    unsigned hold = 0;
    if (bus_state_ == BusState::CommandAddress) {
        setup = device_profile_.t_ca_setup_4x_ticks;
        hold = device_profile_.t_ca_hold_4x_ticks;
    } else if (bus_state_ == BusState::Write) {
        setup = device_profile_.t_write_setup_4x_ticks;
        hold = device_profile_.t_write_hold_4x_ticks;
    } else {
        process_bus_edge(dq, rwds, rising_edge);
        return;
    }
    const bool dq_ready = cycles_4x_ - last_dq_change_4x_tick_ >= setup;
    const bool rwds_ready = bus_state_ != BusState::Write ||
        cycles_4x_ - last_rwds_change_4x_tick_ >= setup;
    if (!dq_ready || !rwds_ready || pending_input_.valid) {
        report_error(ErrorCode::InputTiming);
        return;
    }
    if (hold == 0)
        process_bus_edge(dq, rwds, rising_edge);
    else
        pending_input_ = {true, dq, rwds, rising_edge, cycles_4x_, hold};
}

void HyperramModel::tick_4x(bool reset_n, bool clk, bool cs_n, bool ck, bool ck_n,
                            std::uint8_t dq, bool rwds)
{
    ++cycles_4x_;
    update_input_stability(dq, rwds);
    complete_pending_input(dq, rwds);
    update_device_state(reset_n, cs_n);
    if (device_state_ == DeviceState::Active)
        update_refresh_state();

    // Each 4x-clock pulse samples the main clock and records any transition.
    if (clk && !previous_main_clk_) {
        main_clk_edge_ = MainClockEdge::Rising;
        ++main_clk_rising_edges_;
    } else if (!clk && previous_main_clk_) {
        main_clk_edge_ = MainClockEdge::Falling;
        ++main_clk_falling_edges_;
    } else {
        main_clk_edge_ = MainClockEdge::None;
    }
    previous_main_clk_ = clk;

    if (device_state_ != DeviceState::Active) {
        if (!cs_n && previous_cs_n_ &&
            device_state_ != DeviceState::DeepPowerDown &&
            device_state_ != DeviceState::HybridSleep)
            report_error(ErrorCode::PowerState);
        reset_transaction();
        previous_cs_n_ = cs_n;
        previous_ck_ = ck;
        previous_ck_n_ = ck_n;
        return;
    }

    // CS# terminates the active transaction and releases the bidirectional IO.
    if (cs_n) {
        if (!previous_cs_n_) {
            // CS# may terminate traffic only with the clock pair parked in
            // its idle-low polarity.  Release outputs even when malformed.
            if (ck || (device_profile_.differential_clock_mode && !ck_n))
                report_error(ErrorCode::ChipSelect);
            if ((bus_state_ == BusState::Read || bus_state_ == BusState::Write) &&
                word_phase_ == WordPhase::ByteB)
                report_error(ErrorCode::TruncatedWord);
            last_transaction_end_4x_tick_ = cycles_4x_;
            have_completed_transaction_ = true;
        }
        reset_transaction();
        previous_cs_n_ = true;
        previous_ck_ = ck;
        previous_ck_n_ = ck_n;
        return;
    }

    if (previous_cs_n_) {
        bus_state_ = BusState::CommandAddress;
        ca_bytes_received_ = 0;
        ca_expected_rising_edge_ = true;
        first_ca_seen_ = false;
        cs_asserted_with_ck_low_ = !ck &&
            (!device_profile_.differential_clock_mode || ck_n);
        cs_assert_4x_tick_ = cycles_4x_;
        last_ck_transition_4x_tick_ = cycles_4x_;
        command_address_ = 0;
        dq_oe_ = false;
        // A slave owns RWDS during CA, before it has received enough CA
        // bits to know the transaction type.  The selected level is latched
        // for this transaction and selects one or two latency counts.
        if (configuration_register0_ & (1U << 3))
            additional_latency_ = device_profile_.fixed_latency_rwds_high;
        else
            additional_latency_ = device_profile_.variable_latency_supported &&
                                  refresh_active_;
        rwds_oe_ = true;
        rwds_o_ = additional_latency_;
    }
    previous_cs_n_ = false;

    // Single-ended parts use CK alone. Differential parts require a complete
    // complementary transition; malformed CK/CK# activity never advances the
    // CA/data stream.
    bool transfer_edge = false;
    if (!device_profile_.differential_clock_mode) {
        transfer_edge = ck != previous_ck_;
        differential_clock_invalid_ = false;
    } else {
        const bool pair_valid = ck != ck_n;
        const bool previous_pair_valid = previous_ck_ != previous_ck_n_;
        const bool ck_changed = ck != previous_ck_;
        const bool ck_n_changed = ck_n != previous_ck_n_;
        if (!pair_valid || !previous_pair_valid || ck_changed != ck_n_changed) {
            if (!differential_clock_invalid_)
                report_error(ErrorCode::Clock);
            differential_clock_invalid_ = true;
        } else {
            differential_clock_invalid_ = false;
            transfer_edge = ck_changed;
        }
    }
    if (transfer_edge)
    {
        const unsigned minimum_phase = previous_ck_
            ? device_profile_.t_ck_high_min_4x_ticks
            : device_profile_.t_ck_low_min_4x_ticks;
        if (cycles_4x_ - last_ck_transition_4x_tick_ < minimum_phase)
            report_error(ErrorCode::Clock);
        last_ck_transition_4x_tick_ = cycles_4x_;
        accept_bus_edge(dq, rwds, ck && !previous_ck_);
    }
    previous_ck_ = ck;
    previous_ck_n_ = ck_n;

}

void HyperramModel::process_bus_edge(std::uint8_t dq, bool rwds,
                                     bool rising_edge)
{
    switch (bus_state_) {
      case BusState::CommandAddress:
        if (rising_edge != ca_expected_rising_edge_)
            report_error(ErrorCode::Timing);
        if (!first_ca_seen_) {
            first_ca_seen_ = true;
            if (!cs_asserted_with_ck_low_ || !rising_edge)
                report_error(ErrorCode::ChipSelect);
            if (cycles_4x_ - cs_assert_4x_tick_ <
                device_profile_.t_css_4x_ticks)
                report_error(ErrorCode::Timing);
            if (have_completed_transaction_ &&
                cycles_4x_ - last_transaction_end_4x_tick_ <
                    device_profile_.t_rwr_4x_ticks)
                report_error(ErrorCode::Timing);
        }
        command_address_ = (command_address_ << 8) | dq;
        ++ca_bytes_received_;
        ca_expected_rising_edge_ = !ca_expected_rising_edge_;
        if (ca_bytes_received_ == CommandAddressBytes) {
            // CA[47] is 1 for read and 0 for write.  The HyperBus address is
            // split around the reserved CA bits [15:3].
            read_transfer_ = ((command_address_ >> 47) & 1U) != 0;
            register_space_ = ((command_address_ >> 46) & 1U) != 0;
            word_address_ = static_cast<std::uint32_t>(
                (((command_address_ >> 16) & 0x1fff'ffffULL) << 3) |
                (command_address_ & 0x7ULL));
            if (register_space_ &&
                (!supported_register_address(word_address_) ||
                 (!read_transfer_ && word_address_ < 0x800U))) {
                report_error(ErrorCode::UnsupportedCommand, word_address_);
                bus_state_ = BusState::Ignore;
                dq_oe_ = false;
                rwds_oe_ = false;
                break;
            }
            byte_b_ = false;
            linear_burst_ = ((command_address_ >> 45) & 1U) != 0;
            if (!linear_burst_) {
                wrapped_burst_words_ = wrapped_burst_words_from_cr0();
                wrapped_burst_base_word_ = word_address_ &
                    ~(static_cast<std::uint32_t>(wrapped_burst_words_) - 1U);
                wrapped_burst_words_transferred_ = 0;
                // CR0[2]=0 selects one wrapped window followed by linear
                // addressing. Register-space accesses remain simple linear
                // register streams in this model.
                hybrid_burst_ = !register_space_ &&
                    (configuration_register0_ & (1U << 2)) == 0;
            }
            const auto latency = selected_profile_
                ? selected_profile_->latency.initial_latency(configuration_register0_,
                                                              additional_latency_, false)
                : hyperram_profile::InitialLatency{7, additional_latency_};
            latency_edges_remaining_ = latency.clock_cycles * 2U;
            const bool zero_latency_write = !read_transfer_ &&
                ((register_space_ && device_profile_.zero_latency_register_writes) ||
                 (!register_space_ && device_profile_.zero_latency_memory_writes));
            if (zero_latency_write) {
                // Data starts on the next DDR edge. RWDS is not a mask in
                // this mode and is either low or high impedance by profile.
                bus_state_ = BusState::Write;
                write_masks_enabled_ = false;
                rwds_oe_ = device_profile_.zero_latency_write_rwds_low;
                rwds_o_ = false;
            } else {
                bus_state_ = BusState::Latency;
                // For writes with initial latency, hand RWDS ownership to
                // the master after CA so it can provide its mask preamble.
                if (!read_transfer_)
                    rwds_oe_ = false;
            }
        }
        break;

      case BusState::Latency:
        if (--latency_edges_remaining_ == 0)
            begin_transfer();
        break;

      case BusState::Write:
        write_data_byte(dq, rwds, rising_edge);
        break;

      case BusState::Read:
        if ((word_phase_ == WordPhase::ByteA) != rising_edge) {
            report_error(ErrorCode::Timing);
            break;
        }
        // Present the next byte after each transfer edge.  RWDS is the source
        // synchronous strobe used by the controller to capture DQ.
        dq_o_ = read_data_byte();
        rwds_o_ = !rwds_o_;
        if (word_phase_ == WordPhase::ByteA) {
            byte_b_ = true;
            word_phase_ = WordPhase::ByteB;
        } else {
            advance_data_byte();
            word_phase_ = WordPhase::ByteA;
            if (device_profile_.variable_latency_supported &&
                device_profile_.inter_word_variable_latency_supported &&
                refresh_active_ && device_profile_.inter_word_stall_edges != 0) {
                bus_state_ = BusState::ReadStall;
                read_stall_edges_remaining_ =
                    device_profile_.inter_word_stall_edges;
                // Hold RWDS High throughout the inserted delay.  The normal
                // low idle phase is restored before the next data edge.
                rwds_o_ = true;
            }
        }
        break;

      case BusState::ReadStall:
        if (--read_stall_edges_remaining_ == 0) {
            bus_state_ = BusState::Read;
            rwds_o_ = false;
        }
        break;

      case BusState::Idle:
      case BusState::Ignore:
        break;
    }
}

void HyperramModel::begin_transfer()
{
    if (read_transfer_) {
        bus_state_ = BusState::Read;
        dq_oe_ = true;
        rwds_oe_ = true;
        // RWDS is low while it is a latency indication.  The first byte is
        // driven when the next read-transfer edge raises RWDS.
        dq_o_ = 0;
        rwds_o_ = false;
        byte_b_ = false;
        word_phase_ = WordPhase::ByteA;
    } else {
        bus_state_ = BusState::Write;
        byte_b_ = false;
        word_phase_ = WordPhase::ByteA;
    }
}

std::uint8_t HyperramModel::read_data_byte()
{
    if (register_space_)
        return read_register_byte(word_address_, byte_b_);
    const auto address = (word_address_ << 1) | static_cast<unsigned>(byte_b_);
    if (device_profile_.memory_density_bytes != 0 &&
        address >= device_profile_.memory_density_bytes &&
        !device_profile_.address_rollover)
        report_error(ErrorCode::AddressRange, address);
    return read_byte(address);
}

std::uint8_t HyperramModel::read_register_byte(std::uint32_t word_address,
                                               bool byte_b) const
{
    std::uint16_t value = 0xffff;
    switch (word_address) {
      case 0x000: value = identification_register0_; break;
      case 0x001: value = identification_register1_; break;
      case 0x800: value = configuration_register0_; break;
      case 0x801: value = configuration_register1_; break;
      default: break;
    }
    return byte_b ? static_cast<std::uint8_t>(value)
                  : static_cast<std::uint8_t>(value >> 8);
}

void HyperramModel::write_data_byte(std::uint8_t dq, bool rwds,
                                    bool rising_edge)
{
    if ((word_phase_ == WordPhase::ByteA) != rising_edge) {
        report_error(ErrorCode::Timing);
        return;
    }

    if (word_phase_ == WordPhase::ByteA) {
        pending_byte_a_ = dq;
        pending_byte_a_masked_ = write_masks_enabled_ && rwds;
        byte_b_ = true;
        word_phase_ = WordPhase::ByteB;
        return;
    }

    const bool byte_b_masked = write_masks_enabled_ && rwds;
    if (!pending_byte_a_masked_) {
        if (register_space_)
            write_register_byte(word_address_, false, pending_byte_a_);
        else
            write_memory_byte(word_address_ << 1, pending_byte_a_);
    }
    if (!byte_b_masked) {
        if (register_space_)
            write_register_byte(word_address_, true, dq);
        else
            write_memory_byte((word_address_ << 1) | 1U, dq);
    }
    advance_data_byte();
    word_phase_ = WordPhase::ByteA;
}

void HyperramModel::write_register_byte(std::uint32_t word_address,
                                        bool byte_b, std::uint8_t value)
{
    auto write_byte = [byte_b, value](std::uint16_t& word) {
        if (byte_b)
            word = static_cast<std::uint16_t>((word & 0xff00U) | value);
        else
            word = static_cast<std::uint16_t>((word & 0x00ffU) |
                                              (static_cast<std::uint16_t>(value) << 8));
    };

    // Identification words are read-only. CR0/CR1 are volatile and changes
    // affect only transactions begun after this transaction completes.
    if (word_address == 0x800) {
        // DPD is requested by a complete CR0 1->0 update.  Capture the
        // transition while byte A is written, but enter only after byte B so
        // a byte-masked or truncated word cannot request power-down.
        if (!byte_b)
            dpd_entry_armed_ = device_profile_.deep_power_down_supported &&
                (configuration_register0_ & 0x8000U) != 0 &&
                (value & 0x80U) == 0;
        write_byte(configuration_register0_);
        // CR0[15] is restored to 1 after a successful wake-up.
        if (byte_b && dpd_entry_armed_ &&
            (configuration_register0_ & 0x8000U) == 0) {
            device_state_ = DeviceState::DeepPowerDownEntry;
            device_state_deadline_4x_tick_ = cycles_4x_ +
                device_profile_.t_dpd_entry_4x_ticks;
            reset_transaction();
        }
    } else if (word_address == 0x801) {
        // CR1[5] requests hybrid sleep.  As with DPD, require a complete
        // word write so a masked or truncated write cannot enter the state.
        if (!byte_b)
            hybrid_sleep_entry_armed_ =
                device_profile_.hybrid_sleep_supported &&
                (configuration_register1_ & 0x0020U) == 0;
        write_byte(configuration_register1_);
        if (byte_b && hybrid_sleep_entry_armed_ &&
            (configuration_register1_ & 0x0020U) != 0) {
            device_state_ = DeviceState::HybridSleepEntry;
            device_state_deadline_4x_tick_ = cycles_4x_ +
                device_profile_.t_hs_entry_4x_ticks;
            reset_transaction();
        }
    }
}

void HyperramModel::advance_data_byte()
{
    byte_b_ = !byte_b_;
    if (!byte_b_) {
        if (linear_burst_)
            ++word_address_;
        else {
            ++wrapped_burst_words_transferred_;
            word_address_ = wrapped_burst_base_word_ |
                ((word_address_ + 1U) &
                 (static_cast<std::uint32_t>(wrapped_burst_words_) - 1U));
            if (hybrid_burst_ &&
                wrapped_burst_words_transferred_ == wrapped_burst_words_) {
                word_address_ = wrapped_burst_base_word_ + wrapped_burst_words_;
                linear_burst_ = true;
            }
        }
    }
}

unsigned HyperramModel::wrapped_burst_words_from_cr0() const
{
    // CR0[1:0] defines a power-of-two byte window. Convert to 16-bit words.
    switch (configuration_register0_ & 0x3U) {
      case 0x0: return 64; // 128 bytes
      case 0x1: return 32; // 64 bytes
      case 0x2: return 8;  // 16 bytes
      default: return 16;  // 32 bytes
    }
}

std::uint8_t HyperramModel::read_byte(std::uint32_t address) const
{
    if (!normalize_memory_address(address))
        return 0xff;
    const auto it = memory_.find(address);
    return it == memory_.end() ? 0xff : it->second;
}

bool HyperramModel::supported_register_address(std::uint32_t word_address) const
{
    return word_address == 0x000 || word_address == 0x001 ||
           word_address == 0x800 || word_address == 0x801;
}

bool HyperramModel::normalize_memory_address(std::uint32_t& address) const
{
    const auto bytes = device_profile_.memory_density_bytes;
    if (bytes == 0 || address < bytes)
        return true;
    if (!device_profile_.address_rollover)
        return false;
    address %= bytes;
    return true;
}

bool HyperramModel::write_memory_byte(std::uint32_t address, std::uint8_t value)
{
    if (!normalize_memory_address(address)) {
        report_error(ErrorCode::AddressRange, address);
        return false;
    }
    memory_[address] = value;
    return true;
}

bool HyperramModel::dq_oe() const { return dq_oe_; }
std::uint8_t HyperramModel::dq_o() const { return dq_o_; }
bool HyperramModel::rwds_oe() const { return rwds_oe_; }
bool HyperramModel::rwds_o() const { return rwds_o_; }
std::uint8_t HyperramModel::debug_read_byte(std::uint32_t address) const
{
    return read_byte(address);
}
std::uint16_t HyperramModel::debug_configuration_register0() const
{
    return configuration_register0_;
}
std::uint16_t HyperramModel::debug_configuration_register1() const
{
    return configuration_register1_;
}
bool HyperramModel::debug_refresh_active() const { return refresh_active_; }
unsigned HyperramModel::debug_device_state() const
{
    return static_cast<unsigned>(device_state_);
}
unsigned HyperramModel::debug_bus_state() const
{
    return static_cast<unsigned>(bus_state_);
}
unsigned HyperramModel::debug_protocol_errors() const { return protocol_errors_; }
unsigned HyperramModel::debug_last_error_code() const
{
    return static_cast<unsigned>(last_error_code_);
}
std::uint64_t HyperramModel::debug_last_error_tick() const
{
    return last_error_tick_;
}
std::uint32_t HyperramModel::debug_last_error_address() const
{
    return last_error_address_;
}

static HyperramModel model;

extern "C" {

unsigned char hyperram_model_select_profile(const char* name)
{
    return model.select_profile(name) ? 1 : 0;
}

unsigned long long hyperram_model_output_timing(unsigned int index)
{
    return model.output_timing(index);
}

void hyperram_model_reset() { model.reset(); }
void hyperram_model_tick() { model.tick(); }

void hyperram_model_tick_4x(unsigned char reset_n, unsigned char clk, unsigned char cs_n,
                            unsigned char ck, unsigned char ck_n,
                            unsigned char dq, unsigned char rwds)
{
    model.tick_4x(reset_n != 0, clk != 0, cs_n != 0, ck != 0, ck_n != 0,
                  dq, rwds != 0);
}

void hyperram_model_set_zero_latency_support(unsigned char memory_writes,
                                             unsigned char register_writes,
                                             unsigned char rwds_low)
{
    model.set_zero_latency_support(memory_writes != 0, register_writes != 0,
                                   rwds_low != 0);
}

void hyperram_model_set_memory_geometry(unsigned int bytes,
                                        unsigned char rollover)
{
    model.set_memory_geometry(bytes, rollover != 0);
}
void hyperram_model_set_interword_latency_for_test(unsigned char enabled,
                                                    unsigned int stall_edges)
{
    model.set_interword_latency_for_test(enabled != 0, stall_edges);
}
void hyperram_model_force_refresh_collision_for_test()
{
    model.force_refresh_collision_for_test();
}

unsigned char hyperram_model_dq_oe() { return model.dq_oe() ? 1 : 0; }
unsigned char hyperram_model_dq_o() { return model.dq_o(); }
unsigned char hyperram_model_rwds_oe() { return model.rwds_oe() ? 1 : 0; }
unsigned char hyperram_model_rwds_o() { return model.rwds_o() ? 1 : 0; }
unsigned char hyperram_model_read_byte(unsigned int address)
{
    return model.debug_read_byte(address);
}
unsigned int hyperram_model_read_configuration_register0()
{
    return model.debug_configuration_register0();
}
unsigned int hyperram_model_read_configuration_register1()
{
    return model.debug_configuration_register1();
}
unsigned char hyperram_model_refresh_active()
{
    return model.debug_refresh_active() ? 1 : 0;
}
unsigned int hyperram_model_device_state()
{
    return model.debug_device_state();
}
unsigned int hyperram_model_bus_state()
{
    return model.debug_bus_state();
}
unsigned int hyperram_model_protocol_errors()
{
    return model.debug_protocol_errors();
}
unsigned int hyperram_model_last_error_code()
{
    return model.debug_last_error_code();
}
unsigned long long hyperram_model_last_error_tick()
{
    return model.debug_last_error_tick();
}
unsigned int hyperram_model_last_error_address()
{
    return model.debug_last_error_address();
}

}
