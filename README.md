# Lore

Lore 是一款面向网文写作者的本地优先写作软件，优先支持 macOS 和 Android。

## 仓库结构

```text
apps/lore_app/             Flutter 应用
packages/lore_domain/      领域模型与规则
packages/lore_application/ 应用用例与端口
packages/lore_storage/     本地存储实现
packages/lore_editor/      编辑器能力
packages/lore_ui/          主题与通用界面
contracts/                 未来客户端与服务端共享契约
docs/designs/              产品与技术设计文档
```

未来的 Rust + Axum 服务端将加入同一 monorepo，但当前阶段保持客户端和本地存储优先。

当前 macOS 版已支持本地书库选择、小说与正文注册、卷章创建和排序、文件树、TXT/Markdown 多标签编辑、Markdown 预览、安全自动保存和会话恢复。

## 开发环境

- Flutter 3.44.6 或兼容版本
- Dart 3.12.2 或兼容版本
- macOS 与 Android 开发工具链

## 常用命令

```bash
flutter pub get
dart format .
flutter analyze
(cd packages/lore_application && dart test)
(cd packages/lore_storage && flutter test)
(cd apps/lore_app && flutter test)
(cd apps/lore_app && flutter run -d macos)
```

设计文档入口见 [docs/designs/README.md](docs/designs/README.md)。
