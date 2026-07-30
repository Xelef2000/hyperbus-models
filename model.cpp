#include <cstdint>
#include <optional>

#include <cstdint>
class AdderModel {
  public:
    static constexpr unsigned LATENCY = 3;

    void reset();

    bool request(std::int32_t a, std::int32_t b);

    void tick();

    bool result_valid() const;

    std::int32_t result() const;    
    
    private:
      unsigned cycles_remaining_ = 0;
      std::int32_t pending_result_ =0;
      bool busy_ = false;
      bool result_valid_ = false;
};

void AdderModel::reset()
{
  cycles_remaining_ = 0;
  pending_result_ = 0;
  busy_ = false;
  result_valid_ = false;
}

bool AdderModel::request(std::int32_t a, std::int32_t b)
{
  if(busy_){
    return false;
  }

  pending_result_ = a+b;
  cycles_remaining_ = LATENCY;
  busy_ = true;
  result_valid_ = false;
  return true;
}

void AdderModel::tick()
{
  if(!busy_){
    return;
  }

  if(cycles_remaining_ > 0) {
    --cycles_remaining_;
  }

  if(cycles_remaining_ == 0){
    busy_ = false;
    result_valid_ = true;
  }
}

bool AdderModel::result_valid() const
{
  return result_valid_;
}

std::int32_t AdderModel::result() const
{
  return pending_result_;
}

static AdderModel model;

extern "C" {

void model_reset()
{
    model.reset();
}

unsigned char model_request(int a, int b)
{
    return model.request(a, b) ? 1 : 0;
}

void model_tick()
{
    model.tick();
}

unsigned char model_result_valid()
{
    return model.result_valid() ? 1 : 0;
}

int model_result()
{
    return model.result();
}

}
