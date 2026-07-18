# ADR 0002：采用可移植书库存储会话

- 状态：已接受
- 日期：2026-07-18

## 背景

macOS 书库可以使用普通目录路径，Android 则通过 SAF 文档树访问。若应用层依赖绝对路径、`dart:io` 或 `content://`，相同的小说、正文和回收站规则会形成两套实现，也无法稳定测试。

## 决策

- Domain 使用 POSIX 格式的 `LogicalPath`，拒绝绝对路径、反斜杠和 `..`。
- Application 定义 `LibraryStorageFactory` 与 `LibraryStorageSession`，暴露能力、目录项、CAS 替换和变更流。
- `lore_storage` 保持纯 Dart，提供本地目录会话、可移植语义仓储和 schema 迁移。
- `lore_platform_adapters` 承载 macOS 文件协调、Android MethodChannel/SAF 与 SharedPreferences。
- schema v2 为书库和小说清单增加 `revision`；v1 升级先备份元数据，再写入并验证，失败时恢复。
- SAF 不声明持续监听能力；应用回到前台时重载小说结构并复检打开文档。
- 平台授权句柄只保存在设备本地，不写入可移植书库元数据。

## 结果

业务模型不再假设绝对文件路径，Android 与本地目录共享存储契约、冲突语义和迁移测试。macOS 现有语义仓储在恢复能力完全迁入可移植实现前继续作为兼容实现；所有新增跨平台行为必须先落在通用存储契约上。

源码文件默认限制为 500 行。现存六个工作区/存储大文件被显式登记为待拆分债务，不能继续扩大白名单。
