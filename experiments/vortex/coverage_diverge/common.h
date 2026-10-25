#ifndef _COMMON_H_
#define _COMMON_H_

#include <stdint.h>

typedef struct {
  uint32_t num_points;
  uint64_t src_addr;
  uint64_t dst_addr;
  uint32_t branch_depth;
  uint32_t branch_pattern;
  uint32_t branch_mask_start;
  uint32_t branch_mask_count;
} kernel_arg_t;

static inline uint32_t coverage_predicate(
    uint32_t predicate, uint32_t pattern, uint32_t id) {
  if (pattern == 2u) {
    // Sweep all 14 nonuniform four-lane masks in groups of four IDs.
    uint32_t then_mask = ((id / 4u) % 14u) + 1u;
    return (then_mask >> (id & 3u)) & 1u;
  }
  return (predicate != 0) ^ ((pattern & 1u) != 0);
}

static inline uint32_t coverage_predicate8(uint32_t id) {
  // Sweep all 254 nonuniform eight-lane masks in groups of eight IDs.
  uint32_t then_mask = ((id / 8u) % 254u) + 1u;
  return (then_mask >> (id & 7u)) & 1u;
}

static inline uint32_t coverage_predicate16(
    uint32_t id, uint32_t mask_start, uint32_t mask_count) {
  // Sweep a contiguous shard of nonuniform sixteen-lane masks.
  uint32_t then_mask = mask_start + ((id / 16u) % mask_count);
  return (then_mask >> (id & 15u)) & 1u;
}
#endif
