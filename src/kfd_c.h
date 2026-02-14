// kfd_c.h - 纯 C 接口，便于在 .m 中直接调用（避免 C++ 头）
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <mach/mach.h>

#ifdef __cplusplus
extern "C" {
#endif

bool     kfd_init_by_name(const char *process_name);
bool     kfd_init_by_pid(pid_t pid);
uint64_t kfd_image_base(void);
uint64_t kfd_vm_map_pmap(void);
bool     kfd_read_mem(uint64_t vmAddr, void *out, size_t len);
int      kfd_entry_run(int argc, char *argv[]);

#ifdef __cplusplus
}
#endif
