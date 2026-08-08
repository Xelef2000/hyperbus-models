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
    void set_initial_latency_cycles(unsigned cycles);
    void set_device_profile(std::uint16_t id0, std::uint16_t id1,
                            std::uint16_t config0, std::uint16_t config1);

    bool dq_oe() const;
    std::uint8_t dq_o() const;
    bool rwds_oe() const;
    bool rwds_o() const;
    std::uint8_t debug_read_byte(std::uint32_t address) const;

  private:
    enum class MainClockEdge { None, Rising, Falling };
    enum class BusState { Idle, CommandAddress, Latency, Read, Write };

    static constexpr unsigned CommandAddressBytes = 6;
    // The Infineon reference model's reset configuration uses 13 initial
    // latency clocks, i.e. 26 DDR edges following CA.  HyperBus defines
    // latency counts from 3 through 16 clocks.
    static constexpr unsigned DefaultInitialLatencyCycles = 13;
    static constexpr unsigned MinimumInitialLatencyCycles = 3;
    static constexpr unsigned MaximumInitialLatencyCycles = 16;

    struct DeviceProfile {
        std::uint16_t identification_register0 = 0x0c81;
        std::uint16_t identification_register1 = 0x0001;
        std::uint16_t configuration_register0 = 0x8f2f;
        std::uint16_t configuration_register1 = 0xffc1;
    };

    void reset_transaction();
    void process_bus_edge(std::uint8_t dq, bool rwds);
    void begin_transfer();
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
    std::uint32_t address_ = 0;
    bool read_transfer_ = false;
    // This represents the selected initial-latency configuration.  A future
    // register-space implementation will update this from CR0.
    unsigned initial_latency_cycles_ = DefaultInitialLatencyCycles;
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
    initial_latency_cycles_ = DefaultInitialLatencyCycles;
    identification_register0_ = device_profile_.identification_register0;
    identification_register1_ = device_profile_.identification_register1;
    configuration_register0_ = device_profile_.configuration_register0;
    configuration_register1_ = device_profile_.configuration_register1;
    reset_transaction();
}

void HyperramModel::set_initial_latency_cycles(unsigned cycles)
{
    if (cycles >= MinimumInitialLatencyCycles &&
        cycles <= MaximumInitialLatencyCycles)
        initial_latency_cycles_ = cycles;
}

void HyperramModel::set_device_profile(std::uint16_t id0, std::uint16_t id1,
                                       std::uint16_t config0,
                                       std::uint16_t config1)
{
    device_profile_.identification_register0 = id0;
    device_profile_.identification_register1 = id1;
    device_profile_.configuration_register0 = config0;
    device_profile_.configuration_register1 = config1;
}

void HyperramModel::reset_transaction()
{
    bus_state_ = BusState::Idle;
    ca_bytes_received_ = 0;
    latency_edges_remaining_ = 0;
    command_address_ = 0;
    address_ = 0;
    read_transfer_ = false;
    dq_oe_ = false;
    dq_o_ = 0;
    rwds_oe_ = false;
    rwds_o_ = false;
}

void HyperramModel::tick()
{
    ++cycles_;
}

void HyperramModel::tick_4x(bool clk, bool cs_n, bool ck, bool ck_n,
                            std::uint8_t dq, bool rwds)
{
    ++cycles_4x_;

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
        // bits to know the transaction type.  The current fixed-latency
        // policy advertises one latency count by driving it low.
        rwds_oe_ = true;
        rwds_o_ = false;
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
            address_ = static_cast<std::uint32_t>(
                (((command_address_ >> 16) & 0x1fff'ffffULL) << 3) |
                (command_address_ & 0x7ULL));
            latency_edges_remaining_ = initial_latency_cycles_ * 2;
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
        // RWDS high masks the corresponding write byte.
        if (!rwds)
            memory_[address_] = dq;
        ++address_;
        break;

      case BusState::Read:
        // Present the next byte after each transfer edge.  RWDS is the source
        // synchronous strobe used by the controller to capture DQ.
        dq_o_ = read_byte(address_++);
        rwds_o_ = !rwds_o_;
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

void hyperram_model_set_initial_latency_cycles(unsigned int cycles)
{
    model.set_initial_latency_cycles(cycles);
}

void hyperram_model_set_device_profile(unsigned int id0, unsigned int id1,
                                       unsigned int config0,
                                       unsigned int config1)
{
    model.set_device_profile(static_cast<std::uint16_t>(id0),
                             static_cast<std::uint16_t>(id1),
                             static_cast<std::uint16_t>(config0),
                             static_cast<std::uint16_t>(config1));
}

unsigned char hyperram_model_dq_oe() { return model.dq_oe() ? 1 : 0; }
unsigned char hyperram_model_dq_o() { return model.dq_o(); }
unsigned char hyperram_model_rwds_oe() { return model.rwds_oe() ? 1 : 0; }
unsigned char hyperram_model_rwds_o() { return model.rwds_o() ? 1 : 0; }
unsigned char hyperram_model_read_byte(unsigned int address)
{
    return model.debug_read_byte(address);
}

}
