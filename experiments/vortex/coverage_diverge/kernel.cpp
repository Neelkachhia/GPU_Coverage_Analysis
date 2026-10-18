#include <vx_spawn2.h>
#include "common.h"

static __attribute__((noinline)) int level1_true(int value)
{
	return value + 1;
}

static __attribute__((noinline)) int level1_false(int value)
{
	return value - 1;
}

static __attribute__((noinline))                                            int nested_divergence(uint32_t id, uint32_t depth) {
  int value = 0;

  if (depth >= 1) {
    if ((id & 3) == 0) value = level1_true(value);
    else               value = level1_false(value);
  }
  if (depth >= 2) {
    if ((id & 2) != 0) value += 2;
    else               value -= 2;
  }
  if (depth >= 3) {
    if ((id & 3) == 0) value += 3;
    else               value -= 3;
  }
  if (depth >= 4) {
    if ((id & 3) == 1) value += 4;
    else               value -= 4;
  }
  if (depth >= 5) {
    if ((id & 3) == 2) value += 5;
    else                value -= 5;
  }
  if (depth >= 6) {
    if ((id & 3) == 3) value += 6;
    else                value -= 6;
  }
  if (depth >= 7) {
    if ((id & 3) != 1) value += 7;
    else                value -= 7;
  }
  if (depth >= 8) {
    if ((id & 3) != 2) value += 8;
    else                 value -= 8;
  }

  return value;
}

__kernel void kernel_main(kernel_arg_t* __UNIFORM__ arg) {
  uint32_t id = blockIdx.x * blockDim.x + threadIdx.x;
  if (id >= arg->num_points)
    return;

  uint32_t depth = arg->branch_depth;
  if (depth > 8)
    depth = 8;

  int32_t* dst_ptr = (int32_t*)arg->dst_addr;
  dst_ptr[id] = nested_divergence(id, depth);
}
