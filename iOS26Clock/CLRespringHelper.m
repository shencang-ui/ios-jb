// 注销支持：监听 Respring Darwin 通知，通过 SBSRelaunchAction 重启渲染服务器
// （与参考实现 liquidass Tweak.x 的 LG_requestRespring 同一方案）

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "CLSharedSupport.h"
#import <dlfcn.h>
// libproc.h 在本 SDK 缺失，手动声明用到的两个函数
#ifndef PROC_ALL_PIDS
#define PROC_ALL_PIDS 1
#endif
#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif
extern int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);
extern int proc_name(int pid, void *buffer, uint32_t buffersize);

typedef NS_OPTIONS(NSUInteger, SBSRelaunchActionOptions) {
    SBSRelaunchActionOptionsNone                   = 0,
    SBSRelaunchActionOptionsRestartRenderServer    = 1 << 0,
    SBSRelaunchActionOptionsSnapshotTransition     = 1 << 1,
    SBSRelaunchActionOptionsFadeToBlackTransition  = 1 << 2,
};

@interface SBSRelaunchAction : NSObject
+ (instancetype)actionWithReason:(NSString *)reason options:(SBSRelaunchActionOptions)options targetURL:(NSURL *)targetURL;
@end

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (void)sendActions:(NSSet *)actions withResult:(id)result;
@end

static void CLRequestRespring(void) {
    static const char * const processNames[] = {
        "chronod",
        "WidgetRenderer_Default",
        "WidgetRenderer_CarPlay",
        "backboardd",
        NULL,
    };

    int pidBufferSize = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (pidBufferSize > 0) {
        NSMutableData *pidData = [NSMutableData dataWithLength:(NSUInteger)pidBufferSize];
        int bytesReturned = proc_listpids(PROC_ALL_PIDS, 0,
                                          pidData.mutableBytes, (int)pidData.length);
        if (bytesReturned > 0) {
            pid_t *pids = (pid_t *)pidData.bytes;
            int pidCount = bytesReturned / (int)sizeof(pid_t);
            for (int i = 0; i < pidCount; i++) {
                pid_t pid = pids[i];
                if (pid <= 0 || pid == getpid()) continue;

                char processName[PROC_PIDPATHINFO_MAXSIZE];
                memset(processName, 0, sizeof(processName));
                if (proc_name(pid, processName, sizeof(processName)) <= 0) continue;

                for (NSUInteger nameIndex = 0; processNames[nameIndex]; nameIndex++) {
                    if (strcmp(processName, processNames[nameIndex]) != 0) continue;
                    if (kill(pid, SIGTERM) != 0) {
                        NSLog(@"[iOS26Clock] respring: failed to terminate %s pid %d errno %d",
                              processName, pid, errno);
                    }
                    break;
                }
            }
        }
    }

    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);

    Class actionClass  = objc_getClass("SBSRelaunchAction");
    Class serviceClass = objc_getClass("FBSSystemService");
    if (!actionClass || !serviceClass) return;

    SBSRelaunchAction *restart =
        [actionClass actionWithReason:@"iOS26Clock"
                              options:(SBSRelaunchActionOptionsRestartRenderServer |
                                       SBSRelaunchActionOptionsFadeToBlackTransition)
                            targetURL:nil];
    if (!restart) return;
    [[serviceClass sharedService] sendActions:[NSSet setWithObject:restart] withResult:nil];
}

static void CLRespringRequested(CFNotificationCenterRef center, void *observer,
                                CFStringRef name, const void *object,
                                CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ CLRequestRespring(); });
}

__attribute__((constructor)) static void CLRespringHelperInit(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
    BOOL isUIHost = [bundleID isEqualToString:@"com.apple.springboard"] ||
                    [bundleID hasPrefix:@"com.apple.UIKit"];
    if (!isUIHost) return;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    CLRespringRequested, CLPrefsRespringNotification,
                                    NULL, CFNotificationSuspensionBehaviorCoalesce);
}
