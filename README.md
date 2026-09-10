# DemoTweak — arm64e 越狱插件示例

Logos 越狱插件，由 GitHub Actions 自动构建 **arm64 + arm64e** rootless deb。

## 结构

- `DemoTweak/` — 插件源码（`Tweak.x`，Logos 语法）
- `.github/workflows/build.yml` — 自动构建流水线

## 流程

1. 修改 `DemoTweak/Tweak.x`
2. 提交并推送：

   ```sh
   git add -A
   git commit -m "update"
   git push
   ```

3. 打开 GitHub 仓库 → **Actions** → 等构建完成 → 下载 artifact `DemoTweak-rootless-arm64e`
4. deb 解压后即可用 Filza/Sileo 安装（RootHide/roothide 环境）

## 本地（iSH）快速验证 arm64

iSH 工具链只能出 arm64（不能真 arm64e），本地验证用：

```sh
ios-build deb DemoTweak
```

产物：`DemoTweak/packages/*.deb`

## 发布 Release

打 tag 推送即自动发布到 Releases：

```sh
git tag v1.0.0
git push origin v1.0.0
```

## 修改包信息

编辑 `DemoTweak/control`（包名、版本、描述、依赖）和 `Makefile`（目标进程、架构）。
