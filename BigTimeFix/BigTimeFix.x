// BigTimeFix — BigTime 伴侣插件
//
// 做三件事：
//   1) **字体路径重定向（v0.3.0 新增，默认开启）**
//      BigTime 写死的字体请求路径是 /var/mobile/Axs/字体素材/axs66.otf（UTF-16 常量，
//      从 BigTime.dylib @0x20158 抠出来的）。这是个"明面路径"，容易被越狱检测盯上。
//      本插件把对 /var/mobile/Axs 开头的访问改写到 **jbroot 真实越狱路径**：
//        <jbroot真实根>/var/mobile/Axs/字体素材/axs66.otf
//      jbroot 真实根形如 /var/mobile/Containers/Shared/AppGroup/.jbroot-XXXXXXXXXXXX，
//      每台设备随机 → 运行时用 roothide 的 jbroot() 算，不写死。
//      真实路径下不存在就**回退原路径**，不会因为没放字体而彻底失效。
//   2) 只读日志：层树 / 几何变化 / 高度轴 / 遮罩重建耗时 / 字体 / FPS
//      → /var/mobile/Library/Accessibility/btfix.log
//   3) layer 自愈（默认关闭）：backdrop/模糊层 frame 没盖住 bounds 时拉回
//
// 开关（放在 /var/mobile/Library/Accessibility/，改完 respring）：
//   btfix.off        急停：插件完全不动作
//   btfix.noredirect 只关掉字体重定向
//   btfix.guard      开启 layer 自愈（默认关）
//   btfix.noguard    强制关掉 layer 自愈
//   btfix.fontdir    内容写一个目录路径 → 覆盖重定向目标（把 /var/mobile/Axs 后面的部分接上去）

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#include <roothide.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdarg.h>
#include <stdio.h>
#include <math.h>
#include <sys/stat.h>

#define BTFIX_DIR   "/var/mobile/Library/Accessibility"
#define BTFIX_OFF   BTFIX_DIR "/btfix.off"
#define BTFIX_LOG   BTFIX_DIR "/btfix.log"

// BigTime 内置的字体请求路径（UTF-16 常量，从 BigTime.dylib @0x20158 抠出来的）
#define BT_FONT_REQ "/var/mobile/Axs"

// ------------------------------------------------------------------ 基础设施

static BOOL gOn       = NO;   // 总开关（有 btfix.off 就 NO）
static BOOL gGuard    = NO;   // layer 自愈：**默认关闭**，只有 btfix.guard 存在才开
static BOOL gRedirect = YES;  // 字体路径重定向：**默认开启**（窄过滤 + 有回退，安全）
static int  gLines    = 0;    // 已写行数（防日志爆掉）
static int  gGuardN   = 0;    // 已修正次数
static int  gRedirN   = 0;    // 已重定向次数

static void BTLog(const char *fmt, ...) {
    if (!gOn || gLines > 40000) return;
    gLines++;
    char buf[1024];
    va_list ap; va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf) - 2, fmt, ap);
    va_end(ap);
    size_t n = strlen(buf);
    buf[n] = '\n'; buf[n+1] = 0;
    int fd = open(BTFIX_LOG, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    write(fd, buf, n + 1);
    close(fd);
}

static BOOL BTFileExists(const char *p) {
    return access(p, F_OK) == 0;
}

// ------------------------------------------------------------------ 字体路径重定向
//
// 背景：BigTime 的字体请求路径是写死的 /var/mobile/Axs/字体素材/axs66.otf。
// 这个"明面路径"会被越狱检测盯上。我们的做法：
//   把对 /var/mobile/Axs 开头的访问，改写到 **jbroot 真实越狱路径** 下的同名位置，
//   即 <jbroot真实根>/var/mobile/Axs/字体素材/axs66.otf
//   （jbroot 真实根形如 /var/mobile/Containers/Shared/AppGroup/.jbroot-XXXXXXXXXXXX，
//     每台设备随机，所以必须运行时算，不能写死。）
//
// 用 roothide/libroot 的 jbroot() 做转换（stub.h 里它会调到 libroot_dyn_jbrootpath）。
// 目标不存在时**回退原路径**，保证不会因为没放字体而彻底失效。

static BOOL BTStatExists(const char *p) {
    struct stat st;
    return p && stat(p, &st) == 0;
}

// 可选用配置文件覆盖：/var/mobile/Library/Accessibility/btfix.fontdir 里写一个目录
static NSString *BTFontDirOverride(void) {
    static NSString *cached = nil;
    static BOOL inited = NO;
    if (inited) return cached;
    inited = YES;
    int fd = open(BTFIX_DIR "/btfix.fontdir", O_RDONLY);
    if (fd >= 0) {
        char buf[PATH_MAX] = {0};
        ssize_t n = read(fd, buf, sizeof(buf) - 1);
        close(fd);
        if (n > 0) {
            while (n > 0 && (buf[n-1] == '\n' || buf[n-1] == '\r' || buf[n-1] == ' ')) buf[--n] = 0;
            if (n > 0 && buf[0] == '/') cached = [NSString stringWithUTF8String:buf];
        }
    }
    return cached;
}

// 返回重定向后的路径；不需要/不可用则返回 nil（调用方回退原值）
static NSString *BTRedirectPath(id pathOrURL) {
    if (!gOn || !gRedirect) return nil;

    NSString *p = nil;
    if ([pathOrURL isKindOfClass:[NSURL class]]) {
        NSURL *u = (NSURL *)pathOrURL;
        if (!u.isFileURL) return nil;
        p = u.path;
    } else if ([pathOrURL isKindOfClass:[NSString class]]) {
        p = (NSString *)pathOrURL;
    } else {
        return nil;
    }
    if (p.length == 0) return nil;

    // ---- 窄过滤：只管 /var/mobile/Axs 这一条 ----
    if (![p hasPrefix:@(BT_FONT_REQ)]) return nil;
    // 已经是真实路径了就别再套一层
    if ([p containsString:@".jbroot-"]) return nil;

    NSString *target = nil;
    NSString *ov = BTFontDirOverride();
    if (ov) {
        // 配置了自定义目录：把 /var/mobile/Axs 之后的部分接上去
        NSString *tail = [p substringFromIndex:[@(BT_FONT_REQ) length]];
        target = [ov stringByAppendingString:tail];
    } else {
        // 默认：同相对路径的 jbroot 真实路径
        const char *real = jbroot(p.fileSystemRepresentation);
        if (real) target = [NSString stringWithUTF8String:real];
    }
    if (target.length == 0 || [target isEqualToString:p]) return nil;

    if (BTStatExists(target.fileSystemRepresentation)) {
        if (gRedirN < 40) {
            BTLog("REDIRECT %@  ->  %@", p, target);
            gRedirN++;
        }
        return target;
    }
    if (gRedirN < 40) {
        BTLog("REDIRECT-MISS %@  (真实路径下没有，回退原路径)", p);
        gRedirN++;
    }
    return nil;
}

// ------------------------------------------------------------------ 层树处理

static BOOL BTNameLooksLikeBackdrop(NSString *cls) {
    if (!cls) return NO;
    return [cls isEqualToString:@"CABackdropLayer"] ||
           [cls containsString:@"Backdrop"] ||
           [cls containsString:@"Blur"] ||
           [cls containsString:@"Filter"];
}

// 递归打印层树（限深，防爆）
static void BTLogTree(CALayer *l, int depth, int *budget) {
    if (!l || depth > 4 || *budget <= 0) return;
    (*budget)--;
    BTLog("%*s- %-34s frame=(%.1f,%.1f,%.1f,%.1f) op=%.2f hid=%d masks=%d %@",
          depth * 2, "", object_getClassName(l),
          l.frame.origin.x, l.frame.origin.y, l.frame.size.width, l.frame.size.height,
          l.opacity, l.hidden, l.masksToBounds,
          l.compositingFilter ?: @"");
    for (CALayer *s in l.sublayers) BTLogTree(s, depth + 1, budget);
}

// 找到并修正「本该铺满视图却没铺满」的 backdrop/模糊层
static int BTFixLayers(CALayer *l, CGRect full, int depth) {
    int fixed = 0;
    if (!l || depth > 4) return 0;
    for (CALayer *s in l.sublayers) {
        if (BTNameLooksLikeBackdrop(NSStringFromClass(s.class))) {
            CGRect f = s.frame;
            CGRect b = l.bounds;
            // 以「相对父层」的容差判断：明显小于父层 bounds 才算不匹配
            BOOL tooSmall = (f.size.height + 1.0 < b.size.height) ||
                            (f.size.width  + 1.0 < b.size.width);
            BOOL offset   = (fabs(f.origin.x) > 1.5) || (fabs(f.origin.y) > 1.5);
            if (tooSmall || offset) {
                BTLog("GUARD %s: %@ frame=(%.1f,%.1f,%.1f,%.1f) -> bounds=(%.1f,%.1f,%.1f,%.1f)",
                      object_getClassName(l), NSStringFromClass(s.class),
                      f.origin.x, f.origin.y, f.size.width, f.size.height,
                      b.origin.x, b.origin.y, b.size.width, b.size.height);
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                s.frame = b;
                s.hidden = NO;
                [CATransaction commit];
                fixed++; gGuardN++;
            }
        }
        fixed += BTFixLayers(s, full, depth + 1);
    }
    return fixed;
}

// ------------------------------------------------------------------ 类声明

@interface LGClockGlassView : UIView @end
@interface LGClockBackdropView : UIView @end
@interface LGSharedDisplayLinkHub : NSObject @end
@interface LGDisplayLinkDriver : NSObject @end
@interface LGClockScrollObserver : NSObject @end

// ------------------------------------------------------------------ 主 hook 组

%group BTMain

%hook LGClockGlassView

- (void)layoutSubviews {
    %orig;
    if (!gOn) return;
    @try {
        if (![self isKindOfClass:[UIView class]]) return;
        CALayer *root = self.layer;
        CGRect b = root.bounds;
        if (gGuard && BTFixLayers(root, b, 0) > 0) { /* 已在内部记日志 */ }
        // 只在尺寸变化时打一次层树
        static CGRect last = { {0, 0}, {0, 0} };
        if (!CGSizeEqualToSize(last.size, b.size)) {
            last = b;
            int budget = 40;
            BTLog("---- layer tree @ bounds=(%.1f,%.1f,%.1f,%.1f) cls=%s ----",
                  b.origin.x, b.origin.y, b.size.width, b.size.height, object_getClassName(self));
            BTLogTree(root, 0, &budget);
        }
    } @catch (NSException *e) {
        BTLog("EXC layoutSubviews: %@", e.reason);
    }
}

- (void)setFrame:(CGRect)f {
    %orig;
    if (gOn) BTLog("setFrame (%.1f,%.1f,%.1f,%.1f)", f.origin.x, f.origin.y, f.size.width, f.size.height);
}

- (void)setTargetDynamicHeightAxis:(double)v {
    %orig;
    if (gOn) BTLog("targetAxis = %.4f", v);
}

- (void)applyDynamicHeightAxis:(double)v {
    %orig;
    if (!gOn) return;
    static int n = 0;
    if ((n++ % 20) == 0) BTLog("applyAxis = %.4f  (call#%d) bounds=(%.1f,%.1f)", v, n,
                               self.layer.bounds.size.width, self.layer.bounds.size.height);
}

- (void)setCachedNearestNotificationTop:(double)v {
    %orig;
    if (gOn) BTLog("nearestNotificationTop = %.2f", v);
}

- (void)updateNativeBlurOverlayWithRadius:(double)r filterClass:(Class)c {
    %orig;
    if (gOn) BTLog("nativeBlurOverlay radius=%.2f filterClass=%s", r, c ? object_getClassName(c) : "(nil)");
}

- (BOOL)lg_maskNeedsRebuildForBounds:(CGRect)b {
    BOOL r = %orig;
    if (gOn) BTLog("maskNeedsRebuild(%.1f,%.1f,%.1f,%.1f) -> %d", b.origin.x, b.origin.y, b.size.width, b.size.height, r);
    return r;
}

- (void)lg_updateMask {
    double t0 = CFAbsoluteTimeGetCurrent();
    %orig;
    if (gOn) {
        CGRect b = self.layer.bounds;
        BTLog("updateMask bounds=(%.1f,%.1f,%.1f,%.1f) 用了 %.1f ms",
              b.origin.x, b.origin.y, b.size.width, b.size.height,
              (CFAbsoluteTimeGetCurrent() - t0) * 1000.0);
    }
}

- (void)setDisplayFont:(UIFont *)f {
    %orig;
    if (gOn) BTLog("displayFont = %@ / %@", f.familyName, f.fontName);
}

- (void)setDisplayCTFont:(id)f {
    %orig;
    if (gOn) {
        NSString *name = nil;
        @try { name = (__bridge NSString *)CTFontCopyPostScriptName((CTFontRef)f); } @catch (NSException *e) {}
        BTLog("displayCTFont = %@", name ?: @"(?)");
    }
}

- (void)syncFromSourceLabel:(id)src {
    %orig;
    if (gOn) BTLog("syncFromSourceLabel %s", src ? object_getClassName(src) : "(nil)");
}

%end

%hook LGClockBackdropView

- (void)layoutSubviews {
    %orig;
    if (!gOn) return;
    @try {
        if (![self isKindOfClass:[UIView class]]) return;
        CALayer *root = self.layer;
        if (gGuard) BTFixLayers(root, root.bounds, 0);
    } @catch (NSException *e) { }
}

%end

%hook LGSharedDisplayLinkHub

- (void)refreshForDisplayLink {
    %orig;
    if (!gOn) return;
    static int frames = 0;
    static double t0 = 0;
    frames++;
    double now = CFAbsoluteTimeGetCurrent();
    if (t0 == 0) t0 = now;
    if (now - t0 >= 2.0) {
        BTLog("FPS ≈ %.1f  (%d 帧 / %.1fs)", frames / (now - t0), frames, now - t0);
        frames = 0; t0 = now;
    }
}

- (void)setPreferredFramesPerSecond:(long long)v {
    %orig;
    if (gOn) BTLog("preferredFramesPerSecond = %lld (屏幕上限 %ld)", v,
                   (long)UIScreen.mainScreen.maximumFramesPerSecond);
}

%end

%hook LGClockScrollObserver

- (void)observeValueForKeyPath:(NSString *)k ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx {
    %orig;
    if (!gOn) return;
    static int n = 0;
    if ((n++ % 10) == 0) BTLog("scrollObserver KVO %@ (call#%d)", k, n);
}

- (instancetype)initWithScrollView:(id)sv host:(id)h overlay:(id)ov {
    id r = %orig;
    if (gOn) BTLog("scrollObserver init scrollView=%s host=%s overlay=%s",
                   sv ? object_getClassName(sv) : "(nil)",
                   h ? object_getClassName(h) : "(nil)",
                   ov ? object_getClassName(ov) : "(nil)");
    return r;
}

%end

%end  // BTMain

// ------------------------------------------------------------------ 字体重定向 hook 组
//
// 只拦截「会拿到文件路径」的那几个入口，且内部再做 /var/mobile/Axs 前缀过滤，
// 所以对 SpringBoard 里其它任何文件访问都是零影响。

%group BTFont

%hook NSFileManager

- (BOOL)fileExistsAtPath:(NSString *)path {
    NSString *m = BTRedirectPath(path);
    return %orig(m ?: path);
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDir {
    NSString *m = BTRedirectPath(path);
    return %orig(m ?: path, isDir);
}

- (BOOL)isReadableFileAtPath:(NSString *)path {
    NSString *m = BTRedirectPath(path);
    return %orig(m ?: path);
}

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)err {
    NSString *m = BTRedirectPath(path);
    return %orig(m ?: path, err);
}

- (NSData *)contentsAtPath:(NSString *)path {
    NSString *m = BTRedirectPath(path);
    return %orig(m ?: path);
}

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(NSError **)err {
    NSString *m = BTRedirectPath(path);
    return %orig(m ?: path, err);
}

%end

%hook NSData

+ (NSData *)dataWithContentsOfFile:(NSString *)path {
    NSString *m = BTRedirectPath(path);
    return %orig(m ?: path);
}

+ (NSData *)dataWithContentsOfFile:(NSString *)path options:(NSDataReadingOptions)opts error:(NSError **)err {
    NSString *m = BTRedirectPath(path);
    return %orig(m ?: path, opts, err);
}

+ (NSData *)dataWithContentsOfURL:(NSURL *)url {
    NSString *m = BTRedirectPath(url);
    return %orig(m ? [NSURL fileURLWithPath:m] : url);
}

- (NSData *)initWithContentsOfFile:(NSString *)path {
    NSString *m = BTRedirectPath(path);
    return %orig(m ?: path);
}

%end

%hook NSURL

+ (NSURL *)fileURLWithPath:(NSString *)path {
    NSString *m = BTRedirectPath(path);
    return %orig(m ?: path);
}

+ (NSURL *)fileURLWithPath:(NSString *)path isDirectory:(BOOL)isDir {
    NSString *m = BTRedirectPath(path);
    return %orig(m ?: path, isDir);
}

%end

%end  // BTFont

// ------------------------------------------------------------------ 构造

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;

        BOOL off = BTFileExists(BTFIX_OFF);
        if (off) {
            // 急停：不初始化任何 hook
            return;
        }

        Class glass = objc_getClass("LGClockGlassView");
        Class hub   = objc_getClass("LGSharedDisplayLinkHub");
        if (!glass && !hub) {
            // BigTime 没装/没加载，什么都不做
            return;
        }

        gOn = YES;
        // ★ layer 自愈默认关闭：只有显式放 btfix.guard 才启用。
        if (BTFileExists(BTFIX_DIR "/btfix.guard")) gGuard = YES;
        // 兼容旧开关：btfix.noguard 强制关掉自愈
        if (BTFileExists(BTFIX_DIR "/btfix.noguard")) gGuard = NO;
        // 字体重定向默认开启；放 btfix.noredirect 可单独关掉
        if (BTFileExists(BTFIX_DIR "/btfix.noredirect")) gRedirect = NO;

        // 截断旧日志
        int fd = open(BTFIX_LOG, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) close(fd);

        // 把真实越狱路径算出来记一笔，方便排查
        const char *probe = jbroot("/var/mobile/Axs/字体素材/axs66.otf");
        BOOL probeOK = probe && BTStatExists(probe);
        BTLog("=== BigTimeFix 0.3.0 启动 === 自愈=%s 字体重定向=%s"
              "  BigTime 类: glass=%s hub=%s backdrop=%s observer=%s driver=%s",
              gGuard ? "开" : "关(放 btfix.guard 开)",
              gRedirect ? "开" : "关",
              glass ? "有" : "无",
              hub ? "有" : "无",
              objc_getClass("LGClockBackdropView") ? "有" : "无",
              objc_getClass("LGClockScrollObserver") ? "有" : "无",
              objc_getClass("LGDisplayLinkDriver") ? "有" : "无");
        BTLog("jbroot 目标: %s   存在=%s", probe ?: "(null)", probeOK ? "是" : "否");
        BTLog("原始路径  : %s   存在=%s", "/var/mobile/Axs/字体素材/axs66.otf",
              BTStatExists("/var/mobile/Axs/字体素材/axs66.otf") ? "是" : "否");
        NSString *ov = BTFontDirOverride();
        if (ov) BTLog("btfix.fontdir 覆盖: %@", ov);

        %init(BTMain);
        %init(BTFont);
    }
}
