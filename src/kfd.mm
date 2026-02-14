// kfd.mm - 复用 YuanBao 的 KFD 初始化链路（最小可用版）

#import <Foundation/Foundation.h>
#import <mach-o/loader.h>
#import <sys/sysctl.h>
#import <unistd.h>
#include <dlfcn.h>

#include "kfd_c.h"
#include "YBKFD.hpp"

static NSString *const kKFDLogPrefix = @"[KFD][KFDRead]";
static NSString *const kKFDMachOPrefix = @"[KFD][KFDRead][MACHO]";

static NSString *ProcessNameFromPid(pid_t pid) {
    if (pid <= 0) return @"";
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    struct kinfo_proc kp{};
    size_t len = sizeof(kp);
    if (sysctl(mib, 4, &kp, &len, nullptr, 0) != 0 || len != sizeof(kp)) {
        return @"";
    }
    const char *name = (kp.kp_proc.p_comm[0] != '\0') ? kp.kp_proc.p_comm : "";
    return [NSString stringWithUTF8String:name] ?: @"";
}

static void *LoadLibjailbreakHandle(void) {
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath] ?: @"";
    NSArray<NSString *> *candidates = @[
        [bundlePath stringByAppendingPathComponent:@"libjailbreak.dylib"],
        [[NSBundle mainBundle] pathForResource:@"libjailbreak" ofType:@"dylib"] ?: @"",
        @"/var/jb/basebin/libjailbreak.dylib",
        @"/var/jb/usr/lib/libjailbreak.dylib",
        @"/usr/lib/libjailbreak.dylib",
    ];

    for (NSString *path in candidates) {
        if (path.length == 0) continue;
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;
        dlerror();
        void *h = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
        if (h) {
            NSLog(@"%@ libjailbreak loaded: %@", kKFDLogPrefix, path);
            return h;
        }
    }

    NSLog(@"%@ failed to load libjailbreak: %s", kKFDLogPrefix, dlerror());
    return nullptr;
}

static void TryPlatformize(void *handle) {
    if (!handle) return;
    typedef void (*void_fn_t)(void);
    const char *symbols[] = {
        "platformize",
        "jb_platformize",
        "jb_oneshot_fix_setuid_now",
        nullptr
    };

    for (int i = 0; symbols[i]; ++i) {
        void_fn_t fn = (void_fn_t)dlsym(handle, symbols[i]);
        if (fn) {
            NSLog(@"%@ call %s()", kKFDLogPrefix, symbols[i]);
            fn();
        }
    }
}

static bool CallJbdInitPPLRWFlexible(void *handle, uint64_t *resultOut) {
    if (resultOut) *resultOut = 0;
    if (!handle) return false;

    dlerror();
    void *sym = dlsym(handle, "jbdInitPPLRW");
    const char *err = dlerror();
    if (err || !sym) {
        NSLog(@"%@ dlsym jbdInitPPLRW failed: %s", kKFDLogPrefix, err ? err : "null symbol");
        return false;
    }

    typedef uint64_t (*jbd_init_u64_t)(void);
    jbd_init_u64_t initFn = (jbd_init_u64_t)sym;
    uint64_t result = initFn();
    if (resultOut) *resultOut = result;
    NSLog(@"%@ jbdInitPPLRW returned: 0x%llx", kKFDLogPrefix, (unsigned long long)result);
    return true;
}

static void LogTargetMainMachOHeader(NSString *targetName, uint64_t base, uint64_t vmMapPmap) {
    NSString *nameForLog = targetName.length ? targetName : @"<unknown>";
    if (!base || !vmMapPmap || !KFD::Handle()) {
        NSLog(@"%@[%@] header read skipped: base=0x%llx pmap=0x%llx handle=%p",
              kKFDMachOPrefix,
              nameForLog,
              (unsigned long long)base,
              (unsigned long long)vmMapPmap,
              KFD::Handle());
        return;
    }

    struct mach_header_64 header = KFD::ReadMemoryValue<struct mach_header_64>(&KFD::S().handle, base, vmMapPmap, "target_mach_header");
    if (header.magic != MH_MAGIC_64 && header.magic != MH_CIGAM_64) {
        NSLog(@"%@[%@] header read failed: base=0x%llx magic=0x%x",
              kKFDMachOPrefix,
              nameForLog,
              (unsigned long long)base,
              header.magic);
        return;
    }

    NSLog(@"%@[%@] header: base=0x%llx magic=0x%x cputype=0x%x cpusubtype=0x%x filetype=%u ncmds=%u sizeofcmds=%u flags=0x%x",
          kKFDMachOPrefix,
          nameForLog,
          (unsigned long long)base,
          header.magic,
          (unsigned int)header.cputype,
          (unsigned int)header.cpusubtype,
          header.filetype,
          header.ncmds,
          header.sizeofcmds,
          header.flags);

    struct load_command firstLC = KFD::ReadMemoryValue<struct load_command>(&KFD::S().handle, base + sizeof(struct mach_header_64), vmMapPmap, "target_first_load_command");
    NSLog(@"%@[%@] first load command: cmd=0x%x cmdsize=%u",
          kKFDMachOPrefix,
          nameForLog,
          firstLC.cmd,
          firstLC.cmdsize);
}

static bool InitByPidInternal(pid_t pid, NSString *targetName) {
    if (pid <= 0) return false;

    KFD::Reset();
    KFD::SetKernelReady(false);

    void *handle = LoadLibjailbreakHandle();
    if (!handle) return false;
    KFD::SetHandle(handle);

    TryPlatformize(handle);

    uint64_t jbdInitResult = 0;
    if (!CallJbdInitPPLRWFlexible(handle, &jbdInitResult)) {
        return false;
    }

    KFD::SetPid(pid);
    uint64_t proc_addr = KFD::call_proc_find(KFD::Handle(), pid);
    if (!proc_addr) {
        NSLog(@"%@ proc_find failed: pid=%d (jbdInit=0x%llx)", kKFDLogPrefix, pid, (unsigned long long)jbdInitResult);
        return false;
    }

    uint64_t task_addr = KFD::call_proc_task(KFD::Handle(), proc_addr);
    if (!task_addr) {
        NSLog(@"%@ proc_task failed: proc=0x%llx", kKFDLogPrefix, (unsigned long long)proc_addr);
        return false;
    }

    uint64_t vm_map = KFD::KextRW_kread_ptr(&KFD::S().handle, task_addr + 0x28);
    if (!vm_map) {
        NSLog(@"%@ vm_map read failed", kKFDLogPrefix);
        return false;
    }

    uint64_t offset_vm_map_pmap = 0x48;
    if (@available(iOS 15.4, *)) {
        offset_vm_map_pmap = 0x40;
    }

    uint64_t pmap = KFD::KextRW_kread_ptr(&KFD::S().handle, vm_map + offset_vm_map_pmap);
    if (!pmap) {
        NSLog(@"%@ pmap read failed: vm_map=0x%llx", kKFDLogPrefix, (unsigned long long)vm_map);
        return false;
    }

    uint64_t vm_map_pmap = KFD::KextRW_kread64(&KFD::S().handle, pmap + 0x8);
    if (!vm_map_pmap) {
        NSLog(@"%@ vm_map_pmap read failed: pmap=0x%llx", kKFDLogPrefix, (unsigned long long)pmap);
        return false;
    }

    size_t off_vm_map__hdr = KFD::probe_off_vm_map__hdr(vm_map);
    if (!off_vm_map__hdr) {
        NSLog(@"%@ probe_off_vm_map__hdr failed", kKFDLogPrefix);
        return false;
    }

    uint64_t base = KFD::find_main_exe_base_from_vm_map(vm_map, off_vm_map__hdr);
    if (!base) {
        NSLog(@"%@ target main image base not found", kKFDLogPrefix);
        return false;
    }

    KFD::S().proc_addr = proc_addr;
    KFD::S().task_addr = task_addr;
    KFD::S().vm_map = vm_map;
    KFD::S().pmap = pmap;
    KFD::S().vm_map_pmap = vm_map_pmap;
    KFD::SetBase(base);
    KFD::SetKernelReady(true);

    NSLog(@"%@ target process found: name=%@ pid=%d", kKFDLogPrefix, targetName, pid);
    NSLog(@"%@ target main image base found: 0x%llx", kKFDLogPrefix, (unsigned long long)base);
    LogTargetMainMachOHeader(targetName, base, vm_map_pmap);
    return true;
}

extern "C" bool kfd_init_by_name(const char *process_name) {
    if (!process_name || !*process_name) return false;
    int pid = KFD::findProcessByName(process_name);
    if (pid <= 0) {
        NSLog(@"%@ target process not found: name=%s", kKFDLogPrefix, process_name);
        return false;
    }
    NSString *targetName = [NSString stringWithUTF8String:process_name] ?: @"";
    return InitByPidInternal(pid, targetName);
}

extern "C" bool kfd_init_by_pid(pid_t pid) {
    NSString *targetName = ProcessNameFromPid(pid);
    if (targetName.length == 0) {
        targetName = [NSString stringWithFormat:@"pid:%d", pid];
    }
    return InitByPidInternal(pid, targetName);
}

extern "C" uint64_t kfd_image_base(void) {
    return KFD::Base();
}

extern "C" uint64_t kfd_vm_map_pmap(void) {
    return KFD::S().vm_map_pmap;
}

extern "C" bool kfd_read_mem(uint64_t vmAddr, void *out, size_t len) {
    if (!out || len == 0 || vmAddr == 0) return false;
    if (!KFD::KernelReady() || !KFD::Handle() || !KFD::S().vm_map_pmap) {
        NSLog(@"%@ read blocked: kernel not ready", kKFDLogPrefix);
        return false;
    }
    return KFD::KextRW_readMemory(&KFD::S().handle, vmAddr, out, len, KFD::S().vm_map_pmap);
}

extern "C" int kfd_entry_run(int argc, char *argv[]) {
    @autoreleasepool {
        const char *target = "DeltaForceClient";
        if (argc > 2 && argv[2] && argv[2][0] != '\0') {
            target = argv[2];
        }

        NSLog(@"%@ privileged entry start: target=%s uid=%d euid=%d",
              kKFDLogPrefix,
              target,
              getuid(),
              geteuid());

        if (!kfd_init_by_name(target)) {
            NSLog(@"%@ privileged init failed: target=%s", kKFDLogPrefix, target);
            return 2;
        }

        uint64_t base = kfd_image_base();
        uint64_t pmap = kfd_vm_map_pmap();
        if (!base || !pmap) {
            NSLog(@"%@ privileged state invalid: base=0x%llx pmap=0x%llx",
                  kKFDLogPrefix,
                  (unsigned long long)base,
                  (unsigned long long)pmap);
            return 3;
        }

        unsigned char header16[16] = {0};
        if (!kfd_read_mem(base, header16, sizeof(header16))) {
            NSLog(@"%@ privileged read failed: base=0x%llx", kKFDLogPrefix, (unsigned long long)base);
            return 4;
        }

        NSMutableString *hex = [NSMutableString stringWithCapacity:16 * 3];
        for (int i = 0; i < 16; i++) {
            [hex appendFormat:@"%02X ", header16[i]];
        }
        NSLog(@"%@ privileged read ok: base=0x%llx header16=%@",
              kKFDLogPrefix,
              (unsigned long long)base,
              hex);
        return 0;
    }
}
