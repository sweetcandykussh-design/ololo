// mios_inject.h — shared force-injection engine (DoritosHelper equivalent).
//
// Static functions included by both mioshelperd (daemon) and mioscli (CLI). Uses task_for_pid +
// mach_vm_allocate + mach_vm_write + thread_create_running to dlopen a dylib into a running process
// from /var/tmp/ (sandbox-readable by every daemon). This is the mechanism Doritos uses for securityd
// (which must NEVER be killed — killall -9 securityd corrupts mach-port guards → EXC_GUARD crashes).
//
// On jailbroken iOS, system libraries (including libdyld → dlopen, libpthread → pthread_exit) live in
// the dyld shared cache at the SAME virtual address in every process, so we can resolve their addresses
// in our own process and set them as PC/LR in the target's new thread.

#pragma once

#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <stdio.h>
#include <string.h>

// mach_vm_* are in libsystem_kernel but not always exposed by the iOS SDK headers.
extern kern_return_t mach_vm_allocate(vm_map_t target, mach_vm_address_t *address,
                                      mach_vm_size_t size, int flags);
extern kern_return_t mach_vm_write(vm_map_t target_task, mach_vm_address_t address,
                                    vm_offset_t data, mach_msg_type_number_t dataCnt);
extern kern_return_t mach_vm_deallocate(vm_map_t target, mach_vm_address_t address,
                                         mach_vm_size_t size);

// Self-contained ARM64 thread state — avoids SDK header differences between arm64 and arm64e builds.
// Layout matches the kernel's expected format for thread flavor 6 (ARM_THREAD_STATE64).
typedef struct {
    uint64_t x[29];   // x0–x28
    uint64_t fp;       // x29
    uint64_t lr;       // x30
    uint64_t sp;       // x31
    uint64_t pc;
    uint32_t cpsr;
    uint32_t pad;
} mios_arm64_state_t;

#define MIOS_ARM_THREAD_STATE64       6
#define MIOS_ARM_THREAD_STATE64_COUNT ((mach_msg_type_number_t)(sizeof(mios_arm64_state_t) / sizeof(uint32_t)))

// Strip PAC bits from a function pointer (arm64e upper 16 bits contain the PAC; arm64 is a no-op).
static inline uint64_t mios_strip_pac(void *p) {
    return (uint64_t)(uintptr_t)p & 0x0000FFFFFFFFFFFF;
}

#pragma mark - Process lookup

static pid_t mios_find_pid(const char *name) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t sz = 0;
    if (sysctl(mib, 4, NULL, &sz, NULL, 0) != 0) return 0;
    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(sz);
    if (!procs) return 0;
    if (sysctl(mib, 4, procs, &sz, NULL, 0) != 0) { free(procs); return 0; }
    int n = (int)(sz / sizeof(struct kinfo_proc));
    pid_t result = 0;
    for (int i = 0; i < n; i++) {
        if (strcmp(procs[i].kp_proc.p_comm, name) == 0) {
            result = procs[i].kp_proc.p_pid;
            break;
        }
    }
    free(procs);
    return result;
}

#pragma mark - Dylib staging

static NSString *mios_stage_dylib(NSString *source) {
    NSString *name = source.lastPathComponent;
    NSString *dst = [@"/var/tmp" stringByAppendingPathComponent:name];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:dst error:nil];
    NSError *err = nil;
    if ([fm copyItemAtPath:source toPath:dst error:&err]) {
        chmod(dst.UTF8String, 0644);
        return dst;
    }
    return nil;
}

#pragma mark - Force injection

static kern_return_t mios_inject_pid(pid_t pid, const char *dylib_path) {
    mach_port_t task = MACH_PORT_NULL;
    kern_return_t kr;
    mach_vm_address_t remote_path = 0, remote_stack = 0;
    const mach_vm_size_t page_sz = 4096;
    const mach_vm_size_t stack_sz = 0x4000;

    kr = task_for_pid(mach_task_self(), pid, &task);
    if (kr != KERN_SUCCESS) return kr;

    kr = mach_vm_allocate(task, &remote_path, page_sz, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) goto fail;

    kr = mach_vm_write(task, remote_path, (vm_offset_t)dylib_path,
                        (mach_msg_type_number_t)(strlen(dylib_path) + 1));
    if (kr != KERN_SUCCESS) goto fail;

    kr = mach_vm_allocate(task, &remote_stack, stack_sz, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) goto fail;

    {
        uint64_t dlopen_addr      = mios_strip_pac(dlsym(RTLD_DEFAULT, "dlopen"));
        uint64_t pthread_exit_addr = mios_strip_pac(dlsym(RTLD_DEFAULT, "pthread_exit"));

        mios_arm64_state_t state;
        memset(&state, 0, sizeof(state));
        state.x[0]  = (uint64_t)remote_path;          // dlopen arg0: path
        state.x[1]  = RTLD_NOW | RTLD_GLOBAL;         // dlopen arg1: mode
        state.pc     = dlopen_addr;
        state.lr     = pthread_exit_addr;              // clean thread exit after dlopen returns
        state.sp     = (uint64_t)(remote_stack + stack_sz - 0x10); // 16-byte aligned

        thread_act_t thread;
        kr = thread_create_running(task, MIOS_ARM_THREAD_STATE64,
                                   (thread_state_t)&state, MIOS_ARM_THREAD_STATE64_COUNT, &thread);
        if (kr == KERN_SUCCESS) {
            mach_port_deallocate(mach_task_self(), thread);
        }
    }

    mach_port_deallocate(mach_task_self(), task);
    return kr;

fail:
    if (remote_path)  mach_vm_deallocate(task, remote_path, page_sz);
    if (remote_stack)  mach_vm_deallocate(task, remote_stack, stack_sz);
    mach_port_deallocate(mach_task_self(), task);
    return kr;
}

static BOOL mios_inject_process(const char *procName, const char *dylib_path) {
    pid_t pid = mios_find_pid(procName);
    if (pid == 0) return NO;
    return mios_inject_pid(pid, dylib_path) == KERN_SUCCESS;
}
