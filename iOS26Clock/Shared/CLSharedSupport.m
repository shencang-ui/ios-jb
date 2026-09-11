#import "CLSharedSupport.h"
#import <os/lock.h>

static NSString * const sCLPrefsDomain = @"com.ios26.clockprefs";

NSString *CLJBRootPath(NSString *path) {
    static NSString *prefix;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        // roothide / Dopamine-style bootstraps expose the jailbreak root at /var/jb
        if ([fm fileExistsAtPath:@"/var/jb"]) prefix = @"/var/jb";
        else if ([fm fileExistsAtPath:@"/var/mobile"]) prefix = @"";
        else prefix = @"";
    });
    if (prefix.length == 0) return path;
    return [prefix stringByAppendingString:path];
}
CFStringRef const CLPrefsChangedNotification = CFSTR("com.ios26.clockprefs/Reload");
CFStringRef const CLPrefsRespringNotification = CFSTR("com.ios26.clockprefs/Respring");
static NSString * const sCLPrefsDidReloadInProcessNotification = @"com.ios26.clockprefs.InProcessReload";

static NSDictionary<NSString *, id> *sCLCachedPreferences = nil;
static os_unfair_lock sCLPrefsLock = OS_UNFAIR_LOCK_INIT;
static dispatch_once_t sCLPrefsSetupOnce;

NSString * const CLPrefsDomain = @"com.ios26.clockprefs";

static NSDictionary<NSString *, id> *CLCopyPreferencesDictionary(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)CLPrefsDomain);
    CFDictionaryRef values = CFPreferencesCopyMultiple(NULL,
                                                       (__bridge CFStringRef)CLPrefsDomain,
                                                       kCFPreferencesCurrentUser,
                                                       kCFPreferencesAnyHost);
    NSDictionary *dictionary = CFBridgingRelease(values);
    if (![dictionary isKindOfClass:[NSDictionary class]]) return @{};
    return dictionary;
}

static void CLPreferencesChanged(CFNotificationCenterRef center,
                                 void *observer,
                                 CFStringRef name,
                                 const void *object,
                                 CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        CLReloadPreferences();
        [[NSNotificationCenter defaultCenter] postNotificationName:sCLPrefsDidReloadInProcessNotification object:nil];
    });
}

static void CLEnsurePreferenceCacheInitialized(void) {
    dispatch_once(&sCLPrefsSetupOnce, ^{
        CLReloadPreferences();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        CLPreferencesChanged,
                                        CLPrefsChangedNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    });
}

NSString *CLMainBundleIdentifier(void) {
    static NSString *bundleID = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundleID = [NSBundle.mainBundle.bundleIdentifier copy] ?: @"";
    });
    return bundleID;
}

BOOL CLIsSpringBoardProcess(void) {
    return [CLMainBundleIdentifier() isEqualToString:@"com.apple.springboard"];
}

BOOL CLIsPreferencesProcess(void) {
    return [CLMainBundleIdentifier() isEqualToString:@"com.apple.Preferences"];
}

void CLReloadPreferences(void) {
    NSDictionary<NSString *, id> *dictionary = CLCopyPreferencesDictionary();
    os_unfair_lock_lock(&sCLPrefsLock);
    sCLCachedPreferences = dictionary;
    os_unfair_lock_unlock(&sCLPrefsLock);
}

void CLSetPreferenceValue(NSString *key, id value) {
    if (!key.length) return;
    if (value) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                 (__bridge CFTypeRef)value,
                                 (__bridge CFStringRef)CLPrefsDomain);
    } else {
        CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                 kCFNull,
                                 (__bridge CFStringRef)CLPrefsDomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)CLPrefsDomain);
    CLPostReloadNotification();
}

void CLPostReloadNotification(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CLPrefsChangedNotification,
                                         NULL, NULL, YES);
}

void CLPostRespringNotification(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CLPrefsRespringNotification,
                                         NULL, NULL, YES);
}

void CLObservePreferenceChanges(dispatch_block_t block) {
    if (!block) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:sCLPrefsDidReloadInProcessNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        block();
    }];
}

static id CLPreferenceValue(NSString *key) {
    if (!key.length) return nil;
    CLEnsurePreferenceCacheInitialized();
    NSDictionary<NSString *, id> *preferences = nil;
    os_unfair_lock_lock(&sCLPrefsLock);
    preferences = sCLCachedPreferences;
    os_unfair_lock_unlock(&sCLPrefsLock);
    return preferences[key];
}

BOOL CL_prefBool(NSString *key, BOOL fallback) {
    id value = CLPreferenceValue(key);
    if ([value isKindOfClass:[NSNumber class]]) return [value boolValue];
    return fallback;
}

CGFloat CL_prefFloat(NSString *key, CGFloat fallback) {
    id value = CLPreferenceValue(key);
    if ([value isKindOfClass:[NSNumber class]]) return (CGFloat)[value doubleValue];
    return fallback;
}

NSInteger CL_prefInteger(NSString *key, NSInteger fallback) {
    id value = CLPreferenceValue(key);
    if ([value isKindOfClass:[NSNumber class]]) return [value integerValue];
    return fallback;
}

NSString *CL_prefString(NSString *key, NSString *fallback) {
    id value = CLPreferenceValue(key);
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    return fallback;
}

BOOL CL_globalEnabled(void) {
    return CL_prefBool(@"Global.Enabled", YES);
}

void CLLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[iOS26Clock] %@", message);
}
