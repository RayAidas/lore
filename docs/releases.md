# 发布指南

本文档说明 Lore 如何发布 GitHub Release。当前阶段：**仅构建 macOS、不签名、不公证**。

## 发版流程

### 1. 更新版本号

编辑 `apps/lore_app/pubspec.yaml`：

```yaml
version: 0.1.0+1     # version: <x.y.z>+<build>
```

- `0.1.0` 是用户可见版本号，对应 git tag `v0.1.0`
- `+1` 是构建号，每次重新出包递增

### 2. 提交并打 tag

```bash
git add apps/lore_app/pubspec.yaml
git commit -m "chore(release): v0.1.0"
git tag v0.1.0
git push && git push --tags
```

### 3. 等 CI 跑完

推送 `v*` tag 后，`.github/workflows/release.yml` 自动：

1. `macos-latest` runner 上 checkout + 装 Flutter 3.44.6
2. 跑 `./scripts/test.sh`（analyze + 全部测试）作为质量门
3. `flutter build macos --release` 构建（ad-hoc 签名，无需 Apple 账号）
4. 用 `hdiutil` 把 `.app` 打成 `Lore-<版本>-macos-unsigned.dmg`（内含 `.app` + `/Applications` 软链，用户挂载后拖拽安装）
5. 用 `softprops/action-gh-release` 创建 Release 并挂上 dmg + 自动生成更新摘要

完成后，Release 出现在 <https://github.com/lovezhangchuangxin/lore/releases>。

> 在仓库 Actions 页可看到实时日志。若失败，修 bug、删掉本地与远端 tag，重新打 tag 推送即可。

### 手动测试流水线（不发版）

Actions 页 → 选 `release` workflow → Run workflow（默认分支）。这会只构建 + 上传 artifact，不创建 Release。用于在不打 tag 的情况下验证构建能否通过。

## 关于「未签名」的说明

由于没有 Apple Developer 账号（$99/年），macOS 产物只做了 **ad-hoc 临时签名**，**没有 Developer ID 签名与公证**。后果：

- 用户双击会看到「已损坏」或「无法验证开发者身份」
- 这只是 Gatekeeper 拦截，App 本身完好
- 解决：`xattr -cr /path/to/Lore.app`（Release 正文里已写明）

工程里 `macos/Runner.xcodeproj` 的 `CODE_SIGN_IDENTITY = "-"` 就是 ad-hoc 签名设置，CI 因此无需 Apple 凭证即可构建成功。

## 后续路线

| 阶段 | 增量 |
|---|---|
| 现在 | macOS 未签名 dmg（含 Applications 软链），用户拖拽安装后 `xattr -cr` 解锁 |
| 加 Android | workflow 里加 `flutter build apk --release`，挂 debug 签名 APK（可直接安装） |
| Android 正式 | 生成 release keystore → 存 GitHub Secrets → CI 注入 `key.properties` 出签名包；可上 Google Play |
| macOS 正式 | 申请 Apple Developer 账号 → 配 Developer ID 签名 + `notarytool` 公证（Apple ID 凭证存 Secrets）；可上 Mac App Store |

## 常见问题

**tag 打错了怎么办？**
```bash
git tag -d v0.1.0                      # 删本地
git push origin :refs/tags/v0.1.0      # 删远端
# 改完重打、重推
```
若 Release 已在 GitHub 上创建，到 Releases 页手动删除即可。

**版本号怎么定？**
- `0.x.y`：alpha / beta 阶段
- `1.0.0`：核心功能稳定、有签名后再定
- 遵循 [语义化版本](https://semver.org/lang/zh-CN/)：主版本.次版本.修订号
