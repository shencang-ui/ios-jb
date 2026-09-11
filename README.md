# iOS26Clock — GitHub Actions 构建说明

> **分支说明**：本仓库 `ios26clock` 分支 = iOS26Clock 插件（本说明）；
> `main` 分支 = DemoTweak 示例流水线（iSH 那套工具），两边互不干扰，各建各的。

## 为什么改用 GitHub 构建

本地 WSL 那套 theos 工具链（2023 年构建，clang 11.1 + ld64-609）**只能产出 arm64e 老 ABI**
（cpusubtype `0x00000002`）。在 iOS 17 / M1 这类现代设备上，老 ABI 会让
**字符串字面量的 isa 指针认证失败**，直接崩掉 SpringBoard（黑屏 / 安全模式）。

GitHub 的 **macOS 运行器**自带现代 Xcode，其 `ld64` 天生产出 **arm64e 新 ABI**
（cpusubtype `0x80000002`，和店里能正常工作的 tweak 一致），
**从根上消除这个问题**——不需要任何"免字面量"之类的变通。

工作流里专门加了一步 **ABI 校验**：如果产物不是 `0x80000002`，构建直接失败并报错，
不会给你一个装上去会崩的包。

---

## 仓库布局（已接线）

- 仓库：`https://github.com/shencang-ui/ios-jb`（公开仓库，macOS 构建免费不限时）
- **`main` 分支**：DemoTweak 示例插件 + iSH 流水线，**与本插件无关，不要动**
- **`ios26clock` 分支**：本插件全部内容；推送到该分支自动触发 **Build iOS26Clock**

### 看构建结果

仓库 **Actions** 标签页 → 工作流 **Build iOS26Clock**：

- 绿勾 = 成功
- 点进那次运行 → 页面底部 **Artifacts** → 下载 `iOS26Clock-deb`
- 解压得到 `com.ios26.clock_*.deb`，用 Sileo 安装

---

## 日常使用

改完代码：

```bash
git add .
git commit -m "改了什么"
git push
```

构建完在 Actions 里下载新的 deb 就行。**不用再碰本机的 theos、WSL、SSH。**

也可以到 Actions 页面点 **Run workflow** 手动触发。

---

## 关键看这两处

**1. "校验 arm64e ABI" 这一步的输出**

```
  iOS26Clock.dylib         cpusubtype=0x80000002
  iOS26ClockPrefs          cpusubtype=0x80000002

== ABI 校验通过：全部是 arm64e 新 ABI (0x80000002) ==
```

只要看到这一行，就说明**字面量问题已经从根上解决**，装上不会再黑屏。

**2. "显示工具链版本" 这一步**

会打印 `xcrun ld -v` 的版本。记录一下，以后排查有用。

---

## 仓库结构

```
.
├── .github/workflows/build.yml          # 构建工作流
├── ci/theos-vendor/                     # roothide 魔改件
│   ├── vendor/mod/roothide/             #   theos roothide 模块
│   ├── vendor/lib/iphone/roothide/      #   libroot.a / libsubstrate.tbd 等
│   └── include/                         #   roothide.h / CydiaSubstrate.h
└── iOS26Clock/                          # 插件源码
    ├── Clock.x                          # 主 tweak
    ├── Shared/                          # 偏好读写 / 版本垫片
    └── iOS26ClockPrefs/                 # 设置页 bundle
```

## 注意事项

- **`libsubstrate.tbd` 的 install-name 必须保持**
  `@loader_path/.jbroot/usr/lib/libsubstrate.dylib`
  —— 这是"字体不生效"的根因修复，改动会全毁。
- **不要用 `@available`**：老工具链下会产生未定义符号 `___isOSVersionAtLeast`。
  项目已用 `Shared/CL_OSVersionShim.m` 垫片解决，别删。
- 构建产物在 `iOS26Clock/packages/`，已加进 `.gitignore`。
- 如果第一次跑失败，大概率是 `ldid` 或 SDK 那两步，把 Actions 日志发我即可。
