# Lore

> 本地优先的网文写作软件，优先支持 macOS 与 Android。

Lore 面向长篇、连载网文作者。内容以开放文件格式（TXT、Markdown）保存在本地真实目录，不依赖 Lore 也能用 Finder、Git 或其他编辑器打开；索引、缓存等派生数据都可重建。

核心理念：**写作是核心，阅读是校验方式，书库是长期记忆，AI 是可控的创作协作者。**

## 现状

P0 阶段（`feat/p0-features` 分支）已打通核心写作闭环，并补齐四项基础功能。

**已实现**

- 单书库管理、真实文件系统、小说 / 正文 / 卷 / 章结构与拖拽排序
- 多标签页 TXT / Markdown 编辑、Markdown 预览
- 自动保存、外部变更检测、冲突处理、光标与会话恢复、崩溃恢复
- 设置页：主题（极简白 / 纸张 / 夜间）、默认章节格式、编辑器排版（字号 / 行高 / 行宽）、每日字数目标
- 查找替换：Cmd+F / Cmd+G / Cmd+Shift+G / Cmd+H，区分大小写、正则、`$1`-`$9` 捕获组
- 小说概览页：总字数、章节数、卷数、今日字数、目标进度、卷摘要、封面
- 删除与回收站：移入 `.lore/trash/`、清单、崩溃恢复、孤儿对账、恢复冲突策略、永久删除二次确认

**规划中**（详见 [路线图](docs/designs/quality-and-roadmap.md)）

全文搜索、模板系统、导入导出、阅读模式（章 / 卷 / 整书连续）、沉浸写作（打字机 / 专注）、历史版本、Android SAF 适配、AI Agent。

## 仓库结构

```text
apps/lore_app/             Flutter 应用（平台、providers、功能 UI）
packages/lore_domain/      领域模型与规则（无依赖）
packages/lore_application/ 用例、服务与仓储端口
packages/lore_storage/     本地文件系统持久化与恢复逻辑
packages/lore_editor/      文本编辑、查找替换、Markdown 预览
packages/lore_ui/          主题与通用展示样式
contracts/                 未来客户端与服务端共享契约
docs/designs/              产品与技术设计文档
docs/decisions/            架构决策记录（ADR）
```

依赖向内流动：UI 与 storage 依赖 application 的端口和 domain 类型，domain 包保持独立。未来的 Rust + Axum 服务端会加入同一 monorepo，但当前阶段保持客户端与本地存储优先。

## 开发环境

- Flutter 3.44.6 或兼容版本
- Dart 3.12.2 或兼容版本
- macOS 与 Android 工具链

## 快速开始

```bash
flutter pub get
(cd apps/lore_app && flutter run -d macos)   # Android：flutter run -d android
```

## 测试

```bash
./scripts/test.sh    # 一口气跑 flutter analyze + 所有包测试
```

> **本地代理注意**：若 shell 设了 `http_proxy`/`https_proxy`（如 Clash 的 `127.0.0.1:7890`），`flutter_tester` 的回环连接会失败，报 `HttpException: Connection closed`。`./scripts/test.sh` 已内置 `NO_PROXY=127.0.0.1,localhost`；手动跑 `flutter test` 前请同样设置。

单包测试：`(cd packages/lore_storage && flutter test)` 等，详见 [AGENTS.md](AGENTS.md)。

## 文档与贡献

- [docs/designs/](docs/designs/)：产品定义、内容模型、编辑与阅读、界面、架构、路线图
- [AGENTS.md](AGENTS.md)：构建 / 测试命令、代码风格、测试与提交规范

提交遵循 Conventional Commits，例如 `feat:`、`fix:`、`docs:`、`chore:`。
