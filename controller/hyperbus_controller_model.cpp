#include <cstdint>

#include "profiles/chip_profile.hpp"

// Cycle-scheduled HyperBus master-model core.  This intentionally begins as
// a safe transaction-shell: it accepts the simple request interface and
// reports an unsupported completion until pin-level transfer states are added.
class HyperbusControllerModel {
  public:
    void reset();
    void set_configuration_register0(std::uint16_t value);
    void set_zero_latency_write_support(bool memory_writes,
                                        bool register_writes,
                                        bool rwds_low);
    void set_variable_read_latency_support(bool variable_latency,
                                           bool inter_word_latency,
                                           unsigned stall_timeout_edges);
    void set_timing_profile(unsigned t_rwr, unsigned t_css,
                            unsigned t_ca_setup, unsigned t_ca_hold,
                            unsigned t_write_setup, unsigned t_write_hold,
                            unsigned t_ck_high_min, unsigned t_ck_low_min);
    void set_read_sampling_profile(unsigned rwds_qualify_ticks,
                                   unsigned dq_sample_delay_ticks,
                                   unsigned sample_timeout_ticks);
    void set_read_error_profile(unsigned initial_strobe_timeout_ticks,
                                unsigned byte_b_timeout_ticks,
                                bool unexpected_rwds_fatal);
    void set_memory_geometry(std::uint32_t bytes, bool rollover);
    void set_reset_recovery(unsigned ticks);
    void set_profile_discovery(bool enabled, bool adopt_cr0,
                               std::uint16_t id0, std::uint16_t id1,
                               std::uint16_t cr0, std::uint16_t cr1);
    bool select_profile(const char* name);
    void tick_system(bool reset_n, bool request_valid, bool request_write,
                     bool request_register_space, bool request_linear_burst,
                     std::uint32_t request_address, unsigned request_words,
                     bool write_valid, std::uint16_t write_data,
                     std::uint8_t write_mask, bool read_ready,
                     bool response_ready);
    void tick_4x(bool reset_n, std::uint8_t dq, bool rwds);

    bool request_ready() const;
    bool write_ready() const;
    bool read_valid() const;
    std::uint16_t read_data() const;
    bool read_last() const;
    bool response_valid() const;
    bool response_error() const;
    unsigned response_code() const;
    bool init_valid() const;
    bool init_error() const;
    unsigned init_code() const;

    bool cs_n() const;
    bool ck() const;
    bool ck_n() const;
    bool dq_oe() const;
    std::uint8_t dq_o() const;
    bool rwds_oe() const;
    bool rwds_o() const;

  private:
    enum class State {
        Idle, InitStart, InitWaitRead, InitWaitReadPinEnd, Validate, WaitRead, WaitReadPinEnd, WaitWrite,
        WaitWritePinEnd, Respond
    };
    enum class PinState {
        Idle, CsSetup, DriveCa, SendCa, LatencySample, Latency,
        ReadClock, ReadHold, ReadStall, WriteWaitData, WriteByteA, WriteDriveByteB,
        WriteByteB, WriteHold
    };
    enum class ResponseCode : unsigned {
        Ok = 0,
        Unsupported = 1,
        InvalidLength = 2,
        UnalignedAddress = 3,
        ReadStallTimeout = 4,
        ReadProtocolError = 5,
        ReadStrobeTimeout = 6,
        ReadSampleTimeout = 7,
        AddressOutOfRange = 8, ProfileMismatch = 9
    };

    void apply_configuration_register0_write(std::uint16_t data,
                                             std::uint8_t mask);
    unsigned ca_setup_delay() const;
    unsigned ca_hold_delay() const;
    unsigned write_setup_delay() const;
    unsigned write_hold_delay() const;
    unsigned clock_phase_delay() const;
    void abort_read(ResponseCode code);

    State state_ = State::Idle;
    PinState pin_state_ = PinState::Idle;
    bool response_valid_ = false;
    ResponseCode response_code_ = ResponseCode::Ok;
    bool request_write_ = false;
    bool request_register_space_ = false;
    bool request_linear_burst_ = true;
    std::uint32_t request_address_ = 0;
    unsigned request_words_ = 0;
    std::uint64_t command_address_ = 0;
    unsigned ca_byte_index_ = 0;
    unsigned pin_delay_4x_ticks_ = 0;
    bool ca_start_requested_ = false;
    bool ca_complete_ = false;
    unsigned words_remaining_ = 0;
    bool read_end_requested_ = false;
    bool read_resume_requested_ = false;
    bool read_pin_end_complete_ = false;
    std::uint16_t configuration_register0_reset_ = 0x8f8f;
    std::uint16_t configuration_register0_ = 0x8f8f;
    bool zero_latency_memory_writes_ = false;
    bool zero_latency_register_writes_ = false;
    bool zero_latency_write_rwds_low_ = false;
    bool variable_latency_supported_ = false;
    bool inter_word_variable_latency_supported_ = false;
    unsigned read_stall_timeout_edges_ = 64;
    unsigned read_stall_edges_elapsed_ = 0;
    ResponseCode read_completion_code_ = ResponseCode::Ok;
    unsigned t_rwr_4x_ticks_ = 0;
    unsigned t_css_4x_ticks_ = 0;
    unsigned t_ca_setup_4x_ticks_ = 0;
    unsigned t_ca_hold_4x_ticks_ = 0;
    unsigned t_write_setup_4x_ticks_ = 0;
    unsigned t_write_hold_4x_ticks_ = 0;
    unsigned t_ck_high_min_4x_ticks_ = 0;
    unsigned t_ck_low_min_4x_ticks_ = 0;
    std::uint64_t cycles_4x_ = 0;
    std::uint64_t request_earliest_4x_tick_ = 0;
    unsigned reset_recovery_4x_ticks_ = 0;
    unsigned latency_edges_remaining_ = 0;
    bool previous_rwds_ = false;
    bool read_strobe_candidate_ = false;
    bool read_strobe_candidate_level_ = false;
    unsigned read_strobe_stable_ticks_ = 0;
    bool read_sample_pending_ = false;
    bool read_sample_byte_a_ = false;
    unsigned read_sample_delay_ticks_ = 0;
    unsigned rwds_qualify_4x_ticks_ = 0;
    unsigned dq_sample_delay_4x_ticks_ = 0;
    unsigned read_sample_timeout_4x_ticks_ = 64;
    unsigned read_sample_elapsed_ticks_ = 0;
    unsigned initial_read_strobe_timeout_4x_ticks_ = 0;
    unsigned read_byte_b_timeout_4x_ticks_ = 0;
    bool unexpected_rwds_fatal_ = true;
    unsigned read_strobe_wait_ticks_ = 0;
    std::uint32_t memory_density_bytes_ = 0;
    bool address_rollover_ = true;
    bool auto_profile_discovery_ = false, adopt_discovered_cr0_ = false;
    bool initialization_complete_ = true, initialization_error_ = false;
    std::uint16_t expected_id0_ = 0x0c81, expected_id1_ = 0x0001, expected_cr0_ = 0x8f8f, expected_cr1_ = 0xffc1;
    std::uint16_t discovered_[4] = {};
    unsigned discovery_index_ = 0;
    bool read_byte_a_seen_ = false;
    std::uint8_t read_byte_a_ = 0;
    bool read_valid_ = false;
    std::uint16_t read_data_ = 0;
    bool read_last_ = false;
    bool write_data_available_ = false;
    std::uint16_t write_data_ = 0;
    std::uint8_t write_mask_ = 0;
    bool write_masks_enabled_ = true;
    bool write_updates_configuration_register0_ = false;
    bool write_pin_end_complete_ = false;
    const controller_profile::ChipProfile* selected_profile_ = nullptr;
    bool cs_n_ = true;
    bool ck_ = false;
    bool dq_oe_ = false;
    std::uint8_t dq_o_ = 0;
    bool rwds_oe_ = false;
    bool rwds_o_ = false;
};

bool HyperbusControllerModel::select_profile(const char* name)
{
    const auto* profile = controller_profile::find(name ? name : "");
    if (!profile)
        return false;
    selected_profile_ = profile;
    set_configuration_register0(profile->cr0);
    set_zero_latency_write_support(profile->zero_latency_memory_writes,
        profile->zero_latency_register_writes, profile->zero_latency_write_rwds_low);
    set_variable_read_latency_support(profile->variable_latency_supported,
        profile->inter_word_variable_latency_supported, profile->read_stall_timeout_edges);
    set_timing_profile(profile->t_rwr_4x_ticks, profile->t_css_4x_ticks,
        profile->t_ca_setup_4x_ticks, profile->t_ca_hold_4x_ticks,
        profile->t_write_setup_4x_ticks, profile->t_write_hold_4x_ticks,
        profile->t_ck_high_min_4x_ticks, profile->t_ck_low_min_4x_ticks);
    set_read_sampling_profile(profile->rwds_qualify_4x_ticks,
        profile->dq_sample_delay_4x_ticks, profile->read_sample_timeout_4x_ticks);
    set_read_error_profile(profile->initial_read_strobe_timeout_4x_ticks,
        profile->read_byte_b_timeout_4x_ticks, profile->unexpected_rwds_fatal);
    set_memory_geometry(profile->memory_density_bytes, profile->address_rollover);
    set_reset_recovery(profile->t_reset_recovery_4x_ticks);
    set_profile_discovery(profile->auto_profile_discovery, profile->adopt_discovered_cr0,
        profile->id0, profile->id1, profile->cr0, profile->cr1);
    return true;
}

void HyperbusControllerModel::reset()
{
    state_ = State::Idle;
    response_valid_ = false;
    response_code_ = ResponseCode::Ok;
    initialization_complete_ = !auto_profile_discovery_;
    initialization_error_ = false;
    discovery_index_ = 0;
    request_write_ = false;
    request_register_space_ = false;
    request_linear_burst_ = true;
    request_address_ = 0;
    request_words_ = 0;
    cycles_4x_ = 0;
    request_earliest_4x_tick_ = 0;
    configuration_register0_ = configuration_register0_reset_;
    command_address_ = 0;
    ca_byte_index_ = 0;
    pin_delay_4x_ticks_ = 0;
    ca_start_requested_ = false;
    ca_complete_ = false;
    words_remaining_ = 0;
    read_end_requested_ = false;
    read_resume_requested_ = false;
    read_pin_end_complete_ = false;
    read_stall_edges_elapsed_ = 0;
    read_completion_code_ = ResponseCode::Ok;
    latency_edges_remaining_ = 0;
    previous_rwds_ = false;
    read_strobe_candidate_ = false;
    read_strobe_candidate_level_ = false;
    read_strobe_stable_ticks_ = 0;
    read_sample_pending_ = false;
    read_sample_byte_a_ = false;
    read_sample_delay_ticks_ = 0;
    read_sample_elapsed_ticks_ = 0;
    read_strobe_wait_ticks_ = 0;
    read_byte_a_seen_ = false;
    read_byte_a_ = 0;
    read_valid_ = false;
    read_data_ = 0;
    read_last_ = false;
    write_data_available_ = false;
    write_data_ = 0;
    write_mask_ = 0;
    write_masks_enabled_ = true;
    write_updates_configuration_register0_ = false;
    write_pin_end_complete_ = false;
    pin_state_ = PinState::Idle;
    cs_n_ = true;
    ck_ = false;
    dq_oe_ = false;
    dq_o_ = 0;
    rwds_oe_ = false;
    rwds_o_ = false;
}

void HyperbusControllerModel::set_configuration_register0(std::uint16_t value)
{
    configuration_register0_reset_ = value;
    configuration_register0_ = value;
}

void HyperbusControllerModel::set_zero_latency_write_support(
    bool memory_writes, bool register_writes, bool rwds_low)
{
    zero_latency_memory_writes_ = memory_writes;
    zero_latency_register_writes_ = register_writes;
    zero_latency_write_rwds_low_ = rwds_low;
}

void HyperbusControllerModel::set_variable_read_latency_support(
    bool variable_latency, bool inter_word_latency,
    unsigned stall_timeout_edges)
{
    variable_latency_supported_ = variable_latency;
    inter_word_variable_latency_supported_ = inter_word_latency;
    read_stall_timeout_edges_ = stall_timeout_edges;
}

void HyperbusControllerModel::set_timing_profile(
    unsigned t_rwr, unsigned t_css, unsigned t_ca_setup, unsigned t_ca_hold,
    unsigned t_write_setup, unsigned t_write_hold, unsigned t_ck_high_min,
    unsigned t_ck_low_min)
{
    t_rwr_4x_ticks_ = t_rwr;
    t_css_4x_ticks_ = t_css;
    t_ca_setup_4x_ticks_ = t_ca_setup;
    t_ca_hold_4x_ticks_ = t_ca_hold;
    t_write_setup_4x_ticks_ = t_write_setup;
    t_write_hold_4x_ticks_ = t_write_hold;
    t_ck_high_min_4x_ticks_ = t_ck_high_min;
    t_ck_low_min_4x_ticks_ = t_ck_low_min;
}

void HyperbusControllerModel::set_read_sampling_profile(
    unsigned rwds_qualify_ticks, unsigned dq_sample_delay_ticks,
    unsigned sample_timeout_ticks)
{
    rwds_qualify_4x_ticks_ = rwds_qualify_ticks;
    dq_sample_delay_4x_ticks_ = dq_sample_delay_ticks;
    read_sample_timeout_4x_ticks_ = sample_timeout_ticks;
}

void HyperbusControllerModel::set_read_error_profile(
    unsigned initial_strobe_timeout_ticks, unsigned byte_b_timeout_ticks,
    bool unexpected_rwds_fatal)
{
    initial_read_strobe_timeout_4x_ticks_ = initial_strobe_timeout_ticks;
    read_byte_b_timeout_4x_ticks_ = byte_b_timeout_ticks;
    unexpected_rwds_fatal_ = unexpected_rwds_fatal;
}

void HyperbusControllerModel::set_memory_geometry(std::uint32_t bytes,
                                                   bool rollover)
{
    memory_density_bytes_ = bytes;
    address_rollover_ = rollover;
}
void HyperbusControllerModel::set_reset_recovery(unsigned ticks) { reset_recovery_4x_ticks_ = ticks; }
void HyperbusControllerModel::set_profile_discovery(bool enabled, bool adopt_cr0,
    std::uint16_t id0, std::uint16_t id1, std::uint16_t cr0, std::uint16_t cr1)
{
    auto_profile_discovery_ = enabled;
    adopt_discovered_cr0_ = adopt_cr0;
    expected_id0_ = id0; expected_id1_ = id1;
    expected_cr0_ = cr0; expected_cr1_ = cr1;
    initialization_complete_ = !enabled;
    initialization_error_ = false;
}

void HyperbusControllerModel::abort_read(ResponseCode code)
{
    // A failed read never publishes a partially assembled word. Return the
    // shared pins to their inactive state and observe normal tRWR before the
    // next request.
    read_valid_ = false;
    read_last_ = false;
    read_strobe_candidate_ = false;
    read_sample_pending_ = false;
    read_completion_code_ = code;
    dq_oe_ = false;
    rwds_oe_ = false;
    cs_n_ = true;
    ck_ = false;
    request_earliest_4x_tick_ = cycles_4x_ + t_rwr_4x_ticks_;
    pin_state_ = PinState::Idle;
    read_pin_end_complete_ = true;
    state_ = State::WaitReadPinEnd;
}

unsigned HyperbusControllerModel::ca_setup_delay() const
{
    return t_ca_setup_4x_ticks_ > 1 ? t_ca_setup_4x_ticks_ : 1;
}
unsigned HyperbusControllerModel::ca_hold_delay() const
{
    const unsigned phase_min = ck_ ? t_ck_high_min_4x_ticks_
                                   : t_ck_low_min_4x_ticks_;
    const unsigned value = t_ca_hold_4x_ticks_ > phase_min
                               ? t_ca_hold_4x_ticks_ : phase_min;
    return value > 1 ? value : 1;
}
unsigned HyperbusControllerModel::write_setup_delay() const
{
    return t_write_setup_4x_ticks_ > 1 ? t_write_setup_4x_ticks_ : 1;
}
unsigned HyperbusControllerModel::write_hold_delay() const
{
    const unsigned phase_min = ck_ ? t_ck_high_min_4x_ticks_
                                   : t_ck_low_min_4x_ticks_;
    const unsigned value = t_write_hold_4x_ticks_ > phase_min
                               ? t_write_hold_4x_ticks_ : phase_min;
    return value > 1 ? value : 1;
}
unsigned HyperbusControllerModel::clock_phase_delay() const
{
    const unsigned phase_min = ck_ ? t_ck_high_min_4x_ticks_
                                   : t_ck_low_min_4x_ticks_;
    return phase_min > 2 ? phase_min : 2;
}

void HyperbusControllerModel::apply_configuration_register0_write(
    std::uint16_t data, std::uint8_t mask)
{
    if ((mask & 0x2U) == 0)
        configuration_register0_ = static_cast<std::uint16_t>(
            (configuration_register0_ & 0x00ffU) | (data & 0xff00U));
    if ((mask & 0x1U) == 0)
        configuration_register0_ = static_cast<std::uint16_t>(
            (configuration_register0_ & 0xff00U) | (data & 0x00ffU));
}

void HyperbusControllerModel::tick_system(bool reset_n, bool request_valid,
                                          bool request_write,
                                          bool request_register_space,
                                          bool request_linear_burst,
                                          std::uint32_t request_address,
                                          unsigned request_words,
                                          bool write_valid,
                                          std::uint16_t write_data,
                                          std::uint8_t write_mask,
                                          bool read_ready,
                                          bool response_ready)
{
    if (!reset_n) {
        reset();
        return;
    }

    switch (state_) {
      case State::Idle:
        if (cycles_4x_ < reset_recovery_4x_ticks_)
            break;
        if (!initialization_complete_) {
            if (!initialization_error_)
                state_ = State::InitStart;
            break;
        }
        if (request_valid && request_ready()) {
            request_write_ = request_write;
            request_register_space_ = request_register_space;
            request_linear_burst_ = request_linear_burst;
            request_address_ = request_address;
            request_words_ = request_words;
            state_ = State::Validate;
        }
        break;
      case State::InitStart: {
        request_write_ = false; request_register_space_ = true;
        request_linear_burst_ = true;
        request_address_ = (discovery_index_ < 2 ? discovery_index_ : 0x800U + discovery_index_ - 2U) * 2U;
        request_words_ = 1;
        const std::uint32_t word_address = request_address_ >> 1;
        command_address_ = (std::uint64_t{1} << 47) | (std::uint64_t{1} << 46) |
            (std::uint64_t{1} << 45) | ((std::uint64_t{word_address >> 3} & 0x1fff'ffffULL) << 16) |
            (word_address & 0x7U);
        words_remaining_ = 1; read_end_requested_ = false;
        read_pin_end_complete_ = false; read_valid_ = false;
        read_byte_a_seen_ = false; ca_start_requested_ = true;
        state_ = State::InitWaitRead;
        break;
      }
      case State::InitWaitRead:
        if (read_valid_) {
            discovered_[discovery_index_] = read_data_;
            read_valid_ = false; read_last_ = false;
            --words_remaining_; read_end_requested_ = true;
            state_ = State::InitWaitReadPinEnd;
        }
        break;
      case State::InitWaitReadPinEnd:
        if (read_pin_end_complete_) {
            if (++discovery_index_ < 4) state_ = State::InitStart;
            else {
                const bool mismatch = discovered_[0] != expected_id0_ ||
                    discovered_[1] != expected_id1_ || discovered_[3] != expected_cr1_ ||
                    (!adopt_discovered_cr0_ && discovered_[2] != expected_cr0_);
                if (mismatch) initialization_error_ = true;
                else if (adopt_discovered_cr0_) configuration_register0_ = discovered_[2];
                initialization_complete_ = true;
                state_ = State::Idle;
            }
        }
        break;
      case State::Validate:
        if (request_words_ == 0)
            response_code_ = ResponseCode::InvalidLength;
        else if (request_address_ & 1U)
            response_code_ = ResponseCode::UnalignedAddress;
        else if (!request_register_space_ && memory_density_bytes_ != 0 &&
                 !address_rollover_ &&
                 (static_cast<std::uint64_t>(request_address_) >=
                      memory_density_bytes_ ||
                  static_cast<std::uint64_t>(request_words_) * 2U >
                      static_cast<std::uint64_t>(memory_density_bytes_) -
                          request_address_))
            response_code_ = ResponseCode::AddressOutOfRange;
        else {
            const std::uint32_t word_address = request_address_ >> 1;
            command_address_ = (request_write_ ? 0 : (std::uint64_t{1} << 47)) |
                               (request_register_space_ ?
                                    (std::uint64_t{1} << 46) : 0) |
                               (request_linear_burst_ ?
                                    (std::uint64_t{1} << 45) : 0) |
                               ((std::uint64_t{word_address >> 3} &
                                 0x1fff'ffffULL) << 16) |
                               (word_address & 0x7U);
            ca_complete_ = false;
            words_remaining_ = request_words_;
            read_end_requested_ = false;
            read_resume_requested_ = false;
            read_pin_end_complete_ = false;
            read_stall_edges_elapsed_ = 0;
            read_completion_code_ = ResponseCode::Ok;
            read_strobe_candidate_ = false;
            read_sample_pending_ = false;
            read_strobe_wait_ticks_ = 0;
            write_pin_end_complete_ = false;
            ca_start_requested_ = true;
            state_ = request_write_ ? State::WaitWrite : State::WaitRead;
            break;
        }
        response_valid_ = true;
        state_ = State::Respond;
        break;
      case State::WaitRead:
        if (read_valid_ && read_ready) {
            read_valid_ = false;
            read_last_ = false;
            --words_remaining_;
            if (words_remaining_ == 0) {
                read_end_requested_ = true;
                state_ = State::WaitReadPinEnd;
            } else {
                read_resume_requested_ = true;
            }
        }
        break;
      case State::WaitReadPinEnd:
        if (read_pin_end_complete_) {
            response_code_ = read_completion_code_;
            response_valid_ = true;
            state_ = State::Respond;
        }
        break;
      case State::WaitWrite:
        if (write_valid && write_ready()) {
            write_data_ = write_data;
            write_mask_ = write_mask & 0x3U;
            const unsigned word_index = request_words_ - words_remaining_;
            write_updates_configuration_register0_ = request_register_space_ &&
                ((request_address_ >> 1) + word_index == 0x800U);
            write_data_available_ = true;
            if (words_remaining_ == 1)
                state_ = State::WaitWritePinEnd;
        }
        break;
      case State::WaitWritePinEnd:
        if (write_pin_end_complete_) {
            response_code_ = ResponseCode::Ok;
            response_valid_ = true;
            state_ = State::Respond;
        }
        break;
      case State::Respond:
        if (response_ready) {
            response_valid_ = false;
            response_code_ = ResponseCode::Ok;
            state_ = State::Idle;
        }
        break;
    }
}

void HyperbusControllerModel::tick_4x(bool reset_n, std::uint8_t dq, bool rwds)
{
    if (!reset_n) {
        reset();
        return;
    }

    ++cycles_4x_;

    if (ca_start_requested_ && pin_state_ == PinState::Idle) {
        ca_start_requested_ = false;
        cs_n_ = false;
        ck_ = false;
        dq_oe_ = true;
        ca_byte_index_ = 0;
        dq_o_ = static_cast<std::uint8_t>(command_address_ >> 40);
        // CS# assertion and the first CA byte must both precede the first
        // CK edge by their profile-configured setup intervals.
        const unsigned first_edge_setup = t_css_4x_ticks_ > ca_setup_delay()
                                          ? t_css_4x_ticks_ : ca_setup_delay();
        pin_delay_4x_ticks_ = first_edge_setup > 2 ? first_edge_setup : 2;
        pin_state_ = PinState::CsSetup;
        return;
    }

    if (pin_state_ == PinState::ReadClock) {
        if (rwds != previous_rwds_ && unexpected_rwds_fatal_ &&
            rwds != !read_byte_a_seen_) {
            abort_read(ResponseCode::ReadProtocolError);
        }
        if (pin_state_ == PinState::ReadClock) {
        // The default ideal-pin profile retains the original immediate
        // RWDS-edge sampling behavior exactly.
        if (rwds_qualify_4x_ticks_ == 0 && dq_sample_delay_4x_ticks_ == 0) {
            if (rwds != previous_rwds_) {
                if (rwds) {
                    read_byte_a_ = dq;
                    read_byte_a_seen_ = true;
                    read_strobe_wait_ticks_ = 0;
                } else if (read_byte_a_seen_) {
                    read_data_ = static_cast<std::uint16_t>(
                        (static_cast<std::uint16_t>(read_byte_a_) << 8) | dq);
                    read_last_ = words_remaining_ == 1;
                    read_valid_ = true;
                    read_strobe_wait_ticks_ = 0;
                    pin_state_ = PinState::ReadHold;
                }
            }
        } else {
        if (rwds != previous_rwds_) {
            const bool byte_a_transition = rwds && !read_byte_a_seen_;
            const bool byte_b_transition = !rwds && read_byte_a_seen_;
            if (byte_a_transition || byte_b_transition) {
                read_strobe_candidate_ = true;
                read_strobe_candidate_level_ = rwds;
                read_strobe_stable_ticks_ = 0;
            }
        }

        if (read_strobe_candidate_) {
            if (rwds != read_strobe_candidate_level_) {
                read_strobe_candidate_ = false;
            } else if (++read_strobe_stable_ticks_ >= rwds_qualify_4x_ticks_) {
                read_strobe_candidate_ = false;
                read_sample_pending_ = true;
                read_sample_byte_a_ = read_strobe_candidate_level_;
                read_sample_delay_ticks_ = dq_sample_delay_4x_ticks_;
                read_sample_elapsed_ticks_ = 0;
            }
        }

        if (read_sample_pending_) {
            if (read_sample_delay_ticks_ != 0) {
                --read_sample_delay_ticks_;
                ++read_sample_elapsed_ticks_;
            } else {
                read_sample_pending_ = false;
                    if (read_sample_byte_a_) {
                        read_byte_a_ = dq;
                        read_byte_a_seen_ = true;
                        read_strobe_wait_ticks_ = 0;
                    } else {
                    read_data_ = static_cast<std::uint16_t>(
                        (static_cast<std::uint16_t>(read_byte_a_) << 8) | dq);
                        read_last_ = words_remaining_ == 1;
                        read_valid_ = true;
                        read_strobe_wait_ticks_ = 0;
                        pin_state_ = PinState::ReadHold;
                }
            }
            if (read_sample_pending_ && read_sample_timeout_4x_ticks_ != 0 &&
                read_sample_elapsed_ticks_ >= read_sample_timeout_4x_ticks_) {
                abort_read(ResponseCode::ReadSampleTimeout);
            }
        }
        }
        if (pin_state_ == PinState::ReadClock && !read_sample_pending_ &&
            !read_strobe_candidate_) {
            const unsigned timeout = read_byte_a_seen_
                ? read_byte_b_timeout_4x_ticks_
                : initial_read_strobe_timeout_4x_ticks_;
            if (timeout != 0 && ++read_strobe_wait_ticks_ >= timeout)
                abort_read(ResponseCode::ReadStrobeTimeout);
        }
    }
    }
    previous_rwds_ = rwds;

    switch (pin_state_) {
      case PinState::Idle:
        break;
      case PinState::CsSetup:
      case PinState::SendCa:
        if (--pin_delay_4x_ticks_ != 0)
            break;
        ck_ = !ck_;
        ++ca_byte_index_;
        if (ca_byte_index_ == 6) {
            // The sixth CA byte is captured on this falling CK edge. Keep it
            // valid for one final 4x tick before sampling CA RWDS.
            pin_delay_4x_ticks_ = ca_hold_delay();
            pin_state_ = PinState::LatencySample;
        } else {
            // DQ must remain stable through this CK transition. It is moved
            // to the next CA byte on the following 4x tick, leaving one full
            // 4x interval of setup before the next edge.
            pin_delay_4x_ticks_ = ca_hold_delay();
            pin_state_ = PinState::DriveCa;
        }
        break;
      case PinState::DriveCa:
        if (--pin_delay_4x_ticks_ != 0)
            break;
        dq_o_ = static_cast<std::uint8_t>(
            command_address_ >> ((5 - ca_byte_index_) * 8));
        pin_delay_4x_ticks_ = ca_setup_delay();
        pin_state_ = PinState::SendCa;
        break;
      case PinState::LatencySample: {
        if (--pin_delay_4x_ticks_ != 0)
            break;
        dq_oe_ = false;
        const bool zero_latency_write = request_write_ &&
            (request_register_space_ ? zero_latency_register_writes_
                                     : zero_latency_memory_writes_);
        if (zero_latency_write) {
            // In this mode the first data byte follows CA directly. RWDS is
            // not a byte mask and is either held Low or released by profile.
            rwds_oe_ = zero_latency_write_rwds_low_;
            rwds_o_ = false;
            write_masks_enabled_ = false;
            pin_state_ = PinState::WriteWaitData;
            break;
        }
        // A normal-latency write takes ownership of RWDS immediately after
        // CA and holds it Low as the required write-mask preamble.
        rwds_oe_ = request_write_;
        rwds_o_ = false;
        write_masks_enabled_ = true;
        // RWDS High requests one additional initial-latency count. CR0's
        // latency code is expressed in CK cycles, each containing two edges.
        const auto latency = selected_profile_
            ? selected_profile_->latency.initial_latency(configuration_register0_, rwds)
            : controller_profile::InitialLatency{7, rwds};
        latency_edges_remaining_ = latency.clock_cycles * 2U;
        pin_delay_4x_ticks_ = 2;
        pin_state_ = PinState::Latency;
        break;
      }
      case PinState::Latency:
        if (--pin_delay_4x_ticks_ != 0)
            break;
        ck_ = !ck_;
        --latency_edges_remaining_;
        pin_delay_4x_ticks_ = clock_phase_delay();
        if (latency_edges_remaining_ == 0)
            pin_state_ = request_write_ ? PinState::WriteWaitData
                                        : PinState::ReadClock;
        break;
      case PinState::ReadClock:
        if (--pin_delay_4x_ticks_ != 0)
            break;
        ck_ = !ck_;
        pin_delay_4x_ticks_ = clock_phase_delay();
        break;
      case PinState::ReadHold:
        if (read_end_requested_) {
            cs_n_ = true;
            ck_ = false;
            request_earliest_4x_tick_ = cycles_4x_ + t_rwr_4x_ticks_;
            pin_state_ = PinState::Idle;
            read_pin_end_complete_ = true;
        } else if (read_resume_requested_) {
            read_resume_requested_ = false;
            read_byte_a_seen_ = false;
            read_strobe_candidate_ = false;
            read_sample_pending_ = false;
            read_strobe_wait_ticks_ = 0;
            pin_delay_4x_ticks_ = 2;
            if (variable_latency_supported_ &&
                inter_word_variable_latency_supported_ && rwds) {
                read_stall_edges_elapsed_ = 0;
                pin_state_ = PinState::ReadStall;
            } else {
                pin_state_ = PinState::ReadClock;
            }
        }
        break;
      case PinState::ReadStall:
        if (--pin_delay_4x_ticks_ != 0)
            break;
        ck_ = !ck_;
        pin_delay_4x_ticks_ = clock_phase_delay();
        if (!rwds) {
            // The slave's Low-RWDS recovery phase precedes the next Byte-A
            // strobe. The next CK edge is therefore handled by ReadClock.
            pin_state_ = PinState::ReadClock;
        } else if (read_stall_timeout_edges_ != 0 &&
                   ++read_stall_edges_elapsed_ >= read_stall_timeout_edges_) {
            abort_read(ResponseCode::ReadStallTimeout);
        }
        break;
      case PinState::WriteWaitData:
        if (!write_data_available_)
            break;
        write_data_available_ = false;
        dq_oe_ = true;
        dq_o_ = static_cast<std::uint8_t>(write_data_ >> 8);
        rwds_o_ = write_masks_enabled_ && (write_mask_ & 0x2U) != 0;
        pin_delay_4x_ticks_ = write_setup_delay();
        pin_state_ = PinState::WriteByteA;
        break;
      case PinState::WriteByteA:
        if (--pin_delay_4x_ticks_ != 0)
            break;
        ck_ = true;
        pin_delay_4x_ticks_ = write_hold_delay();
        pin_state_ = PinState::WriteDriveByteB;
        break;
      case PinState::WriteDriveByteB:
        if (--pin_delay_4x_ticks_ != 0)
            break;
        dq_o_ = static_cast<std::uint8_t>(write_data_);
        rwds_o_ = write_masks_enabled_ && (write_mask_ & 0x1U) != 0;
        pin_delay_4x_ticks_ = write_setup_delay();
        pin_state_ = PinState::WriteByteB;
        break;
      case PinState::WriteByteB:
        if (--pin_delay_4x_ticks_ != 0)
            break;
        ck_ = false;
        pin_delay_4x_ticks_ = write_hold_delay();
        pin_state_ = PinState::WriteHold;
        break;
      case PinState::WriteHold:
        if (--pin_delay_4x_ticks_ != 0)
            break;
        if (write_updates_configuration_register0_) {
            apply_configuration_register0_write(write_data_, write_mask_);
            write_updates_configuration_register0_ = false;
        }
        --words_remaining_;
        if (words_remaining_ != 0) {
            // Keep ownership of RWDS (Low) and DQ between words. CK stays
            // stopped until the request channel supplies the next word.
            rwds_o_ = false;
            pin_state_ = PinState::WriteWaitData;
        } else {
            dq_oe_ = false;
            rwds_oe_ = false;
            cs_n_ = true;
            ck_ = false;
            request_earliest_4x_tick_ = cycles_4x_ + t_rwr_4x_ticks_;
            pin_state_ = PinState::Idle;
            write_pin_end_complete_ = true;
        }
        break;
    }
}

bool HyperbusControllerModel::request_ready() const
{ return cycles_4x_ >= reset_recovery_4x_ticks_ && initialization_complete_ && !initialization_error_ && state_ == State::Idle && !response_valid_ &&
           cycles_4x_ >= request_earliest_4x_tick_;
}
bool HyperbusControllerModel::write_ready() const
{
    return state_ == State::WaitWrite &&
           pin_state_ == PinState::WriteWaitData && !write_data_available_;
}
bool HyperbusControllerModel::read_valid() const { return initialization_complete_ && read_valid_; }
std::uint16_t HyperbusControllerModel::read_data() const { return read_data_; }
bool HyperbusControllerModel::read_last() const { return read_last_; }
bool HyperbusControllerModel::response_valid() const { return response_valid_; }
bool HyperbusControllerModel::response_error() const
{
    return response_code_ != ResponseCode::Ok;
}
unsigned HyperbusControllerModel::response_code() const
{
    return static_cast<unsigned>(response_code_);
}
bool HyperbusControllerModel::init_valid() const { return initialization_complete_ && !initialization_error_; }
bool HyperbusControllerModel::init_error() const { return initialization_error_; }
unsigned HyperbusControllerModel::init_code() const { return initialization_error_ ? static_cast<unsigned>(ResponseCode::ProfileMismatch) : 0; }

// Until a transaction is implemented, the controller must be electrically
// inert: no CS#, clock, DQ, or RWDS drive is asserted.
bool HyperbusControllerModel::cs_n() const { return cs_n_; }
bool HyperbusControllerModel::ck() const { return ck_; }
bool HyperbusControllerModel::ck_n() const { return !ck_; }
bool HyperbusControllerModel::dq_oe() const { return dq_oe_; }
std::uint8_t HyperbusControllerModel::dq_o() const { return dq_o_; }
bool HyperbusControllerModel::rwds_oe() const { return rwds_oe_; }
bool HyperbusControllerModel::rwds_o() const { return rwds_o_; }

static HyperbusControllerModel model;

extern "C" {

unsigned char hyperbus_controller_model_select_profile(const char* name)
{
    return model.select_profile(name) ? 1 : 0;
}

void hyperbus_controller_model_reset() { model.reset(); }
void hyperbus_controller_model_tick_system(unsigned char reset_n,
                                            unsigned char request_valid,
                                            unsigned char request_write,
                                            unsigned char request_register_space,
                                            unsigned char request_linear_burst,
                                            unsigned int request_address,
                                            unsigned int request_words,
                                            unsigned char write_valid,
                                            unsigned int write_data,
                                            unsigned int write_mask,
                                            unsigned char read_ready,
                                            unsigned char response_ready)
{
    model.tick_system(reset_n != 0, request_valid != 0, request_write != 0,
                      request_register_space != 0, request_linear_burst != 0,
                      request_address, request_words, write_valid != 0,
                      static_cast<std::uint16_t>(write_data),
                      static_cast<std::uint8_t>(write_mask),
                      read_ready != 0, response_ready != 0);
}
void hyperbus_controller_model_tick_4x(unsigned char reset_n, unsigned char dq,
                                       unsigned char rwds)
{
    model.tick_4x(reset_n != 0, dq, rwds != 0);
}
unsigned char hyperbus_controller_model_request_ready()
{
    return model.request_ready() ? 1 : 0;
}
unsigned char hyperbus_controller_model_write_ready()
{
    return model.write_ready() ? 1 : 0;
}
unsigned char hyperbus_controller_model_read_valid()
{
    return model.read_valid() ? 1 : 0;
}
unsigned int hyperbus_controller_model_read_data()
{
    return model.read_data();
}
unsigned char hyperbus_controller_model_read_last()
{
    return model.read_last() ? 1 : 0;
}
unsigned char hyperbus_controller_model_response_valid()
{
    return model.response_valid() ? 1 : 0;
}
unsigned char hyperbus_controller_model_response_error()
{
    return model.response_error() ? 1 : 0;
}
unsigned int hyperbus_controller_model_response_code()
{
    return model.response_code();
}
unsigned char hyperbus_controller_model_init_valid() { return model.init_valid() ? 1 : 0; }
unsigned char hyperbus_controller_model_init_error() { return model.init_error() ? 1 : 0; }
unsigned int hyperbus_controller_model_init_code() { return model.init_code(); }
unsigned char hyperbus_controller_model_cs_n() { return model.cs_n() ? 1 : 0; }
unsigned char hyperbus_controller_model_ck() { return model.ck() ? 1 : 0; }
unsigned char hyperbus_controller_model_ck_n() { return model.ck_n() ? 1 : 0; }
unsigned char hyperbus_controller_model_dq_oe() { return model.dq_oe() ? 1 : 0; }
unsigned char hyperbus_controller_model_dq_o() { return model.dq_o(); }
unsigned char hyperbus_controller_model_rwds_oe()
{
    return model.rwds_oe() ? 1 : 0;
}
unsigned char hyperbus_controller_model_rwds_o()
{
    return model.rwds_o() ? 1 : 0;
}

}
