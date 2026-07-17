# ADR-0001：采用 Flutter 与未来 Rust 服务端共用的 Monorepo

- 状态：已接受
- 日期：2026-07-17

## 背景

Lore 当前是 Flutter 本地优先应用，未来可能增加 Rust + Axum 后端，用于跨设备同步、云端备份和 AI 网关。客户端、服务端和协议需要长期保持一致，但当前阶段不应承担未使用后端的开发复杂度。

## 决策

- Flutter 应用、Dart packages、未来 Rust 服务、共享契约、工具和文档放在同一仓库。
- Dart 代码使用 Pub Workspace，未来 Rust 代码使用 Cargo Workspace。
- Dart 与 Rust 共享 OpenAPI、JSON Schema 和测试 fixtures，不共享领域源码。
- 当前只创建客户端需要的 workspace；Axum 服务在开始后端开发时再落地。
- 后端作为本地优先客户端的同步与服务能力扩展，不取代本地书库。

## 影响

- 跨端协议变更可以在同一提交中完成并验证。
- CI 需要按目录拆分 Flutter、Rust、契约和文档任务。
- 客户端和服务端会分别实现少量相同规则，需要使用共享 fixtures 保证兼容。
- 仓库顶层目录和依赖方向必须保持稳定，避免客户端 package 与服务端实现耦合。

