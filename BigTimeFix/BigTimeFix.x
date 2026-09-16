// BigTimeFix — 伴侣插件：诊断 + 修正 BigTime 锁屏时钟的"阴影边框"
//
// 背景结论（已实测）：
//   * 掩码缓存 /var/mobile/Library/Accessibility/liquidglass-clock-mask.bin 的格式已解出：
//       [28 字节头: "3CGL" | w | h(1172) | 2.0 | 24.0 | count] + [w*h 字节灰度遮罩]
//     还原出来是干净正确的字形（"19:32"），**遮罩本身没问题**
//   * 现象是一条**横贯整屏的硬边**，上下两种透光度 —— 属于玻璃合成层的问题，
//     最可能是某个 backdrop/模糊层的 frame 没有跟着视图 bounds 更新
//
// 本插件做两件事：
//   1) 只读日志：把层树与几何变化记录下来，供定位（写 /var/mobile/Library/Accessibility/btfix.log）
//   2) 一处安全自愈：layoutSubviews 后，如果发现 backdrop/模糊层的 frame 没盖住视图 bounds，
//      用 CATransaction 关动画把它拉回 bounds（幂等；没有不匹配就什么都不做）
//
// 急停：touch /var/mobile/Library/Accessibility/btfix.off  然后 respring → 插件完全不动作

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdarg.h>
#include <stdio.h>
#include <math.h>

#define BTFIX_DIR   "/var/mobile/Library/Accessibility"
#define BTFIX_OFF   BTFIX_DIR "/btfix.off"
#define BTFIX_LOG   BTFIX_DIR "/btfix.log"

// ------------------------------------------------------------------ 基础设施

static BOOL gOn      = NO;   // 总开关（有 btfix.off 就 NO）
static BOOL gGuard   = NO;   // 自愈：**默认关闭**，只有 btfix.guard 存在才开
static int  gLines   = 0;    // 已写行数（防日志爆掉）
static int  gGuardN  = 0;    // 已修正次数

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
        // ★ 自愈默认关闭：只有显式放 btfix.guard 才启用。
        //   这样"装上本插件"本身 = 只加了一份日志，零行为变化，主力机也安全。
        if (BTFileExists(BTFIX_DIR "/btfix.guard")) gGuard = YES;
        // 兼容旧开关：btfix.noguard 强制关掉自愈
        if (BTFileExists(BTFIX_DIR "/btfix.noguard")) gGuard = NO;
        // 截断旧日志
        int fd = open(BTFIX_LOG, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) close(fd);

        BTLog("=== BigTimeFix 0.2.0 启动 === 自愈=%s（放 btfix.guard 开启）"
              "  BigTime 类: glass=%s hub=%s backdrop=%s observer=%s driver=%s",
              gGuard ? "开" : "关",
              glass ? "有" : "无",
              hub ? "有" : "无",
              objc_getClass("LGClockBackdropView") ? "有" : "无",
              objc_getClass("LGClockScrollObserver") ? "有" : "无",
              objc_getClass("LGDisplayLinkDriver") ? "有" : "无");

        %init(BTMain);
    }
}
