// iOS26Clock — lock screen clock restyled with the iOS 26 adaptive variable font.
// Ported from the Clock surface of Liquid (Gl)ass with the liquid glass rendering removed.

#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import <TargetConditionals.h>
#import <objc/runtime.h>
#import "CLSharedSupport.h"

extern BOOL CL_prefBool(NSString *key, BOOL fallback);
extern CGFloat CL_prefFloat(NSString *key, CGFloat fallback);
extern NSString *CL_prefString(NSString *key, NSString *fallback);

static BOOL CLEnabled(void) {
    return CL_globalEnabled() && CL_prefBool(@"Clock.Enabled", YES);
}

static BOOL CLVariableFontEnabled(void) {
    return CL_prefBool(@"Clock.VariableFont.Enabled", YES);
}

static CGFloat CLFontScale(void) {
    return CL_prefFloat(@"Clock.VariableFont.SizeScale", 1.4);
}

static CGFloat CLAxisValue(NSString *axis) {
    if ([axis isEqualToString:@"weight"]) return CL_prefFloat(@"Clock.VariableFont.Weight", 750.0);
    if ([axis isEqualToString:@"width"]) return CL_prefFloat(@"Clock.VariableFont.Width", 100.0);
    if ([axis isEqualToString:@"height"]) return CL_prefFloat(@"Clock.VariableFont.Height", 350.0);
    if ([axis isEqualToString:@"softness"]) return CL_prefFloat(@"Clock.VariableFont.Softness", 56.0);
    return 0.0;
}

static BOOL CLDateFormatEnabled(void) {
    return CL_prefBool(@"Lockscreen.Clock.DateFormat.Enabled", YES);
}

static NSString *CLVariableFontPath(void) {
#if TARGET_OS_SIMULATOR
    return @"/opt/simject/PreferenceBundles/iOS26ClockPrefs.bundle/SFAdaptiveSoftNumeric-VF.otf";
#else
    return CLJBRootPath(@"/Library/PreferenceBundles/iOS26ClockPrefs.bundle/SFAdaptiveSoftNumeric-VF.otf");
#endif
}

static NSInteger CLSystemMajorVersion(void) {
    static NSInteger major = -1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *version = UIDevice.currentDevice.systemVersion ?: @"";
        major = version.integerValue;
    });
    return major;
}

// Uses explicit version checks instead of @available: this toolchain's clang 11
// emits ___isOSVersionAtLeast for @available and the SDK ships no compiler-rt
// defining it, which breaks linking.
static BOOL CLIsHost(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    if (CLSystemMajorVersion() >= 16) {
        return [name isEqualToString:@"CSProminentTimeView"];
    }
    return [name isEqualToString:@"SBFLockScreenDateView"];
}

static BOOL CLIsLegacySystem(void) {
    return CLSystemMajorVersion() < 16;
}

static BOOL CLIsLegacyHost(UIView *view) {
    return [NSStringFromClass(view.class) isEqualToString:@"SBFLockScreenDateView"];
}

static void *kCLLegacyDateOriginalFrameKey = &kCLLegacyDateOriginalFrameKey;

static BOOL CLIsDateLabel(UIView *view) {
    if (![view isKindOfClass:UILabel.class]) return NO;
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        NSString *name = NSStringFromClass(ancestor.class);
        if ([name isEqualToString:@"SBFLockScreenDateSubtitleDateView"] ||
            [name isEqualToString:@"CSProminentSubtitleDateView"]) return YES;
    }
    return NO;
}

static NSString *CLCustomDateString(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatter = [NSDateFormatter new]; });
    formatter.locale = [NSLocale autoupdatingCurrentLocale];
    formatter.timeZone = [NSTimeZone localTimeZone];
    NSString *format = CL_prefString(@"Lockscreen.Clock.DateFormat.Format", nil);
    formatter.dateFormat = format.length
        ? format
        : [NSDateFormatter dateFormatFromTemplate:@"EEE MMM d" options:0 locale:formatter.locale];
    NSString *text = [formatter stringFromDate:[NSDate date]] ?: @"";
    text = [text stringByReplacingOccurrencesOfString:@"," withString:@""];
    while ([text containsString:@"  "]) {
        text = [text stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static void CLApplyDateText(UILabel *label) {
    if (!label || !CLIsDateLabel(label)) return;
    static void *kApplying = &kApplying;
    static void *kOriginal = &kOriginal;
    static void *kLastCustom = &kLastCustom;
    if ([objc_getAssociatedObject(label, kApplying) boolValue]) return;

    NSString *lastCustom = objc_getAssociatedObject(label, kLastCustom);
    NSString *original = objc_getAssociatedObject(label, kOriginal);
    if (label.text.length && ![label.text isEqualToString:lastCustom]) {
        objc_setAssociatedObject(label, kOriginal, label.text, OBJC_ASSOCIATION_COPY_NONATOMIC);
        original = label.text;
    }
    BOOL custom = CLDateFormatEnabled();
    NSString *desired = custom ? CLCustomDateString() : original;
    objc_setAssociatedObject(label, kLastCustom, custom ? desired : nil,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (!desired.length || [label.text isEqualToString:desired]) return;
    objc_setAssociatedObject(label, kApplying, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    label.text = desired;
    objc_setAssociatedObject(label, kApplying, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void CLApplyDateTextInView(UIView *root) {
    if (!root) return;
    if ([root isKindOfClass:UILabel.class]) CLApplyDateText((UILabel *)root);
    for (UIView *child in root.subviews) CLApplyDateTextInView(child);
}

static UIView *CLFindDescendantNamed(UIView *root, NSString *className) {
    if (!root || !className.length) return nil;
    if ([NSStringFromClass(root.class) isEqualToString:className]) return root;
    for (UIView *child in root.subviews) {
        UIView *match = CLFindDescendantNamed(child, className);
        if (match) return match;
    }
    return nil;
}

static void CLPositionLegacyDateSubtitle(UIView *clockHost) {
    if (!clockHost || !CLIsLegacyHost(clockHost) || !clockHost.superview) return;
    UIView *subtitle = CLFindDescendantNamed(clockHost, @"SBFLockScreenDateSubtitleDateView");
    if (!subtitle || !subtitle.superview) return;
    NSValue *originalFrame = objc_getAssociatedObject(subtitle, kCLLegacyDateOriginalFrameKey);
    if (!originalFrame) {
        originalFrame = [NSValue valueWithCGRect:subtitle.frame];
        objc_setAssociatedObject(subtitle, kCLLegacyDateOriginalFrameKey,
                                 originalFrame, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!CLEnabled()) {
        subtitle.frame = originalFrame.CGRectValue;
        return;
    }
    UIView *container = clockHost.superview;
    clockHost.clipsToBounds = NO;
    clockHost.layer.masksToBounds = NO;
    CGRect clockFrame = [container convertRect:clockHost.bounds fromView:clockHost];
    CGRect subtitleFrame = [container convertRect:subtitle.frame fromView:subtitle.superview];
    subtitleFrame.origin.x = round(CGRectGetMidX(clockFrame) - CGRectGetWidth(subtitleFrame) * 0.5);
    subtitleFrame.origin.y = round(CGRectGetMinY(clockFrame) - CGRectGetHeight(subtitleFrame) + 10.0);
    subtitle.frame = [subtitle.superview convertRect:subtitleFrame fromView:container];
}

static BOOL CLLooksLikeTime(NSString *text) {
    if (!text.length || [text rangeOfString:@":"].location == NSNotFound) return NO;
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    return [text rangeOfCharacterFromSet:digits].location != NSNotFound;
}

static void CLCollectLabels(UIView *root, NSMutableArray<UILabel *> *labels) {
    if ([root isKindOfClass:UILabel.class]) [labels addObject:(UILabel *)root];
    for (UIView *child in root.subviews) CLCollectLabels(child, labels);
}

static BOOL CLLabelIsInsideClass(UILabel *label, UIView *host, NSString *className) {
    for (UIView *view = label.superview; view && view != host; view = view.superview) {
        if ([NSStringFromClass(view.class) isEqualToString:className]) return YES;
    }
    return NO;
}

static UILabel *CLFindSourceLabel(UIView *host) {
    if (CLIsLegacyHost(host)) {
        NSMutableArray<UILabel *> *labels = [NSMutableArray array];
        for (UIView *child in host.subviews) {
            if ([NSStringFromClass(child.class) isEqualToString:@"SBUILegibilityLabel"]) {
                CLCollectLabels(child, labels);
            }
        }
        UILabel *best = nil;
        CGFloat bestScore = -CGFLOAT_MAX;
        for (UILabel *label in labels) {
            NSString *text = label.text.length ? label.text : label.attributedText.string;
            if (!text.length || !CLLabelIsInsideClass(label, host, @"SBUILegibilityLabel")) continue;
            CGFloat score = label.font.pointSize;
            if (CLLooksLikeTime(text)) score += 1000.0;
            if (score > bestScore) {
                best = label;
                bestScore = score;
            }
        }
        return best;
    }

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    CLCollectLabels(host, labels);
    UILabel *best = nil;
    CGFloat bestScore = -CGFLOAT_MAX;
    for (UILabel *label in labels) {
        NSString *text = label.text.length ? label.text : label.attributedText.string;
        if (!text.length) continue;
        CGFloat score = label.font.pointSize;
        if (CLLooksLikeTime(text)) score += 1000.0;
        if ([NSStringFromClass(label.class) isEqualToString:@"_UIAnimatingLabel"]) score += 200.0;
        if (score > bestScore) {
            best = label;
            bestScore = score;
        }
    }
    return best;
}

static NSString *CLVariableFontPathString(void) __attribute__((unused));
static NSString *CLVariableFontPathString(void) {
    return CLVariableFontPath();
}

@interface CLFontStore : NSObject
@property (nonatomic) CGFontRef graphicsFont;
@property (nonatomic, copy) NSString *postScriptName;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *axisIDs;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<NSNumber *> *> *axisRanges;
@property (nonatomic, strong) NSCache<NSString *, UIFont *> *cache;
+ (instancetype)shared;
- (UIFont *)fontAtPointSize:(CGFloat)pointSize;
- (UIFont *)fontAtPointSize:(CGFloat)pointSize heightAxis:(CGFloat)heightAxis;
- (CGFloat)minimumHeightAxis;
@end

@implementation CLFontStore

+ (instancetype)shared {
    static CLFontStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [CLFontStore new]; });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _cache = [NSCache new];
    _cache.countLimit = 64;
    [self loadFont];
    return self;
}

- (void)dealloc {
    if (_graphicsFont) CGFontRelease(_graphicsFont);
}

- (void)loadFont {
    NSString *path = CLVariableFontPath();
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) {
        CLLog(@"font load failed path=%@", path);
        return;
    }
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    _graphicsFont = provider ? CGFontCreateWithDataProvider(provider) : NULL;
    if (provider) CGDataProviderRelease(provider);
    if (!_graphicsFont) {
        CLLog(@"font decode failed path=%@ bytes=%lu", path, (unsigned long)data.length);
        return;
    }
    _postScriptName = CFBridgingRelease(CGFontCopyPostScriptName(_graphicsFont));
    CFErrorRef error = NULL;
    BOOL registered = CTFontManagerRegisterGraphicsFont(_graphicsFont, &error);
    if (!registered && error) {
        CFIndex code = CFErrorGetCode(error);
        if (code != kCTFontManagerErrorAlreadyRegistered)
            CLLog(@"font registration failed ps=%@ error=%@", _postScriptName, error);
    }
    if (error) CFRelease(error);

    CTFontRef probe = CTFontCreateWithGraphicsFont(_graphicsFont, 60.0, NULL, NULL);
    NSArray<NSDictionary *> *axes = probe ? CFBridgingRelease(CTFontCopyVariationAxes(probe)) : nil;
    if (probe) CFRelease(probe);
    NSMutableDictionary *ids = [NSMutableDictionary dictionary];
    NSMutableDictionary *ranges = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in axes) {
        NSString *name = [entry[(id)kCTFontVariationAxisNameKey] lowercaseString];
        NSNumber *identifier = entry[(id)kCTFontVariationAxisIdentifierKey];
        if (!identifier) continue;
        NSString *key = nil;
        switch (identifier.unsignedIntValue) {
            case 'wght': key = @"weight";   break;
            case 'wdth': key = @"width";    break;
            case 'HGHT': key = @"height";   break;
            case 'SOFT': key = @"softness"; break;
            default: break;
        }
        if (!key && name.length) {
            if ([name containsString:@"weight"] || [name containsString:@"wght"]) key = @"weight";
            else if ([name containsString:@"width"] || [name containsString:@"wdth"]) key = @"width";
            else if ([name containsString:@"height"] || [name containsString:@"hght"]) key = @"height";
            else if ([name containsString:@"soft"]) key = @"softness";
        }
        if (!key) continue;
        ids[key] = identifier;
        ranges[key] = @[
            entry[(id)kCTFontVariationAxisMinimumValueKey] ?: @(-CGFLOAT_MAX),
            entry[(id)kCTFontVariationAxisMaximumValueKey] ?: @(CGFLOAT_MAX),
        ];
    }
    _axisIDs = ids;
    _axisRanges = ranges;
    CLLog(@"font ready path=%@ ps=%@ bytes=%lu axes=%@",
          path, _postScriptName, (unsigned long)data.length, ids);
}

- (CGFloat)clampedValueForAxis:(NSString *)axis {
    CGFloat value = CLAxisValue(axis);
    NSArray<NSNumber *> *range = self.axisRanges[axis];
    if (range.count == 2) value = MIN(MAX(value, range[0].doubleValue), range[1].doubleValue);
    return value;
}

- (UIFont *)fontAtPointSize:(CGFloat)pointSize {
    return [self fontAtPointSize:pointSize heightAxis:CLAxisValue(@"height")];
}

- (CGFloat)minimumHeightAxis {
    NSArray<NSNumber *> *range = self.axisRanges[@"height"];
    return range.count == 2 ? range[0].doubleValue : 100.0;
}

- (UIFont *)fontAtPointSize:(CGFloat)pointSize heightAxis:(CGFloat)heightAxis {
    if (!self.graphicsFont || !self.postScriptName.length) {
        CLLog(@"font request unavailable graphics=%p ps=%@ size=%.2f height=%.1f",
              self.graphicsFont, self.postScriptName, pointSize, heightAxis);
        return nil;
    }
    pointSize = MAX(1.0, pointSize);
    NSString *key = [NSString stringWithFormat:@"%.2f|%.1f|%.1f|%.1f|%.1f",
                     pointSize,
                     [self clampedValueForAxis:@"weight"],
                     [self clampedValueForAxis:@"width"],
                     heightAxis,
                     [self clampedValueForAxis:@"softness"]];
    UIFont *cached = [self.cache objectForKey:key];
    if (cached) return cached;

    NSMutableDictionary *variations = [NSMutableDictionary dictionary];
    [self.axisIDs enumerateKeysAndObjectsUsingBlock:^(NSString *axis, NSNumber *identifier, BOOL *stop) {
        variations[identifier] = @([axis isEqualToString:@"height"]
            ? heightAxis : [self clampedValueForAxis:axis]);
    }];
    NSDictionary *attributes = @{
        (id)kCTFontNameAttribute: self.postScriptName,
        (id)kCTFontVariationAttribute: variations,
    };
    CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)attributes);
    CTFontRef ctFont = descriptor ? CTFontCreateWithFontDescriptor(descriptor, pointSize, NULL) : NULL;
    if (descriptor) CFRelease(descriptor);
    UIFont *font = CFBridgingRelease(ctFont);
    if (!font)
        CLLog(@"font create failed ps=%@ size=%.2f variations=%@", self.postScriptName,
              pointSize, variations);
    if (font) [self.cache setObject:font forKey:key];
    return font;
}

@end

@interface CLClockState : NSObject
@property (nonatomic, weak) UIView *host;
@property (nonatomic, weak) UILabel *sourceLabel;
@property (nonatomic, strong) UIFont *originalFont;
@property (nonatomic) CGFloat originalLabelAlpha;
@property (nonatomic) BOOL originalLabelHidden;
@property (nonatomic) BOOL applying;
@property (nonatomic) BOOL scheduled;
@property (nonatomic, copy) NSString *lastSignature;
- (void)scheduleApply:(NSString *)reason;
- (void)restore;
@end

static void *kCLClockStateKey = &kCLClockStateKey;
static void *kCLClockOriginalFontKey = &kCLClockOriginalFontKey;

static NSHashTable<CLClockState *> *CLClockStates(void) {
    static NSHashTable<CLClockState *> *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ states = [NSHashTable weakObjectsHashTable]; });
    return states;
}

static void CLScheduleKnownStates(NSString *reason) __attribute__((unused));
static void CLScheduleKnownStates(NSString *reason) {
    for (CLClockState *state in CLClockStates().allObjects) {
        if (state.host.window) [state scheduleApply:reason];
    }
}

static BOOL CLIsOurFont(UIFont *font) {
    return [font.fontName containsString:@"SFAdaptiveSoftNumeric"];
}

static UIFont *CLAttributedFont(UILabel *label) {
    if (!label.attributedText.length) return nil;
    UIFont *font = [label.attributedText attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    return font ?: [label.attributedText attribute:(__bridge NSString *)kCTFontAttributeName
                                           atIndex:0 effectiveRange:NULL];
}

static BOOL CLLabelUsesOurFont(UILabel *label) {
    if (CLIsOurFont(label.font)) return YES;
    return CLIsOurFont(CLAttributedFont(label));
}

@implementation CLClockState

- (void)scheduleApply:(NSString *)reason {
    if (self.scheduled) return;
    self.scheduled = YES;
    __weak CLClockState *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        CLClockState *state = weakSelf;
        if (!state) return;
        state.scheduled = NO;
        [state applyReason:reason];
    });
}

- (void)applyReason:(NSString *)reason {
    UIView *host = self.host;
    if (!host.window) return;
    UILabel *label = CLFindSourceLabel(host);
    if (label != self.sourceLabel) {
        [self restore];
        self.sourceLabel = label;
        UIFont *savedFont = objc_getAssociatedObject(label, kCLClockOriginalFontKey);
        if (!savedFont && !CLIsOurFont(label.font)) {
            savedFont = label.font;
            objc_setAssociatedObject(label, kCLClockOriginalFontKey,
                                     savedFont, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        self.originalFont = savedFont ?: label.font;
        self.originalLabelAlpha = label.alpha;
        self.originalLabelHidden = label.hidden;
    }
    if (!label) return;

    BOOL enabled = CLEnabled();
    BOOL variableFontEnabled = CLVariableFontEnabled();

    // The signature covers every input that can change the rendered result, so
    // repeated layout passes coalesce into a no-op.
    NSString *signature = [NSString stringWithFormat:@"%d|%d|%@|%.2f|%.1f|%.1f|%.1f|%.1f",
                           enabled, variableFontEnabled, label.text ?: label.attributedText.string,
                           self.originalFont.pointSize,
                           variableFontEnabled ? CLAxisValue(@"weight") : 0.0,
                           variableFontEnabled ? CLAxisValue(@"width") : 0.0,
                           variableFontEnabled ? CLAxisValue(@"height") : 0.0,
                           variableFontEnabled ? CLAxisValue(@"softness") : 0.0];
    BOOL fontStateMatches = enabled ? (self.originalFont != nil)
                                    : !CLLabelUsesOurFont(label);
    if ([signature isEqualToString:self.lastSignature] && fontStateMatches) return;
    self.lastSignature = signature;
    self.applying = YES;

    if (!enabled) {
        if (self.originalFont) label.font = self.originalFont;
        label.alpha = self.originalLabelAlpha;
        label.hidden = self.originalLabelHidden;
    } else if (variableFontEnabled) {
        CGFloat pointSize = self.originalFont.pointSize * CLFontScale();
        UIFont *font = [[CLFontStore shared] fontAtPointSize:pointSize];
        if (font) {
            label.font = font;
            label.alpha = 1.0;
            label.hidden = NO;
        }
    }
    self.applying = NO;
    (void)reason;
}

- (void)restore {
    if (self.sourceLabel && !self.applying) {
        self.applying = YES;
        if (self.originalFont) self.sourceLabel.font = self.originalFont;
        self.sourceLabel.alpha = self.originalLabelAlpha;
        self.sourceLabel.hidden = self.originalLabelHidden;
        self.applying = NO;
    }
    self.sourceLabel = nil;
    self.originalFont = nil;
    self.lastSignature = nil;
}

@end

static CLClockState *CLStateForHost(UIView *host, BOOL create) {
    if (!CLIsHost(host)) return nil;
    CLClockState *state = objc_getAssociatedObject(host, kCLClockStateKey);
    if (!state && create) {
        state = [CLClockState new];
        state.host = host;
        [CLClockStates() addObject:state];
        objc_setAssociatedObject(host, kCLClockStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static void CLSourceFontDidChange(UILabel *label, UIFont *candidate, NSString *reason) {
    UIView *host = label.superview;
    while (host && !CLIsHost(host)) host = host.superview;
    if (!host) return;

    UIFont *font = candidate ?: CLAttributedFont(label) ?: label.font;
    if (!CLEnabled()) return;

    CLClockState *state = CLStateForHost(host, YES);
    if (state.applying || !font || CLIsOurFont(font)) return;

    state.originalFont = font;
    objc_setAssociatedObject(label, kCLClockOriginalFontKey,
                             font, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void CLSourceTextDidChange(UILabel *label) {
    UIView *host = label.superview;
    while (host && !CLIsHost(host)) host = host.superview;
    if (!host) return;
    if (!CLEnabled()) return;

    CLClockState *state = CLStateForHost(host, YES);
    if (state.applying) {
        [state scheduleApply:@"text-after-apply"];
        return;
    }
    CLSourceFontDidChange(label, nil, @"text");
    [state scheduleApply:@"text"];
}

static void CLHostDidMove(UIView *host) {
    CLClockState *state = CLStateForHost(host, CLEnabled() && host.window != nil);
    if (!CLEnabled() || !host.window) {
        [state restore];
        objc_setAssociatedObject(host, kCLClockStateKey, nil, OBJC_ASSOCIATION_ASSIGN);
        return;
    }
    [state scheduleApply:@"window"];
}

static void CLHostDidLayout(UIView *host) {
    if (!CLEnabled()) return;
    [CLStateForHost(host, YES) scheduleApply:@"layout"];
}

static void CLRefreshWindows(void) {
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];
        while (stack.count) {
            UIView *view = stack.lastObject;
            [stack removeLastObject];
            if (CLIsDateLabel(view)) CLApplyDateText((UILabel *)view);
            if (CLIsHost(view)) {
                CLClockState *state = CLStateForHost(view, CLEnabled());
                if (CLEnabled()) [state scheduleApply:@"prefs"];
                else [state restore];
            }
            [stack addObjectsFromArray:view.subviews];
        }
    }
}

static void CLReconcilePreferenceReload(void) {
    if (CLEnabled()) {
        CLRefreshWindows();
        return;
    }
    for (CLClockState *state in CLClockStates().allObjects) {
        [state restore];
        if (CLIsLegacyHost(state.host)) CLPositionLegacyDateSubtitle(state.host);
    }
}

// Split into per-class groups: every group is only %init-ed when its class
// actually exists in the running SpringBoard. Unconditional %init on a missing
// class (e.g. CSProminentTimeView on iPadOS, which never received the iPhone
// lock screen) makes MSHookMessageEx(NULL, ...) crash → instant safe mode.
%group CLAnimLabelHooks

%hook _UIAnimatingLabel
- (void)setFont:(UIFont *)font {
    %orig(font);
    CLSourceFontDidChange((UILabel *)self, font, @"setFont");
}
- (void)setText:(NSString *)text {
    %orig(text);
    if (CLIsDateLabel((UIView *)self)) {
        CLApplyDateText((UILabel *)self);
        return;
    }
    CLSourceTextDidChange((UILabel *)self);
}
- (void)setAttributedText:(NSAttributedString *)text {
    %orig(text);
    if (CLIsDateLabel((UIView *)self)) {
        CLApplyDateText((UILabel *)self);
        return;
    }
    CLSourceTextDidChange((UILabel *)self);
}
%end

%end

%group CLUILabelHooks

%hook UILabel

- (void)setText:(NSString *)text {
    %orig(text);
    if (CLIsDateLabel((UIView *)self)) {
        CLApplyDateText((UILabel *)self);
        return;
    }
    if (CLIsLegacySystem() &&
        CLLabelIsInsideClass((UILabel *)self, nil, @"SBUILegibilityLabel")) {
        CLSourceTextDidChange((UILabel *)self);
    }
}
- (void)setAttributedText:(NSAttributedString *)text {
    %orig(text);
    if (CLIsDateLabel((UIView *)self)) {
        CLApplyDateText((UILabel *)self);
        return;
    }
    if (CLIsLegacySystem() &&
        CLLabelIsInsideClass((UILabel *)self, nil, @"SBUILegibilityLabel")) {
        CLSourceTextDidChange((UILabel *)self);
    }
}
%end

%end

%group CLTimeViewHooks

%hook CSProminentTimeView
- (void)didMoveToWindow {
    %orig;
    CLHostDidMove((UIView *)self);
}
- (void)layoutSubviews {
    %orig;
    CLHostDidLayout((UIView *)self);
}
%end

%end

%group CLDateViewHooks

%hook SBFLockScreenDateView
- (void)didMoveToWindow {
    %orig;
    UIView *host = (UIView *)self;
    if (CLIsLegacySystem()) {
        CLApplyDateTextInView(host);
        CLPositionLegacyDateSubtitle(host);
    }
    CLHostDidMove(host);
}
- (void)layoutSubviews {
    %orig;
    UIView *host = (UIView *)self;
    if (CLIsLegacySystem()) {
        CLApplyDateTextInView(host);
        CLPositionLegacyDateSubtitle(host);
    }
    CLHostDidLayout(host);
}
%end

%hook SBFLockScreenDateSubtitleDateView
- (void)didMoveToWindow {
    %orig;
    if (CLIsLegacySystem()) {
        CLApplyDateTextInView((UIView *)self);
        UIView *host = ((UIView *)self).superview;
        while (host && !CLIsLegacyHost(host)) host = host.superview;
        CLPositionLegacyDateSubtitle(host);
    }
}
- (void)layoutSubviews {
    %orig;
    if (CLIsLegacySystem()) {
        CLApplyDateTextInView((UIView *)self);
        UIView *host = ((UIView *)self).superview;
        while (host && !CLIsLegacyHost(host)) host = host.superview;
        CLPositionLegacyDateSubtitle(host);
    }
}
%end

%end

%ctor {
    @autoreleasepool {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    CLLog(@"ctor os=%@ font=%@ hostModern=%@ hostLegacy=%@ animLabel=%@ enabled=%d variable=%d",
          UIDevice.currentDevice.systemVersion, CLVariableFontPath(),
          NSClassFromString(@"CSProminentTimeView"),
          NSClassFromString(@"SBFLockScreenDateView"), NSClassFromString(@"_UIAnimatingLabel"),
          CLEnabled(), CLVariableFontEnabled());
    @try {
        [CLFontStore shared];
        CLObservePreferenceChanges(^{ CLReconcilePreferenceReload(); });
        // UILabel always exists; everything else is hooked only when present.
        %init(CLUILabelHooks);
        if (NSClassFromString(@"_UIAnimatingLabel")) %init(CLAnimLabelHooks);
        if (NSClassFromString(@"CSProminentTimeView")) %init(CLTimeViewHooks);
        if (NSClassFromString(@"SBFLockScreenDateView")) %init(CLDateViewHooks);
        CLLog(@"hooks installed");
    } @catch (NSException *e) {
        CLLog(@"ctor exception %@ %@", e.name, e.reason);
    }
    }
}
