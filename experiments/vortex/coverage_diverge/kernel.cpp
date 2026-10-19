#include <vx_spawn2.h>
#include "common.h"

static __attribute__((noinline)) int nested_divergence(
    uint32_t id, uint32_t depth, uint32_t pattern) {
  int value = 0;

  if (depth >= 1) {
    if (coverage_predicate((id & 3) == 0, pattern, id)) value += 1;
    else                                             value -= 1;
  }
  if (depth >= 2) {
    if (coverage_predicate((id & 2) != 0, pattern, id)) value += 2;
    else                                             value -= 2;
  }
  if (depth >= 3) {
    if (coverage_predicate((id & 3) == 0, pattern, id)) value += 3;
    else                                             value -= 3;
  }
  if (depth >= 4) {
    if (coverage_predicate((id & 3) == 1, pattern, id)) value += 4;
    else                                             value -= 4;
  }
  if (depth >= 5) {
    if (coverage_predicate((id & 3) == 2, pattern, id)) value += 5;
    else                                             value -= 5;
  }
  if (depth >= 6) {
    if (coverage_predicate((id & 3) == 3, pattern, id)) value += 6;
    else                                             value -= 6;
  }
  if (depth >= 7) {
    if (coverage_predicate((id & 3) != 1, pattern, id)) value += 7;
    else                                             value -= 7;
  }
  if (depth >= 8) {
    if (coverage_predicate((id & 3) != 2, pattern, id)) value += 8;
    else                                             value -= 8;
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

  uint32_t pattern = arg->branch_pattern; if (pattern > 2) pattern = 2;
  int32_t* dst_ptr = (int32_t*)arg->dst_addr;
  dst_ptr[id] = nested_divergence(id, depth, pattern);
}
