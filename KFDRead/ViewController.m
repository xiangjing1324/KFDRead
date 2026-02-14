//
//  ViewController.m
//  KFDRead
//
//  Created by 大京 on 2025/10/31.
//

#import "ViewController.h"
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>
#import <signal.h>
#import <mach-o/dyld.h>

 
#import "kfd_c.h"     // 纯 C 接口
static NSString * const kTargetName = @"DeltaForceClient"; // 目标进程名（可按需修改）
extern char **environ;

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);

@interface ViewController ()
@property (strong, nonatomic) UIButton *testButton;
@property (atomic, assign) pid_t cachedPid;
@property (atomic, assign) mach_port_t cachedTask;
@end

@implementation ViewController

- (int)spawnPrivilegedReadForTarget:(NSString *)targetName {
    uint32_t size = 0;
    _NSGetExecutablePath(NULL, &size);
    if (size == 0) return -1;

    char *exePath = (char *)calloc(1, size);
    if (!exePath) return -1;
    if (_NSGetExecutablePath(exePath, &size) != 0) {
        free(exePath);
        return -1;
    }

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    int rcPersona = posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    int rcUID = posix_spawnattr_set_persona_uid_np(&attr, 0);
    int rcGID = posix_spawnattr_set_persona_gid_np(&attr, 0);
    NSLog(@"[KFD][KFDRead] spawn persona rc: persona=%d uid=%d gid=%d", rcPersona, rcUID, rcGID);

    const char *target = targetName.UTF8String ?: "DeltaForceClient";
    const char *args[] = { exePath, "-kfdread", target, NULL };
    pid_t pid = 0;
    int rc = posix_spawn(&pid, exePath, NULL, &attr, (char * const *)args, environ);
    NSLog(@"[KFD][KFDRead] posix_spawn rc=%d pid=%d", rc, pid);
    posix_spawnattr_destroy(&attr);
    free(exePath);

    if (rc != 0) return rc;

    int status = 0;
    const int maxWaitMs = 8000;
    int waitedMs = 0;
    while (waitedMs < maxWaitMs) {
        pid_t w = waitpid(pid, &status, WNOHANG);
        if (w == pid) {
            if (WIFEXITED(status)) return WEXITSTATUS(status);
            if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
            return -3;
        }
        if (w < 0) {
            return -4;
        }
        usleep(100000);
        waitedMs += 100;
    }

    kill(pid, SIGKILL);
    return -5;
}

#pragma mark - UI helpers (Alert/Toast)

- (void)showToast:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *toast = [[UILabel alloc] init];
        toast.text = text;
        toast.numberOfLines = 0;
        toast.textAlignment = NSTextAlignmentCenter;
        toast.textColor = [UIColor whiteColor];
        toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        toast.font = [UIFont boldSystemFontOfSize:15];
        toast.layer.cornerRadius = 10;
        toast.layer.masksToBounds = YES;
        toast.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.3].CGColor;
        toast.layer.shadowOpacity = 0.8;
        toast.layer.shadowRadius = 8;
        toast.layer.shadowOffset = CGSizeMake(0, 3);

        CGFloat maxWidth = self.view.bounds.size.width * 0.8;
        CGSize textSize = [toast sizeThatFits:CGSizeMake(maxWidth, CGFLOAT_MAX)];
        CGFloat width = textSize.width + 30;
        CGFloat height = textSize.height + 20;
        toast.frame = CGRectMake((self.view.bounds.size.width - width) / 2,
                                 self.view.bounds.size.height * 0.75,
                                 width, height);
        toast.alpha = 0.0;

        [self.view addSubview:toast];

        [UIView animateWithDuration:0.3 animations:^{
            toast.alpha = 1.0;
            toast.transform = CGAffineTransformMakeScale(1.05, 1.05);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.15 animations:^{
                toast.transform = CGAffineTransformIdentity;
            } completion:^(BOOL finished) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [UIView animateWithDuration:0.3 animations:^{
                        toast.alpha = 0.0;
                    } completion:^(BOOL finished) {
                        [toast removeFromSuperview];
                    }];
                });
            }];
        }];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"Hello viewDidload");
    NSString *bundleLibJB = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"libjailbreak.dylib"];
    BOOL hasSystemLib = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/lib/libjailbreak.dylib"];
    BOOL hasBundleLib = [[NSFileManager defaultManager] fileExistsAtPath:bundleLibJB];
    NSLog(@"= %d systemLib=%d bundleLib=%d", [self pidForProcessName:kTargetName], hasSystemLib, hasBundleLib);
    NSLog(@"uid=%d euid=%d", getuid(), geteuid());

    // 添加“运行KFD物理读取测试”按钮
    self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.testButton setTitle:@"运行KFD物理读取测试" forState:UIControlStateNormal];
    self.testButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.testButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.testButton.backgroundColor = [UIColor systemBlueColor];
    self.testButton.layer.cornerRadius = 10;
    self.testButton.layer.masksToBounds = YES;
    [self.testButton addTarget:self action:@selector(runKFDTestTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.testButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.testButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.testButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.testButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.testButton.widthAnchor constraintEqualToConstant:220],
        [self.testButton.heightAnchor constraintEqualToConstant:46],
    ]];

}

#pragma mark - Actions

- (void)runKFDTestTapped:(id)sender {
    [self showToast:@"开始读取目标 Mach-O 头部…"];
    NSLog(@"[UI] 开始读取目标 Mach-O 头部…");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        pid_t pid = [self pidForProcessName:kTargetName];
        NSLog(@"[Check] 目标进程名=%@, pid=%d", kTargetName, pid);

        NSString *bundleLibJB = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"libjailbreak.dylib"];
        NSArray<NSString *> *paths = @[ bundleLibJB,
                                        @"/var/jb/basebin/libjailbreak.dylib",
                                        @"/var/jb/usr/lib/libjailbreak.dylib",
                                        @"/usr/lib/libjailbreak.dylib" ];
        __block NSString *hit = nil;
        [paths enumerateObjectsUsingBlock:^(NSString *p, NSUInteger idx, BOOL *stop){
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) { hit = p; *stop = YES; }
        }];
        NSLog(@"[Check] libjailbreak.dylib %@%@", hit ? @"存在: " : @"不存在", hit ?: @"");
        int ok = 0;
        int rc = [self spawnPrivilegedReadForTarget:kTargetName];
        NSLog(@"[KFD][KFDRead] privileged spawn exit=%d", rc);
        if (rc == 0) ok = 1;
        int ok_local = ok;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok_local) {
                [self showToast:@"读取成功：请看 [KFD][KFDRead] 日志"];
            } else {
                [self showToast:@"读取失败，请查看日志！"];
                NSLog(@"[ERR] 读取失败：请确认越狱库/目标进程/权限是否满足");
            }
        });
    });
}






// 获取进程 ID
- (pid_t)pidForProcessName:(NSString *)processName {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t miblen = 4;

    size_t size;
    if (sysctl(mib, (u_int)miblen, NULL, &size, NULL, 0) < 0) return -1;

    struct kinfo_proc *process = NULL;
    process = malloc(size);
    if (!process) return -1;

    if (sysctl(mib, (u_int)miblen, process, &size, NULL, 0) < 0) {
        free(process);
        return -1;
    }

    int procCount = (int)(size / sizeof(struct kinfo_proc));
    pid_t pid = -1;
    for (int i = 0; i < procCount; i++) {
        NSString *name = [NSString stringWithFormat:@"%s", process[i].kp_proc.p_comm];
        if ([name isEqualToString:processName]) {
            pid = process[i].kp_proc.p_pid;
            break;
        }
    }

    free(process);
    return pid;
}

@end
