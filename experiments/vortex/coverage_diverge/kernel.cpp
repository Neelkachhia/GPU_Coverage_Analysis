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


static __attribute__((noinline)) int nested_divergence8(
    uint32_t id, uint32_t depth) {
  int value = 0;
  if (depth >= 1) {
    if (coverage_predicate8(id)) value += 1; else value -= 1;
  }
  if (depth >= 2) {
    if (coverage_predicate8(id)) value += 2; else value -= 2;
  }
  if (depth >= 3) {
    if (coverage_predicate8(id)) value += 3; else value -= 3;
  }
  if (depth >= 4) {
    if (coverage_predicate8(id)) value += 4; else value -= 4;
  }
  if (depth >= 5) {
    if (coverage_predicate8(id)) value += 5; else value -= 5;
  }
  if (depth >= 6) {
    if (coverage_predicate8(id)) value += 6; else value -= 6;
  }
  if (depth >= 7) {
    if (coverage_predicate8(id)) value += 7; else value -= 7;
  }
  if (depth >= 8) {
    if (coverage_predicate8(id)) value += 8; else value -= 8;
  }
  return value;
}

static __attribute__((noinline)) int nested_divergence16(
    uint32_t id, uint32_t depth, uint32_t mask_start, uint32_t mask_count) {
  int value = 0;
  if (depth >= 1) { if (coverage_predicate16(id, mask_start, mask_count)) value += 1; else value -= 1; }
  if (depth >= 2) { if (coverage_predicate16(id, mask_start, mask_count)) value += 2; else value -= 2; }
  if (depth >= 3) { if (coverage_predicate16(id, mask_start, mask_count)) value += 3; else value -= 3; }
  if (depth >= 4) { if (coverage_predicate16(id, mask_start, mask_count)) value += 4; else value -= 4; }
  if (depth >= 5) { if (coverage_predicate16(id, mask_start, mask_count)) value += 5; else value -= 5; }
  if (depth >= 6) { if (coverage_predicate16(id, mask_start, mask_count)) value += 6; else value -= 6; }
  if (depth >= 7) { if (coverage_predicate16(id, mask_start, mask_count)) value += 7; else value -= 7; }
  if (depth >= 8) { if (coverage_predicate16(id, mask_start, mask_count)) value += 8; else value -= 8; }
  return value;
}

static __attribute__((noinline)) int nested_divergence16_loop(
    uint32_t lane_id, uint32_t depth, uint32_t mask_start, uint32_t mask_count) {
  int value = 0;
  uint32_t lane = lane_id & 15u;
  for (uint32_t mask_offset = 0; mask_offset < mask_count; ++mask_offset) {
    uint32_t mask = mask_start + mask_offset;
    if (depth >= 1) { if ((mask >> ((lane + 0u) & 15u)) & 1u) value += 1; else value -= 1; }
    if (depth >= 2) { if ((mask >> ((lane + 1u) & 15u)) & 1u) value += 2; else value -= 2; }
    if (depth >= 3) { if ((mask >> ((lane + 2u) & 15u)) & 1u) value += 3; else value -= 3; }
    if (depth >= 4) { if ((mask >> ((lane + 3u) & 15u)) & 1u) value += 4; else value -= 4; }
    if (depth >= 5) { if ((mask >> ((lane + 4u) & 15u)) & 1u) value += 5; else value -= 5; }
    if (depth >= 6) { if ((mask >> ((lane + 5u) & 15u)) & 1u) value += 6; else value -= 6; }
    if (depth >= 7) { if ((mask >> ((lane + 6u) & 15u)) & 1u) value += 7; else value -= 7; }
    if (depth >= 8) { if ((mask >> ((lane + 7u) & 15u)) & 1u) value += 8; else value -= 8; }
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

  uint32_t pattern = arg->branch_pattern; if (pattern > 5) pattern = 5;
  int32_t* dst_ptr = (int32_t*)arg->dst_addr;
  if (pattern == 5u) {
    dst_ptr[id] = nested_divergence16_loop(
        id, depth, arg->branch_mask_start, arg->branch_mask_count);
  } else if (pattern == 4u) {
    dst_ptr[id] = nested_divergence16(
        id, depth, arg->branch_mask_start, arg->branch_mask_count);
  } else if (pattern == 3u) {
    dst_ptr[id] = nested_divergence8(id, depth);
  } else {
    dst_ptr[id] = nested_divergence(id, depth, pattern);
  }
}
