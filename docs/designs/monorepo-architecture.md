# Monorepo 架构设计

> 文档状态：初稿  
> 当前实现：Flutter 本地客户端  
> 未来扩展：Rust + Axum 后端

## 设计目标

- Flutter 客户端、未来 Rust 服务端、协议和工具放在同一仓库。
- 当前不因尚未存在的后端增加运行复杂度。
- 本地优先能力保持独立，后端不可用时仍可完整写作和阅读。
- 客户端与服务端共享协议和测试样例，不强行共享语言实现。
- 后端加入后提供同步、备份、AI 网关等能力，而不是取代本地文件系统。

## 顶层结构

```text
lore/
├── apps/
│   └── lore_app/                  # Flutter macOS、Android 应用
├── packages/
│   ├── lore_domain/               # Dart 领域模型与规则
│   ├── lore_application/          # Dart 用例、端口和事务编排
│   ├── lore_storage/              # 本地文件、元数据和 SQLite 实现
│   ├── lore_editor/               # 编辑器抽象和 Flutter 实现
│   ├── lore_ui/                   # 主题、布局和通用组件
│   └── lore_api_client/           # 未来由契约生成的 API 客户端
├── services/
│   └── lore_api/                  # 未来 Axum 二进制入口
├── crates/
│   ├── lore_server_domain/        # 服务端领域规则
│   ├── lore_server_application/   # 服务端用例
│   ├── lore_server_storage/       # PostgreSQL、对象存储
│   └── lore_server_common/        # Rust 通用类型和错误
├── contracts/
│   ├── openapi/                   # HTTP API 契约
│   ├── schemas/                   # 同步和元数据 JSON Schema
│   └── fixtures/                  # Dart、Rust 共用测试样例
├── docs/
│   ├── designs/                   # 产品与技术设计
│   ├── api/                       # API 使用说明
│   └── decisions/                 # Architecture Decision Records
├── tools/                          # 代码生成、迁移和开发工具
├── scripts/                        # 仓库级构建与检查脚本
└── infra/                          # 未来容器和部署配置
```

当前阶段只创建 Flutter 需要的 `apps`、`packages`、`contracts` 和文档结构。`services`、`crates` 与 `infra` 在开始后端开发时再加入实际工程，避免维护空壳代码。

## Workspace 管理

### Dart 与 Flutter

- 使用 Dart Pub Workspace 管理 `apps/lore_app` 和 `packages/*`。
- 根级 `pubspec.yaml` 只负责声明 workspace 成员和统一 SDK 下限。
- 每个 package 独立声明最小依赖，禁止通过应用包反向共享代码。
- Flutter 应用只负责启动、平台配置和功能组合。

### Rust

- 后端开始开发时在仓库根级增加 Cargo virtual workspace。
- `services/lore_api` 只包含 Axum 启动、路由装配和进程配置。
- 领域与应用逻辑放在 `crates`，避免写入 HTTP Handler。
- 不为了预留后端提前创建无法验证的 Rust crate。

### 仓库命令

- 根级脚本统一封装格式化、静态检查、测试和代码生成。
- Flutter 与 Rust 仍使用各自原生工具链，不强制引入 Node.js。
- CI 根据路径变化选择 Flutter、契约或 Rust 任务。

## Dart 包职责

### `lore_domain`

纯 Dart 包，不依赖 Flutter：

- 书库、小说、正文、卷、章模型。
- 稳定 ID、排序、编号和命名规则。
- 文件冲突、模板变量和领域事件。
- 可被 Application、测试工具和未来导入工具复用。

### `lore_application`

纯 Dart 包，依赖 `lore_domain`：

- 创建小说、卷章管理、保存和导入导出用例。
- 定义 `LibraryStorage`、仓储、时钟和 ID 生成等端口。
- 协调文件操作和元数据事务。
- 未来定义 `SyncRepository` 和 AI 工具调用边界。

### `lore_storage`

Flutter package，依赖 Domain 和 Application：

- macOS 本地目录存储实现。
- Android SAF 存储实现。
- JSON 元数据、历史、回收站和恢复日志。
- SQLite 搜索索引和本机状态。
- 文件监听及外部变更协调。

### `lore_editor`

Flutter package：

- 文本编辑器控制器和组件适配。
- Markdown 增量高亮与预览接口。
- 选区、查找替换、撤销栈和自动保存快照接口。
- 不负责决定文件路径和直接保存书库。

### `lore_ui`

Flutter package：

- 设计令牌、主题和排版系统。
- 桌面三栏、移动端基础布局和通用组件。
- 不包含小说创建、文件保存等业务用例。

### `lore_app`

Flutter 应用：

- 应用启动和依赖装配。
- Riverpod Provider 根节点。
- 路由、窗口、菜单和平台生命周期。
- 将各 package 组合为最终产品。

### `lore_api_client`

后端 API 确定后再创建：

- 根据 OpenAPI 等契约生成或封装客户端。
- 提供认证、同步和 AI 网关调用。
- 不向 UI 直接暴露 HTTP 细节。

## 客户端依赖方向

```text
lore_app
├── lore_ui
├── lore_editor
├── lore_storage
└── lore_application
    └── lore_domain
```

约束：

- `lore_domain` 不依赖任何仓库内 package。
- `lore_application` 只依赖 `lore_domain`。
- `lore_storage` 实现 Application 定义的端口。
- `lore_editor` 和 `lore_ui` 不依赖 `lore_storage`。
- `lore_app` 是唯一负责装配具体实现的组合根。
- package 之间禁止循环依赖。

## 本地优先与未来后端

后端加入后，用户编辑仍首先写入本地：

```text
编辑器
  ↓
本地正文安全保存
  ↓
本地元数据提交
  ↓
产生领域事件或变更记录
  ↓
后台同步服务上传
```

服务端未来负责：

- 用户、设备和会话认证。
- 书库跨设备同步和云端备份。
- 冲突版本与远端历史。
- AI 请求代理、模型配置和用量管理。
- 后续多人协作与作品发布。

服务端暂时不负责基础编辑、阅读、搜索和本地书库管理。网络不可用不能阻止这些能力。

## 同步预留

当前不实现同步，但本地模型保留以下条件：

- 对象使用 UUID，而非本地数据库自增 ID。
- 元数据包含 `schemaVersion` 和 `revision`。
- 结构操作从 Application 用例进入并能够产生领域事件。
- 删除进入回收站，并为未来 tombstone 保留对象 ID。
- 未来操作记录使用 `operationId` 支持幂等上传。
- 文件内容使用哈希检测版本差异。
- 冲突保留双方副本，不静默使用最后写入覆盖。

MVP 不实现 CRDT。单作者跨设备同步优先采用版本号、内容哈希和冲突副本；实时协作开始设计后再决定是否引入 CRDT。

## Dart 与 Rust 的共享边界

Dart 和 Rust 共享契约，不共享领域源码：

```text
contracts/openapi/lore-api.yaml
├── 生成或校验 Dart API Client
└── 生成或校验 Rust HTTP 类型

contracts/schemas/sync-operation.json
├── Dart 序列化测试
└── Rust serde 测试

contracts/fixtures/
├── Dart 行为测试
└── Rust 行为测试
```

不建议为了未来复用后端代码，将 Flutter 的领域和本地存储提前写成 Rust FFI。只有在编辑器解析、全文索引等功能经过性能测试确认 Dart 无法满足要求时，才针对具体热点评估 Rust 原生库。

## 未来 Axum 服务结构

```text
Axum HTTP / WebSocket
          ↓
lore_server_application
          ↓
lore_server_domain
          ↑
PostgreSQL / Object Storage / AI Provider
```

- Axum Handler 只处理认证、协议转换和响应映射。
- Application 负责同步、备份、AI 调用等用例。
- Domain 负责版本、权限、设备和冲突规则。
- Storage 负责 PostgreSQL、对象存储和事务。
- Redis 只在任务队列、限流或在线状态出现明确需求后引入。

建议的数据职责：

- PostgreSQL：账号、设备、书库、对象元数据、版本和同步操作。
- 对象存储：附件、备份和较大的正文历史版本。
- 客户端本地文件：作者正在编辑的主要副本。

## 契约管理

- HTTP API 使用 OpenAPI 作为权威契约。
- 同步操作和可交换元数据使用 JSON Schema。
- 生成代码可以提交仓库，保证客户端构建不依赖在线生成服务。
- 契约变更需要兼容性检查和对应测试样例。
- 服务端内部数据库模型不能直接作为客户端 API 模型。

## CI 边界

建议按路径触发任务：

| 变更范围 | 检查任务 |
| --- | --- |
| `apps/**`、`packages/**` | Dart format、analyze、test、Flutter build smoke test |
| `contracts/**` | Schema/OpenAPI 校验、生成代码一致性 |
| `services/**`、`crates/**` | cargo fmt、clippy、test |
| `docs/**` | Markdown 链接和格式检查 |

根级发布流程分别产出 macOS、Android 和未来服务端制品，不使用一个统一版本号强行绑定所有组件发布。

## 当前落地范围

当前只落地：

- `apps/lore_app`。
- `packages/lore_domain`。
- `packages/lore_application`。
- `packages/lore_storage`。
- `packages/lore_editor`。
- `packages/lore_ui`。
- `contracts` 基础目录。
- 根级 Dart Pub Workspace 和统一说明。

后端目录在开始设计同步 API 时再创建实际 Rust workspace。

