#ifndef _COMMON_H_
#define _COMMON_H_

#include <stdint.h>

typedef struct {
  uint32_t num_points;
  uint64_t src_addr;
  uint64_t dst_addr;
  uint32_t branch_depth;
  uint32_t branch_pattern;
} kernel_arg_t;

static inline uint32_t coverage_predicate(
    uint32_t predicate, uint32_t pattern, uint32_t id) {
  if (pattern == 2u) {
    // Four consecutive IDs form one four-lane group. Sweep divergent masks 1..14.
    uint32_t then_mask = ((id / 4u) % 14u) + 1u;
    return (then_mask >> (id & 3u)) & 1u;
  }
  return (predicate != 0) ^ ((pattern & 1u) != 0);
}
#endif
