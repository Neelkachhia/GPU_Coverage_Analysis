#include <iostream>
#include <unistd.h>
#include <string.h>
#include <vortex2.h>
#include <vector>
#include <assert.h>
#include "common.h"

#define RT_CHECK(_expr)                                         \
  do {                                                          \
    int _ret = _expr;                                           \
    if (0 == _ret)                                              \
      break;                                                    \
    printf("Error: '%s' returned %d!\n", #_expr, (int)_ret);    \
    cleanup();                                                  \
    exit(-1);                                                   \
  } while (false)

///////////////////////////////////////////////////////////////////////////////

const char* kernel_file = "kernel.vxbin";
uint32_t count = 0;
uint32_t branch_pattern = 0;
uint32_t branch_depth = 8; // NEW: default nested depth

vx_device_h device = nullptr;
vx_buffer_h src_buffer = nullptr;
vx_buffer_h dst_buffer = nullptr;
vx_queue_h  queue   = nullptr;
vx_module_h module_ = nullptr;
vx_kernel_h kernel  = nullptr;
kernel_arg_t kernel_arg = {};

static void show_usage() {
  std::cout << "Vortex Test.\n";
  std::cout << "Usage: [-k kernel] [-n words] [-d depth(1..8)] [-p pattern(0..2)] [-h]\n";
}

static void parse_args(int argc, char **argv) {
  int c;
  while ((c = getopt(argc, argv, "n:k:d:p:h")) != -1) {
    switch (c) {
      case 'n':
        count = atoi(optarg);
        break;
      case 'k':
        kernel_file = optarg;
        break;
      case 'd':
        branch_depth = std::max(1, std::min(8, atoi(optarg)));
        break;
      case 'p':
	branch_pattern = std::min(2, std::max(0, atoi(optarg)));
	break;
      case 'h':
        show_usage();
        exit(0);
      default:
        show_usage();
        exit(-1);
    }
  }
}

void cleanup() {
  if (device) {
    if (src_buffer) vx_buffer_release(src_buffer);
    if (dst_buffer) vx_buffer_release(dst_buffer);
    if (kernel)  vx_kernel_release(kernel);
    if (module_) vx_module_release(module_);
    if (queue)   vx_queue_release(queue);
    vx_device_dump_perf(device, stdout);
    vx_device_release(device);
  }
}

void gen_src_data(std::vector<int>& src_data, uint32_t size) {
  src_data.resize(size);
  for (uint32_t i = 0; i < size; ++i) {
    int value = std::rand();
    src_data[i] = value;
  }
}

// Host mirror of kernel's nested chain (must be identical to device logic)
static inline int nested_chain_1to8_host(int v, uint32_t id, uint32_t depth) {
  if (depth == 0) return v;

  if ((id >> 0) & 1) v += 1; else v -= 1;
  if (depth <= 1) return v;

  if ((id >> 1) & 1) v += 2; else v -= 2;
  if (depth <= 2) return v;

  if ((id >> 2) & 1) v += 3; else v -= 3;
  if (depth <= 3) return v;

  if ((id >> 3) & 1) v += 4; else v -= 4;
  if (depth <= 4) return v;

  if ((id >> 4) & 1) v += 5; else v -= 5;
  if (depth <= 5) return v;

  if ((id >> 5) & 1) v += 6; else v -= 6;
  if (depth <= 6) return v;

  if ((id >> 6) & 1) v += 7; else v -= 7;
  if (depth <= 7) return v;

  if ((id >> 7) & 1) v += 8; else v -= 8;
  return v;
}

void gen_ref_data(std::vector<int>& ref_data,
                  const std::vector<int>& src_data,
                  uint32_t size,
                  uint32_t depth,
		  uint32_t pattern) {
  (void)src_data;
  if (depth > 8)
    depth = 8;

  ref_data.resize(size);
  for (uint32_t id = 0; id < size; ++id) {
    int value = 0;

 if (depth >= 1) { if (coverage_predicate((id & 3) == 0, pattern, id))
	 value += 1; else value -= 1; }
 if (depth >= 2) { if (coverage_predicate((id & 2) != 0, pattern, id)) value += 2; else value -= 2; }
 if (depth >= 3) { if (coverage_predicate((id & 3) == 0, pattern, id)) value += 3; else value -= 3; }
 if (depth >= 4) { if (coverage_predicate((id & 3) == 1, pattern, id)) value += 4; else value -= 4; }
 if (depth >= 5) { if (coverage_predicate((id & 3) == 2, pattern, id)) value += 5; else value -= 5; }
 if (depth >= 6) { if (coverage_predicate((id & 3) == 3, pattern, id)) value += 6; else value -= 6; }
 if (depth >= 7) { if (coverage_predicate((id & 3) != 1, pattern, id)) value += 7; else value -= 7; }
 if (depth >= 8) { if (coverage_predicate((id & 3) != 2, pattern, id)) value += 8; else value -= 8; }

    ref_data[id] = value;
  }
}

int main(int argc, char *argv[]) {
  parse_args(argc, argv);

  if (count == 0) count = 1;

  std::srand(50);

  std::cout << "open device connection\n";
  RT_CHECK(vx_device_open(0, &device));

  vx_queue_info_t qi = { sizeof(qi), nullptr, VX_QUEUE_PRIORITY_NORMAL, 0 };
  RT_CHECK(vx_queue_create(device, &qi, &queue));

  uint64_t num_cores, num_warps, num_threads;
  RT_CHECK(vx_device_query(device, VX_CAPS_NUM_CORES, &num_cores));
  RT_CHECK(vx_device_query(device, VX_CAPS_NUM_WARPS, &num_warps));
  RT_CHECK(vx_device_query(device, VX_CAPS_NUM_THREADS, &num_threads));

  uint32_t total_threads = num_cores * num_warps * num_threads;
  uint32_t num_points = count * total_threads;
  uint32_t buf_size = num_points * sizeof(int32_t);

  std::cout << "number of points: " << num_points << "\n";
  std::cout << "buffer size: " << buf_size << " bytes\n";
  std::cout << "nested branch depth: " << branch_depth << "\n";
  std::cout << "branch pattern: " << branch_pattern << "\n";

  kernel_arg.num_points   = num_points;
  kernel_arg.branch_depth = branch_depth; // NEW
  kernel_arg.branch_pattern = branch_pattern;

  std::cout << "allocate device memory\n";
  RT_CHECK(vx_buffer_create(device, buf_size, VX_MEM_READ, &src_buffer));
  RT_CHECK(vx_buffer_address(src_buffer, &kernel_arg.src_addr));
  RT_CHECK(vx_buffer_create(device, buf_size, VX_MEM_WRITE, &dst_buffer));
  RT_CHECK(vx_buffer_address(dst_buffer, &kernel_arg.dst_addr));

  std::cout << "dev_src=0x" << std::hex << kernel_arg.src_addr << "\n";
  std::cout << "dev_dst=0x" << std::hex << kernel_arg.dst_addr << "\n";

  std::cout << "allocate host buffers\n";
  std::vector<int32_t> h_src;
  std::vector<int32_t> h_dst(num_points);
  gen_src_data(h_src, num_points);

  std::cout << "upload source buffer\n";
  RT_CHECK(vx_enqueue_write(queue, src_buffer, 0, h_src.data(), buf_size, 0, nullptr, nullptr));

  std::cout << "load kernel module\n";
  RT_CHECK(vx_module_load_file(device, kernel_file, &module_));
  RT_CHECK(vx_module_get_kernel(module_, "main", &kernel));

  std::cout << "start device\n";
  vx_event_h launch_ev = nullptr, read_ev = nullptr;
  {
    uint32_t grid_dim[1], block_dim[1];
    RT_CHECK(vx_device_max_occupancy_grid(device, 1, &num_points, grid_dim, block_dim));
    vx_launch_info_t li = {};
    li.struct_size  = sizeof(li);
    li.kernel       = kernel;
    li.args_host    = &kernel_arg;
    li.args_size    = sizeof(kernel_arg);
    li.ndim         = 1;
    li.grid_dim[0]  = grid_dim[0];
    li.block_dim[0] = block_dim[0];
    RT_CHECK(vx_enqueue_launch(queue, &li, 0, nullptr, &launch_ev));
  }

  std::cout << "download destination buffer\n";
  RT_CHECK(vx_enqueue_read(queue, h_dst.data(), dst_buffer, 0, buf_size, 1, &launch_ev, &read_ev));

  std::cout << "wait for completion\n";
  RT_CHECK(vx_event_wait_value(read_ev, 1, VX_TIMEOUT_INFINITE));
  vx_event_release(read_ev);
  vx_event_release(launch_ev);

  std::cout << "verify result\n";
  int errors = 0;
  {
    std::vector<int32_t> h_ref;
    gen_ref_data(h_ref, h_src, num_points, branch_depth, branch_pattern);

    for (uint32_t i = 0; i < num_points; ++i) {
      int ref = h_ref[i];
      int cur = h_dst[i];
      if (cur != ref) {
        std::cout << "error at result #" << std::dec << i
                  << std::hex << ": actual 0x" << cur << ", expected 0x" << ref << "\n";
        ++errors;
      }
    }
  }

  std::cout << "cleanup\n";
  cleanup();

  if (errors != 0) {
    std::cout << "Found " << std::dec << errors << " errors!\nFAILED!\n";
    return errors;
  }

  std::cout << "PASSED!\n";
  return 0;
}
