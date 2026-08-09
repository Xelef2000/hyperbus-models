#include <cstdint>
#include <unordered_map>

// Minimal cycle-accurate HyperRAM behavioural core.  It supports the memory
// address space, fixed initial latency, and linear read/write bursts.
class HyperramModel {
  public:
    void reset();
    void tick();
    void tick_4x(bool clk, bool cs_n, bool ck, bool ck_n, std::uint8_t dq,
                 bool rwds);
    void set_device_profile(std::uint16_t id0, std::uint16_t id1,
                            std::uint16_t config0, std::uint16_t config1,
                            bool fixed_latency_rwds_high,
                            bool variable_latency_supported,
                            unsigned refresh_interval_4x_ticks,
                            unsigned refresh_busy_4x_ticks);

    bool dq_oe() const;
    std::uint8_t dq_o() const;
    bool rwds_oe() const;
    bool rwds_o() const;
    std::uint8_t debug_read_byte(std::uint32_t address) const;
    std::uint16_t debug_configuration_register0() const;
    bool debug_refresh_active() const;

  private:
    enum class MainClockEdge { None, Rising, Falling };
    enum class BusState { Idle, CommandAddress, Latency, Read, Write };

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
    };

    void reset_transaction();
    void update_refresh_state();
    void process_bus_edge(std::uint8_t dq, bool rwds);
    void begin_transfer();
    unsigned latency_cycles_from_cr0() const;
    std::uint8_t read_data_byte() const;
    std::uint8_t read_register_byte(std::uint32_t word_address,
                                    bool byte_b) const;
    void write_data_byte(std::uint8_t dq, bool rwds);
    void write_register_byte(std::uint32_t word_address, bool byte_b,
                             std::uint8_t value);
    void advance_data_byte();
    std::uint8_t read_byte(std::uint32_t address) const;

    std::uint64_t cycles_ = 0;
    std::uint64_t cycles_4x_ = 0;
    std::uint64_t main_clk_rising_edges_ = 0;
    std::uint64_t main_clk_falling_edges_ = 0;
    bool previous_main_clk_ = false;
    MainClockEdge main_clk_edge_ = MainClockEdge::None;

    BusState bus_state_ = BusState::Idle;
    bool previous_ck_ = false;
    bool previous_cs_n_ = true;
    unsigned ca_bytes_received_ = 0;
    unsigned latency_edges_remaining_ = 0;
    std::uint64_t command_address_ = 0;
    std::uint32_t word_address_ = 0;
    bool byte_b_ = false;
    bool read_transfer_ = false;
    bool register_space_ = false;
    bool additional_latency_ = false;
    bool refresh_active_ = false;
    std::uint64_t next_refresh_start_4x_tick_ = 0;
    std::uint64_t refresh_busy_until_4x_tick_ = 0;
    // Reset values for the device-specific register-space profile.  The
    // registers are stored now so future register transactions can use them.
    DeviceProfile device_profile_;
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

void HyperramModel::reset()
{
    cycles_ = 0;
    cycles_4x_ = 0;
    main_clk_rising_edges_ = 0;
    main_clk_falling_edges_ = 0;
    previous_main_clk_ = false;
    main_clk_edge_ = MainClockEdge::None;
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
                                       unsigned refresh_busy_4x_ticks)
{
    device_profile_.identification_register0 = id0;
    device_profile_.identification_register1 = id1;
    device_profile_.configuration_register0 = config0;
    device_profile_.configuration_register1 = config1;
    device_profile_.fixed_latency_rwds_high = fixed_latency_rwds_high;
    device_profile_.variable_latency_supported = variable_latency_supported;
    device_profile_.refresh_interval_4x_ticks = refresh_interval_4x_ticks;
    device_profile_.refresh_busy_4x_ticks = refresh_busy_4x_ticks;
}

void HyperramModel::reset_transaction()
{
    bus_state_ = BusState::Idle;
    ca_bytes_received_ = 0;
    latency_edges_remaining_ = 0;
    command_address_ = 0;
    word_address_ = 0;
    byte_b_ = false;
    read_transfer_ = false;
    register_space_ = false;
    additional_latency_ = false;
    dq_oe_ = false;
    dq_o_ = 0;
    rwds_oe_ = false;
    rwds_o_ = false;
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

void HyperramModel::tick()
{
    ++cycles_;
}

void HyperramModel::tick_4x(bool clk, bool cs_n, bool ck, bool ck_n,
                            std::uint8_t dq, bool rwds)
{
    ++cycles_4x_;
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

    // CS# terminates the active transaction and releases the bidirectional IO.
    if (cs_n) {
        reset_transaction();
        previous_cs_n_ = true;
        previous_ck_ = ck;
        return;
    }

    if (previous_cs_n_) {
        bus_state_ = BusState::CommandAddress;
        ca_bytes_received_ = 0;
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

    // HyperBus is DDR: one byte transfers on each CK transition.
    if (ck != previous_ck_)
        process_bus_edge(dq, rwds);
    previous_ck_ = ck;

    // CK# is retained in the DPI interface for future differential-clock
    // validation.  This basic model uses CK as the edge reference.
    (void)ck_n;
}

void HyperramModel::process_bus_edge(std::uint8_t dq, bool rwds)
{
    switch (bus_state_) {
      case BusState::CommandAddress:
        command_address_ = (command_address_ << 8) | dq;
        ++ca_bytes_received_;
        if (ca_bytes_received_ == CommandAddressBytes) {
            // CA[47] is 1 for read and 0 for write.  The HyperBus address is
            // split around the reserved CA bits [15:3].
            read_transfer_ = ((command_address_ >> 47) & 1U) != 0;
            register_space_ = ((command_address_ >> 46) & 1U) != 0;
            word_address_ = static_cast<std::uint32_t>(
                (((command_address_ >> 16) & 0x1fff'ffffULL) << 3) |
                (command_address_ & 0x7ULL));
            byte_b_ = false;
            latency_edges_remaining_ = latency_cycles_from_cr0() *
                                       (additional_latency_ ? 4 : 2);
            bus_state_ = BusState::Latency;

            // For writes with initial latency, hand RWDS ownership to the
            // master after CA so it can provide its mask preamble and masks.
            if (!read_transfer_)
                rwds_oe_ = false;
        }
        break;

      case BusState::Latency:
        if (--latency_edges_remaining_ == 0)
            begin_transfer();
        break;

      case BusState::Write:
        write_data_byte(dq, rwds);
        break;

      case BusState::Read:
        // Present the next byte after each transfer edge.  RWDS is the source
        // synchronous strobe used by the controller to capture DQ.
        dq_o_ = read_data_byte();
        rwds_o_ = !rwds_o_;
        advance_data_byte();
        break;

      case BusState::Idle:
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
    } else {
        bus_state_ = BusState::Write;
    }
}

unsigned HyperramModel::latency_cycles_from_cr0() const
{
    switch ((configuration_register0_ >> 4) & 0xfU) {
      case 0x0: return 5;
      case 0x1: return 6;
      case 0x2: return 7;
      case 0x3: return 8;
      case 0x4: return 9;
      case 0x5: return 10;
      case 0x6: return 11;
      case 0x7: return 12;
      case 0x8: return 13;
      case 0x9: return 14;
      case 0xa: return 15;
      case 0xb: return 16;
      case 0xe: return 3;
      case 0xf: return 4;
      default: return 7; // Reserved encodings use the profile-safe value.
    }
}

std::uint8_t HyperramModel::read_data_byte() const
{
    if (register_space_)
        return read_register_byte(word_address_, byte_b_);
    return read_byte((word_address_ << 1) | static_cast<unsigned>(byte_b_));
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

void HyperramModel::write_data_byte(std::uint8_t dq, bool rwds)
{
    // RWDS high masks the corresponding write byte.
    if (!rwds) {
        if (register_space_)
            write_register_byte(word_address_, byte_b_, dq);
        else
            memory_[(word_address_ << 1) | static_cast<unsigned>(byte_b_)] = dq;
    }
    advance_data_byte();
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
    if (word_address == 0x800)
        write_byte(configuration_register0_);
    else if (word_address == 0x801)
        write_byte(configuration_register1_);
}

void HyperramModel::advance_data_byte()
{
    byte_b_ = !byte_b_;
    if (!byte_b_)
        ++word_address_;
}

std::uint8_t HyperramModel::read_byte(std::uint32_t address) const
{
    const auto it = memory_.find(address);
    return it == memory_.end() ? 0xff : it->second;
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
bool HyperramModel::debug_refresh_active() const { return refresh_active_; }

static HyperramModel model;

extern "C" {

void hyperram_model_reset() { model.reset(); }
void hyperram_model_tick() { model.tick(); }

void hyperram_model_tick_4x(unsigned char clk, unsigned char cs_n,
                            unsigned char ck, unsigned char ck_n,
                            unsigned char dq, unsigned char rwds)
{
    model.tick_4x(clk != 0, cs_n != 0, ck != 0, ck_n != 0, dq, rwds != 0);
}

void hyperram_model_set_device_profile(unsigned int id0, unsigned int id1,
                                       unsigned int config0,
                                       unsigned int config1,
                                       unsigned char fixed_latency_rwds_high,
                                       unsigned char variable_latency_supported,
                                       unsigned int refresh_interval_4x_ticks,
                                       unsigned int refresh_busy_4x_ticks)
{
    model.set_device_profile(static_cast<std::uint16_t>(id0),
                             static_cast<std::uint16_t>(id1),
                             static_cast<std::uint16_t>(config0),
                             static_cast<std::uint16_t>(config1),
                             fixed_latency_rwds_high != 0,
                             variable_latency_supported != 0,
                             refresh_interval_4x_ticks,
                             refresh_busy_4x_ticks);
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
unsigned char hyperram_model_refresh_active()
{
    return model.debug_refresh_active() ? 1 : 0;
}

}
