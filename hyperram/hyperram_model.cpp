#include <cstdint>

// Cycle-accurate HyperRAM behavioural core.  Protocol decoding and memory
// storage will be added here; the wrapper drives this core through DPI-C.
class HyperramModel {
  public:
    void reset();
    void tick();
    void tick_4x(bool cs_n, bool ck, bool ck_n);

  private:
    std::uint64_t cycles_ = 0;
    std::uint64_t cycles_4x_ = 0;
};

void HyperramModel::reset()
{
    cycles_ = 0;
    cycles_4x_ = 0;
}

void HyperramModel::tick()
{
    ++cycles_;
}

void HyperramModel::tick_4x(bool cs_n, bool ck, bool ck_n)
{
    ++cycles_4x_;

    (void)cs_n;
    (void)ck;
    (void)ck_n;
}

static HyperramModel model;

extern "C" {

void hyperram_model_reset()
{
    model.reset();
}

void hyperram_model_tick()
{
    model.tick();
}

void hyperram_model_tick_4x(unsigned char cs_n, unsigned char ck,
                            unsigned char ck_n)
{
    model.tick_4x(cs_n != 0, ck != 0, ck_n != 0);
}

}
