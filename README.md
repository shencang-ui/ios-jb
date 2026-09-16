# BigTimeFix — BigTime 伴侣修复插件

> **分支说明（各插件独立，互不干扰）**：
> - `bigtimefix` 分支 = **BigTimeFix**（本说明），本地工作区 `ci/repo-btfix`，工作流 `Build BigTimeFix`
> - `ios26clock` 分支 = iOS26Clock 锁屏时钟插件，工作流 `Build iOS26Clock`
> - `main` 分支 = DemoTweak 示例流水线（iSH 那套工具），不要动

## 功能

- BigTime 掩码"矩形阴影边框"问题的诊断与 backdrop 层自愈（带急停开关，默认关闭）
- 包名 `com.ios26.btfix`

## 日常使用

在本工作区（`ci/repo-btfix`）改完 `BigTimeFix/` 代码后：

```bash
bash "D:\Admin\Documents\ios26clock\ci\build_btfix.sh" "改了什么"
```

自动：提交 → 推送 `bigtimefix` 分支 → Actions 构建 → `BigTimeFix-deb` artifact。

## 注意事项

- **改代码只在这个工作区改，不要去 `ci/repo`**——那是 iOS26Clock 的地盘。
- 构建产物在 Actions run 页面底部 Artifacts 下载。
- ABI 校验不是 `0x80000002` 会直接构建失败，不会产出会崩的包。
