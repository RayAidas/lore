# 历史版本设计

> 文档状态：spec 待评审  
> 依赖文档：[书库存储详细设计](library-storage-design.md)、[界面与交互设计](interface-design.md)

## 设计目标

- 用户随时回看任一文档的过往内容，找回误删或误改的段落。
- 自动留档无需用户干预，手动版本可命名备注标记里程碑。
- 任意两个版本之间可 diff 对比。
- 历史随书库走（位于 `.lore/history/`），备份迁移不丢失。
- 故障安全优先：任何单条快照损坏不影响其他版本的可读性。

## 范围与非目标

首轮实现：

- 章节正文与小说目录内的 txt/md 文档历史。
- 自动 checkpoint + 变更量阈值触发，哈希去重。
- 分层时间窗保留 + 硬上限兜底 + 手动版本永久保留。
- 恢复（覆盖当前并自动留底）、复制内容。
- 段落块 + 字级 diff，响应式（桌面并排 / 窄屏内联）。

非目标（留待后续）：

- 增量 patch 存储（首轮用全量 gzip，详见「存储格式」）。
- 跨文档 / 全书库的时间线视图。
- 图片等二进制附件历史。
- 远程 / 云端历史同步。

## 数据模型（lore_domain）

无外部依赖的值对象。

```dart
/// 触发快照的原因。
enum HistoryTrigger {
  autoCheckpoint,     // 切换/关闭文档时
  autoThreshold,      // 变更量达到阈值
  manual,             // 用户主动创建
  restoreSafeguard,   // 恢复前为当前内容自动留底
}

/// 文档身份：章节用 nodeId，普通文件退化为路径哈希。
/// 移动后：章节历史不断链（nodeId 不变），普通文件会断链（已知限制）。
final class DocumentIdentity {
  const DocumentIdentity({this.nodeId, required this.relativePath, required this.format});
  final String? nodeId;            // 章节节点 ID；普通文件为 null
  final String relativePath;       // 相对书库的标准化路径
  final DocumentFormat format;

  /// 历史目录键。章节用 node: 前缀，普通文件用 path: 前缀 + 路径哈希。
  String get historyKey => nodeId != null
      ? 'node:$nodeId'
      : 'path:${_sha1(relativePath)}';
}

final class HistorySnapshot {
  const HistorySnapshot({
    required this.id,
    required this.createdAt,
    required this.trigger,
    required this.contentHash,
    required this.characterCount,
    required this.protected_,    // 手动版本 true，不参与自动 GC
    this.label,                  // 手动命名，如「交稿前」
    this.note,                   // 手动备注
  });
  final String id;
  final DateTime createdAt;
  final HistoryTrigger trigger;
  final String contentHash;      // sha256，用于去重与 diff 标识
  final int characterCount;      // 该版本正文字数
  final bool protected_;
  final String? label;
  final String? note;
}
```

`_sha1` / `sha256` 在 lore_storage 层用 `crypto` 包计算；domain 只持有字符串结果，保持零依赖。

## 存储设计

### 目录结构

完全沿用 [书库存储详细设计](library-storage-design.md#历史版本) 预留的结构：

```text
.lore/history/
└── 898f5aeb-166b-4aaf-bd97-bf7f2b56d15a/   # historyKey 去掉前缀后的目录名
    ├── manifest.json
    └── snapshots/
        ├── 2026-07-22T14-30-00Z_a1b2.txt.gz
        └── 2026-07-22T22-10-00Z_c3d4.txt.gz
```

历史目录以 `historyKey` 命名：章节直接用 nodeId（无 `node:` 前缀），普通文件用路径哈希（无 `path:` 前缀，但 manifest 内记录完整 key 以便区分）。

### manifest.json

```json
{
  "schemaVersion": 1,
  "historyKey": "node:898f5aeb-166b-4aaf-bd97-bf7f2b56d15a",
  "relativePath": "正文/第一卷/第1章.md",
  "format": "markdown",
  "nodeId": "898f5aeb-166b-4aaf-bd97-bf7f2b56d15a",
  "snapshots": [
    {
      "id": "a1b2c3",
      "createdAt": "2026-07-22T14:30:00Z",
      "trigger": "autoCheckpoint",
      "contentHash": "sha256:9f86...",
      "characterCount": 4123,
      "byteSize": 4321,
      "protected": false,
      "file": "snapshots/2026-07-22T14-30-00Z_a1b2.txt.gz"
    },
    {
      "id": "c3d4e5",
      "createdAt": "2026-07-22T22:10:00Z",
      "trigger": "manual",
      "contentHash": "sha256:a1b2...",
      "characterCount": 4250,
      "byteSize": 4400,
      "protected": true,
      "label": "交稿前",
      "note": "改完第三章伏笔",
      "file": "snapshots/2026-07-22T22-10-00Z_c3d4.txt.gz"
    }
  ]
}
```

约束：

- 单文档一份 manifest，写回采用与 trash 一致的 `_writeNewJson` / `_replaceJson` 安全替换。
- 快照文件名 `ISO8601_短哈希.txt.gz`，时间戳前缀保证字典序即时间序，哈希后缀避免同秒冲突。
- manifest 损坏时，按 snapshots 目录扫描重建（复用 trash 的 reconcile 套路）；快照文件单独损坏只影响该条，其他条目仍可列举与恢复。

### 存储格式：全量 gzip（非增量）

- 每条快照独立完整保存文本 + gzip 压缩。
- 单条约 3.5–4.5 KB（4000 字章节），稳态单文档 ~50 条 ≈ 200 KB，一部百章小说 ~25 MB，可忽略。
- 选全量的核心理由是**可靠性**：增量 patch 链任一环损坏即断链，而历史功能的价值恰在「出事时能找回」，方向上不能牺牲可靠性换空间；gzip 对相似文本的压缩已吃掉增量大部分空间收益。
- 未来若出现超大文档（MB 级）且快照密集，可按「文档大小」策略分流再引入增量。

## 触发与过滤策略

### 触发器

| 触发器 | 时机 | 实现 |
|---|---|---|
| autoCheckpoint | 切换活动文档 / 关闭文档标签时 | workspace_controller 在文档失活时调用 |
| autoThreshold | 自上次快照后净变更量 ≥ 800 字 | 编辑器持续统计，达阈值即调用 |
| manual | 用户在历史面板点「创建版本」 | 带命名 / 备注 |
| restoreSafeguard | 恢复某版本前，为当前内容自动留底 | restore 流程内部调用 |

autoCheckpoint 与 autoThreshold 取先到者；二者都受哈希去重约束。

### 过滤器：哈希去重

任何触发在落盘前：

1. 计算 `sha256(text)`。
2. 若等于该文档 manifest 中最近一条快照的 `contentHash`，跳过（返回既有快照）。
3. 否则写入新快照。

这保证「保存了但没改」「切走又切回」不产生垃圾，是数量控制的第一道闸门。

## 保留策略与回收

### 分层时间窗（自动快照）

| 距今 | 保留 |
|---|---|
| 1 小时内 | 全留 |
| 1–24 小时 | 每小时保留最新 1 条 |
| 1–7 天 | 每天保留最新 1 条 |
| 7–30 天 | 每周保留最新 1 条 |
| 30 天以上 | 每月保留最新 1 条，其余淘汰 |

合并按「桶内保留最新」实现：遍历自动快照按时间窗分桶，每桶仅留 `createdAt` 最大者（1 小时桶例外，全留）。

### 硬上限

单文档自动快照 > 100 条时，淘汰最老的至 100。防御性兜底，正常不触发。

### 手动版本

`protected = true` 的快照**不参与**分层合并与硬上限，永久保留；仅用户显式删除时移除。

### GC 触发时机

- 打开历史面板列举前。
- 写入新自动快照后异步触发一次。

GC 只删除自动快照及其 gzip 文件，不动 manifest 中受保护条目。

## 恢复流程

恢复走「覆盖当前 + 自动留底」，由应用层 HistoryService 协调：

1. 读当前磁盘内容（`DocumentRepository.readDocument`）。
2. 若当前内容哈希 ≠ 目标快照哈希，先 `record(trigger: restoreSafeguard)` 为当前留底。
3. 用目标快照文本 `DocumentRepository.saveDocument` 覆盖（带 revision 乐观锁；冲突则提示）。
4. 刷新编辑器缓冲，广播文档变更。

留底快照标记 `restoreSafeguard`，受保护、可在历史列表中识别。

## 端口与实现（跨包职责）

### lore_application：端口

```dart
abstract interface class HistoryRepository {
  Future<List<HistorySnapshot>> list(LibraryAccess access, DocumentIdentity doc);

  /// 写入快照（内部做哈希去重）。返回实际生效的快照（可能复用最近一条）。
  Future<HistorySnapshot> record(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String text,
    required HistoryTrigger trigger,
    String? label,
    String? note,
  });

  Future<String> readSnapshotText(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  });

  Future<void> deleteSnapshot(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  });

  /// 执行分层时间窗 + 硬上限回收。
  Future<void> prune(LibraryAccess access, DocumentIdentity doc);
}
```

`HistoryService`（应用层用例）封装：自动触发判定（变更量计数）、恢复协调（留底 + 覆盖）、GC 调度。

### lore_storage：实现

新增 mixin，完全参照 `_StorageBackedTrashSupport` / `_StorageBackedTrashRepository` 的形态挂在 `storage_backed_library_repository.dart` 下：

- `_StorageBackedHistorySupport`：`_historyRoot`、`_historyManifest`、gzip 读写、manifest JSON 编解码、孤儿快照 reconcile。
- `_StorageBackedHistoryRepository`：实现 `HistoryRepository`。

全程走 `LibraryStorageSession`（不碰 `dart:io`），macOS 与 Android SAF 通用。

### 文档身份解析

- 章节文档：workspace_controller 在打开 / 保存章节时已持有 `ContentNode`，直接取 `nodeId` 构造 `DocumentIdentity`。
- 普通文件：无 nodeId，`DocumentIdentity.historyKey` 退化为 `path:<sha1>`；路径变化即断链（已知限制，UI 可在列表中标注「文件已移动，历史可能无法关联」）。

## UI 设计

### 入口与形态

- Panel 形态（`showLorePanelSheet`），`maxWidth: 960`，以当前活动文档为上下文。
- 入口：inspector「信息」tab 内「查看历史版本」；文件树右键文档「历史版本」。
- 无活动文档时显示空态（复用 `InspectorEmpty` 模式）。

### 版本选择交互

- 列表顶部固定 `● 当前（磁盘）` 锚点行，代表磁盘内容。
- 列表项支持选中：
  - **选 1 条** → 与「当前」diff（默认场景）。
  - **选 2 条** → 两条互相 diff。
- 顶部摘要条显示当前对比：`07-21 22:10「交稿前」 → 当前`。

### 列表项

勾选圆点 · 时间 · 触发类型图标（自动 / 手动命名 / 恢复留底）· 命名备注 · 字数变化（与上一条相比 `+X / −Y`）。

### Diff 粒度与呈现

- **粒度**：段落分块 + 块内字级高亮。
  - 按段落（双换行 / 标题行）切块，判定每块：未变 / 新增 / 删除 / 修改。
  - 修改块内用 `diff_match_patch` 做字符级 diff：删除字红底删除线，新增字绿底，未变字正常。
  - 未变段落默认折叠，仅展示改动上下文。
- **布局（响应式）**：
  - 桌面宽屏：并排 split（左旧右新，同步滚动）。
  - 窄屏（Android 手机 / 平板竖屏）：unified 内联（删除块在上、新增块在下）。
  - 按宽度断点自动切换，复用项目已有响应式能力。

### 导航与操作

- 顶部摘要：`+128 字  −45 字  · 6 段改动`，附「上一处 / 下一处改动」跳转。
- 底部操作栏：`复制内容`、`恢复此版本`（恢复走留底 + 覆盖，二次确认）。
- 手动创建：面板顶部「创建版本」按钮 → 弹命名 / 备注输入。

### 新增依赖

`diff_match_patch`（pub.dev，纯 Dart），用于字符级 diff 计算。段落分块与渲染逻辑自写。

## 跨平台与安全约束

- 历史目录与快照均位于书库 `.lore/history/`，属权威内容，随书库备份迁移。
- 所有路径操作走 `LogicalPath` 规范化与作用域校验，禁止逃逸。
- Android SAF 走 `LibraryStorageSession` 抽象，不假设 POSIX 路径。
- 不记录正文到日志；manifest 与日志仅含 ID、相对路径、哈希。

## 测试策略

- **lore_domain**：`DocumentIdentity.historyKey` 规则、快照值对象相等性。
- **lore_storage**（重点）：
  - manifest 读写、gzip 快照往返一致。
  - 哈希去重（相同内容不新增）。
  - 分层时间窗合并（构造跨时段快照集合，断言每桶保留最新）。
  - 硬上限淘汰。
  - 受保护快照不被 GC。
  - manifest 损坏 / 孤儿快照 reconcile。
  - 文档移动后章节历史不断链（nodeId 不变）。
- **lore_application**：`HistoryService` 恢复协调（留底顺序、saveDocument 冲突）、变更量阈值判定。
- **lore_app**（widget）：历史面板空 / 列表 / 多选切换 diff 对象、响应式布局断点、恢复二次确认。

## 实现阶段拆分

1. **domain 值对象 + application 端口**：`HistorySnapshot` / `DocumentIdentity` / `HistoryTrigger` / `HistoryRepository` 接口。配套 domain 单测。
2. **storage 实现**：mixin + gzip manifest + 哈希去重 + 基础 list/record/read/delete。配套 storage 单测（不含 GC）。
3. **保留策略 GC**：分层时间窗 + 硬上限 + 受保护豁免。配套 GC 单测。
4. **application HistoryService**：恢复协调 + 变更量阈值 + GC 调度。
5. **接入 workspace**：在文档失活 / 保存后调用 record；构造 `DocumentIdentity`。
6. **历史面板 UI**：列表 + 多选 + 创建版本 + 恢复流程。
7. **diff 视图**：引入 `diff_match_patch`，段落块 + 字级渲染，响应式 split / unified，折叠与跳转。
8. **收尾**：`./scripts/test.sh` 全绿、dart format、接入入口（inspector / 文件树右键）、更新 `library-storage-design.md` 的「当前实现状态」。

每阶段独立可测，阶段 6 之前即可拿到一个能自动留档 + 恢复的最小闭环。

## UI 形态修订（实现版）

实现阶段将 UI 从初稿的「modal 面板 + 右侧面板内 diff」调整为 VSCode 式：

- **入口**：右侧工具栏新增「版本」tab（与 助手/大纲/信息 平级），常驻列出当前活动文档的历史快照；移除原「信息」tab 的入口按钮与 modal 面板（`history_pane.dart`）。
- **diff 位置**：点列表项 → 中间编辑器区**替换为 diff 视图**（替换 `DocumentPane` 内容区，非独立 tab、非 modal），对比「该快照 vs 当前磁盘」。工具条显示标题 + 内联/并排 toggle + 退出。
- **对比语义**：只与当前磁盘对比（取消任意两版互比）。
- **diff 呈现**：**默认内联**（单视图字符级着色，红删绿增）；并排仅宽屏且手动切换时可用。内联为默认是因为中文连续散文 + 长段落下并排折行易错位、写作修改以局部为主、且双端含窄屏。
- **操作**：版本列表项内联恢复/删除；顶部创建版本。恢复后自动退出 diff（内容已变，重新进编辑器）。
- **状态**：`WorkspaceController` 持有 `diffTarget`（快照文本 + 标题）与 `diffMode`（默认 inline）；`isDiffing` 控制 `DocumentPane` 是否渲染 diff 分支。
