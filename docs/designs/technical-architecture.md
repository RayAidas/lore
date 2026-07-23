# 技术架构设计

> 文档状态：初稿  
> 适用阶段：MVP 及后续演进  
> 客户端技术：Flutter

仓库级目录、Dart package 边界和未来 Rust 服务端结构参见 [Monorepo 架构设计](monorepo-architecture.md)。

## 架构目标

技术架构需要优先满足以下目标：

- macOS 与 Android 共用业务模型和主要界面逻辑。
- 真实文件是用户内容的权威来源，数据库不能取代正文文件。
- 平台文件 API、编辑器和未来同步服务可以替换，不向业务层泄漏实现细节。
- 写作、自动保存和恢复链路保持简单可靠。
- 大型书库索引、统计和 Markdown 解析不阻塞编辑输入。
- AI Agent 后续通过受控应用服务接入，不能直接绕过权限操作文件。

## 总体分层

采用以功能模块为边界、分层依赖为约束的架构。避免建立只有技术分层、所有功能互相引用的全局目录。

```text
Presentation
    ↓
Application
    ↓
Domain
    ↑
Infrastructure / Platform
```

### Presentation

负责 Flutter 界面和交互状态：

- 页面、组件、对话框和导航。
- 文件树展开状态、标签页和当前选择。
- 编辑器视图状态。
- 对应用服务返回结果的展示。
- 加载、错误、冲突和保存状态。

Presentation 不直接读写文件、数据库或平台 Keychain。

### Application

负责组织完整用例和事务边界：

- 创建小说、卷和章。
- 打开、保存、移动、重排和删除文档。
- 导入、导出、建立索引和恢复历史版本。
- 协调正文文件、元数据和缓存更新。
- 产生可供界面处理的冲突、确认和错误结果。

Application 是未来 AI 工具唯一允许调用的业务入口。

### Domain

负责不依赖 Flutter 和平台 API 的核心规则：

- 书库、小说、正文、卷、章和普通文件的模型。
- 卷章识别、排序、编号和命名规则。
- 模板实例化规则。
- 文件操作计划和冲突模型。
- 写作统计和阅读顺序计算。

Domain 对 `dart:io`、SQLite、SAF、Widget 和具体编辑器组件保持无感知。

### Infrastructure

负责技术实现：

- 书库元数据序列化。
- SQLite 搜索索引和本地状态缓存。
- 历史快照与回收站。
- Markdown 解析。
- 文件监听与变更协调。
- 导入和导出实现。

### Platform

负责平台能力适配：

- macOS 本地目录访问和文件监听。
- Android Storage Access Framework（SAF）目录授权。
- macOS Keychain 与 Android Keystore。
- 系统菜单、窗口、快捷键、分享和文件选择器。
- 应用生命周期和后台保存信号。

## 依赖规则

- Domain 不依赖其他层。
- Application 依赖 Domain，并通过接口使用 Infrastructure 和 Platform。
- Infrastructure 实现 Domain 或 Application 定义的端口。
- Presentation 只能通过 Application 用例修改业务状态。
- 功能模块之间通过公开用例、事件或只读模型通信，不直接访问对方内部仓储。

## 应用内功能模块

```text
apps/lore_app/lib/
├── app/
│   ├── bootstrap/
│   ├── routing/
│   └── theme/
├── core/
│   ├── errors/
│   ├── ids/
│   ├── result/
│   └── platform/
├── features/
│   ├── library/
│   ├── novel/
│   ├── explorer/
│   ├── editor/
│   ├── reader/
│   ├── templates/
│   ├── search/
│   ├── history/
│   ├── import_export/
│   ├── settings/
│   └── ai_agent/
└── shared/
    ├── widgets/
    └── shortcuts/
```

这里主要描述应用层的页面和功能组合。可复用的领域、用例、存储、编辑器和 UI 基础能力分别位于 monorepo 的独立 package 中；每个模块内部按需要组织目录，简单模块不必机械建立空目录。

## 状态管理与依赖注入

建议使用 Riverpod，原因包括：

- 同时承担状态管理和依赖注入，减少额外容器。
- 适合表达当前书库、打开文档、保存状态等异步数据。
- Provider 可以覆盖，便于使用内存存储实现测试业务用例。
- 不要求业务模型继承框架基类。

状态按生命周期划分：

| 状态 | 示例 | 保存位置 |
| --- | --- | --- |
| 瞬时界面状态 | 菜单展开、悬停、临时选择 | Widget 或页面 Provider |
| 会话状态 | 打开的标签、当前文件、侧栏宽度 | 应用状态缓存 |
| 可移植业务状态 | 卷章顺序、小说信息 | 书库元数据 |
| 派生状态 | 搜索索引、字数缓存 | 本地 SQLite，可重建 |

不应把整个应用状态放入一个全局可变对象。

## 路由与桌面窗口

- 页面级导航可使用 `go_router`，具体依赖在 Flutter 工程初始化时确认版本。
- 桌面端的文件标签页属于工作区状态，不为每个标签建立系统路由。
- 桌面工作区最多维护左右两个编辑器组；标签归属、组内顺序、各组活动路径、
  焦点组和分隔比例作为设备本地会话状态恢复。
- Android 始终使用单编辑器组；读取桌面双组会话时按左右顺序合并标签。
- MVP 只要求单窗口；多窗口属于后续能力。
- 恢复应用时先恢复书库，再恢复存在且可访问的标签页。

## 存储抽象

macOS 可以使用普通路径和 `dart:io`，Android 书库则可能是 SAF 授权后的 `content://` 文档树。业务层不能统一假设书库拥有绝对文件路径。

建议定义语义化存储接口：

```text
LibraryStorage
├── listChildren(node)
├── readText(node)
├── writeText(node, content)
├── createDirectory(parent, name)
├── createFile(parent, name, content)
├── move(node, target, name)
├── copy(node, target, name)
├── delete(node)
├── stat(node)
└── watch(scope)
```

存储节点使用应用自己的 `StorageRef`，其中保存相对路径、平台句柄和能力信息，但不向 Domain 暴露 URI 或系统路径。

实现至少包括：

- `MacOsDirectoryStorage`：真实目录、原子替换和文件系统监听。
- `AndroidSafStorage`：持久化目录授权、DocumentFile 操作和能力降级。
- `MemoryStorage`：单元测试和业务规则验证。

> 落地时按 ADR-0002 拆包：macOS 本地目录会话在 `lore_storage`（纯 Dart），Android SAF 的 MethodChannel 与 macOS 文件协调在 `lore_platform_adapters`，二者实现同一套可移植存储会话契约。

Android 文档提供者的能力并不一致，移动、重命名和原子替换必须通过能力检测处理，不能假设所有 SAF Provider 行为相同。

## 数据持久化边界

### 书库中的可移植数据

- TXT、Markdown、图片等用户文件。
- 书库和小说的 JSON 元数据。
- 模板文件。
- 历史快照与回收站内容。

这些数据应当随书库整体移动和备份。

### 应用私有目录中的本地数据

- SQLite 搜索索引。
- 最近打开、窗口尺寸和本机标签页状态。
- 文件监听游标和扫描缓存。
- 可重建的字数与 Markdown 解析缓存。
- 平台授予的书库访问句柄。

SQLite 不直接放在 Android SAF 书库中，也不作为跨设备同步对象。

## 数据访问组件

建议按职责拆分仓储：

- `LibraryRepository`：书库清单、版本和扫描状态。
- `NovelRepository`：小说信息和正文目录。
- `ContentTreeRepository`：卷章身份、顺序和路径映射。
- `DocumentRepository`：TXT、Markdown 的读取和保存。
- `TemplateRepository`：模板注册与实例化。
- `HistoryRepository`：快照、比较和恢复。
- `SearchRepository`：索引写入和查询。
- `SettingsRepository`：应用级与小说级设置。

仓储接口表达领域语义，不应成为对任意 SQL 或任意文件路径的薄封装。

## 命令、事件与一致性

修改文件系统的用例采用“计划—执行—提交”流程：

1. 验证名称、权限和目标位置。
2. 生成文件操作计划及可能影响的元数据。
3. 执行可回滚或可恢复的文件操作。
4. 提交权威元数据。
5. 发布领域事件，异步更新索引和统计。

典型领域事件：

```text
NovelCreated
DocumentSaved
ContentMoved
ContentReordered
ContentDeleted
MetadataReconciled
```

搜索索引和统计属于事件的异步消费者。它们更新失败时提示后台状态并允许重建，但不得回滚已经成功保存的正文。

## 编辑器架构

编辑器是高风险组件，应通过适配接口隔离：

```text
EditorController
├── load(document)
├── getText()
├── applyEdit(edit)
├── setSelection(selection)
├── observeChanges()
└── buildSnapshot()
```

正式选择组件前必须完成技术验证，至少测试：

- macOS 中文输入法组合输入。
- Android 主流中文输入法和软键盘。
- 10 万至 50 万字文档的加载、输入和滚动。
- 光标、撤销栈、查找替换和选区行为。
- Markdown 增量高亮而非每次全文重建。
- 自动保存时从编辑缓冲区取得一致快照。

第一阶段优先稳定的纯文本编辑内核。Markdown 高亮和预览建立在文本之上，不把正文转换成私有富文本模型。

## 后台任务

以下任务不得阻塞 UI isolate：

- 初次扫描大型书库。
- 全文搜索索引构建。
- 大文档 Markdown 解析。
- 整书字数重算。
- 大文件导入拆章和整书导出。
- 历史快照压缩与清理。

任务需要支持进度、取消和失败重试。写作保存属于高优先级链路，不应排队等待低优先级索引任务。

## 错误模型

统一使用可区分的应用错误，而不是向界面抛出平台异常文本：

- 权限失效。
- 文件不存在。
- 名称冲突。
- 外部修改冲突。
- 存储空间不足。
- 编码无法识别。
- 元数据损坏。
- 不支持的存储能力。

错误结果应包含可执行的恢复建议，例如重新授权、另存副本、保留两个版本或重建索引。

## 测试策略

### 单元测试

- 卷章识别、排序和重新编号。
- 元数据序列化与版本迁移。
- 文件操作计划和冲突判断。
- 模板变量替换。
- 阅读顺序和字数统计。

### 集成测试

- 使用临时目录验证 macOS 文件操作。
- 使用内存存储验证创建小说到保存章节的完整用例。
- SQLite 索引建立、删除和重建。
- 外部重命名、移动和删除后的元数据协调。

### 平台测试

- Android SAF 授权持久化和权限恢复。
- Android 不同文档提供者的移动、重命名和覆盖行为。
- macOS 文件权限、目录监听和原子替换。
- 两个平台的中文输入法、后台切换和异常恢复。

## 推荐技术验证顺序

在搭建完整业务界面前，按以下顺序制作最小技术验证：

1. macOS 普通目录与 Android SAF 的统一存储接口。
2. JSON 元数据和正文文件的一致性事务。
3. 中文长文本编辑器及自动保存快照。
4. 大型书库后台扫描和 SQLite 全文搜索。
5. Markdown 增量解析与阅读排版。

验证结果可能影响具体依赖选择，但不改变分层和数据权威边界。
