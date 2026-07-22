# Lore 设计文档

本目录存放 Lore 的产品与功能设计文档。文档按领域拆分，避免单篇文档同时承担产品定位、交互、数据和实施计划等职责。

## 文档导航

| 文档 | 内容 |
| --- | --- |
| [产品总览](product-overview.md) | 产品定位、目标用户、设计原则和核心术语 |
| [书库与内容模型](library-and-content-model.md) | 单书库、小说目录、正文、卷章规则和元数据 |
| [书库存储详细设计](library-storage-design.md) | JSON 结构、稳定 ID、保存事务、恢复和本地索引 |
| [技术架构](technical-architecture.md) | Flutter 分层、模块、平台存储、后台任务和测试策略 |
| [Monorepo 架构](monorepo-architecture.md) | Flutter workspace、未来 Axum 服务、契约和依赖边界 |
| [界面与交互](interface-design.md) | macOS、Android、文件树、标签页和概览页面 |
| [编辑与阅读](editor-and-reader.md) | TXT、Markdown、沉浸写作、阅读和审稿体验 |
| [写作数据统计](writing-statistics.md) | 小说级日净增、目标、趋势、连续写作和本地持久化设计 |
| [模板与数据管理](templates-and-data-management.md) | 模板、搜索、保存、历史、导入导出和同步预留 |
| [AI Agent](ai-agent.md) | 后续 AI 的启用方式、上下文、能力和安全边界 |
| [质量与路线图](quality-and-roadmap.md) | 非功能需求、MVP、开发顺序和待细化事项 |

## 文档约定

- 当前内容是产品定义阶段的设计基线，不代表所有细节已经冻结。
- 已确认的产品方向直接写入对应文档；尚未确定的事项集中记录在“待细化事项”中。
- 新设计应放入本目录，并在本索引中增加入口。
- 功能设计发生变化时，应同步更新受影响的领域文档，避免复制出多份定义。
