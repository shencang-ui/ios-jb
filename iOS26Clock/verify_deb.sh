#!/bin/bash
# 构建后自检：校验 deb 内的签名、链接路径、PreferenceLoader 条目、汉化资源
# 用法: bash verify_deb.sh <path-to-deb>   （CI 与本地通用）
set -u
DEB="$1"
fail=0

work=$(mktemp -d)
dpkg -x "$DEB" "$work" >/dev/null 2>&1 || { echo "FAIL: 无法解包 $DEB"; exit 1; }

echo "== 0. 包信息"
dpkg -I "$DEB" 2>/dev/null | grep -E "Package|Version|Architecture" | sed 's/^ *//'

DYLIB="$work/var/jb/Library/MobileSubstrate/DynamicLibraries/iOS26Clock.dylib"
[ -f "$DYLIB" ] || DYLIB="$work/Library/MobileSubstrate/DynamicLibraries/iOS26Clock.dylib"
BUNDLE="$work/var/jb/Library/PreferenceBundles/iOS26ClockPrefs.bundle"
[ -d "$BUNDLE" ] || BUNDLE="$work/Library/PreferenceBundles/iOS26ClockPrefs.bundle"
ENTRY="$work/var/jb/Library/PreferenceLoader/Preferences/iOS26ClockPrefs.plist"
[ -f "$ENTRY" ] || ENTRY="$work/Library/PreferenceLoader/Preferences/iOS26ClockPrefs.plist"

has_sig() {
python3 - "$1" <<'EOF'
import sys, struct
d = open(sys.argv[1],'rb').read()
n = struct.unpack_from('<I', d, 16)[0]
p = 32
for _ in range(n):
    cmd, size = struct.unpack_from('<II', d, p)
    if cmd == 0x1d:
        print("YES"); break
    p += size
else:
    print("NO")
EOF
}

has_arm64e() {
python3 - "$1" <<'EOF'
import sys, struct
d = open(sys.argv[1],'rb').read()
magic = struct.unpack_from('<I', d, 0)[0]
ok = False
if magic == 0xfeedfacf:
    cpu, sub = struct.unpack_from('<II', d, 4)
    ok = (cpu == 0x0100000c and sub == 2)
elif magic in (0xcafebabe, 0xbebafeca):
    nfat = struct.unpack_from('>I', d, 4)[0]
    for i in range(nfat):
        off = 8 + i*20
        cpu, sub = struct.unpack_from('>II', d, off)
        if cpu == 0x0100000c and sub == 2:
            ok = True
print("YES" if ok else "NO")
EOF
}

echo "== 1. tweak dylib"
if [ ! -f "$DYLIB" ]; then echo "FAIL: dylib 缺失"; fail=1; else
  [ "$(has_sig "$DYLIB")" = "YES" ] && echo "PASS: dylib 已签名" || { echo "FAIL: dylib 无签名块"; fail=1; }
  [ "$(has_arm64e "$DYLIB")" = "YES" ] && echo "PASS: 包含 arm64e" || { echo "WARN: 本包无 arm64e（本地 arm64 快速验证包？）"; }
  grep -aq '@loader_path/.jbroot/usr/lib/libsubstrate.dylib' "$DYLIB" \
    && echo "PASS: substrate 走 .jbroot 链接" || { echo "FAIL: substrate 链接路径错误"; fail=1; }
  grep -aq '@rpath/CydiaSubstrate.framework' "$DYLIB" \
    && { echo "FAIL: 残留 @rpath/CydiaSubstrate 引用"; fail=1; } \
    || echo "PASS: 无 @rpath/CydiaSubstrate 残留"
fi

echo "== 2. tweak 过滤器"
PLIST=$(dirname "$DYLIB")/iOS26Clock.plist
[ -f "$PLIST" ] && grep -q "com.apple.springboard" "$PLIST" \
  && echo "PASS: Filter 指向 com.apple.springboard" || { echo "FAIL: 过滤器缺失/错误"; fail=1; }

echo "== 3. PreferenceLoader 设置入口"
[ -f "$ENTRY" ] && grep -q "iOS26ClockPrefs" "$ENTRY" && grep -q "CLRootListController" "$ENTRY" \
  && echo "PASS: 入口 plist 存在" || { echo "FAIL: 设置入口缺失"; fail=1; }

echo "== 4. 偏好 bundle 完整性"
for f in "iOS26ClockPrefs" "SFAdaptiveSoftNumeric-VF.otf" "zh-Hans.lproj/Localizable.strings" "Info.plist" "icon.png"; do
  [ -f "$BUNDLE/$f" ] && echo "PASS: $f" || { echo "FAIL: 缺 $f"; fail=1; }
done
[ -f "$BUNDLE/iOS26ClockPrefs" ] && {
  [ "$(has_sig "$BUNDLE/iOS26ClockPrefs")" = "YES" ] && echo "PASS: bundle 二进制已签名" || { echo "FAIL: bundle 无签名"; fail=1; }
  [ "$(has_arm64e "$BUNDLE/iOS26ClockPrefs")" = "YES" ] && echo "PASS: bundle 含 arm64e" || { echo "WARN: bundle 无 arm64e"; }
}
[ -f "$BUNDLE/zh-Hans.lproj/Localizable.strings" ] && {
  python3 - "$BUNDLE/zh-Hans.lproj/Localizable.strings" <<'EOF' && echo "PASS: 汉化内容有效" || { echo "FAIL: 汉化内容异常"; fail=1; }
import sys, plistlib
try:
    d = plistlib.load(open(sys.argv[1], 'rb'))
except Exception:
    sys.exit(1)
sys.exit(0 if any('时钟' in str(v) for v in d.values()) else 1)
EOF
} || { echo "FAIL: 汉化内容异常"; fail=1; }

rm -rf "$work"
echo ""
if [ "$fail" = "0" ]; then echo "===== 自检全部通过 ====="; else echo "===== 存在失败项，禁止交付 ====="; exit 2; fi
