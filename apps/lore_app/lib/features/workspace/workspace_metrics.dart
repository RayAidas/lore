/// 工作区底部"chrome 条"的统一高度：左侧栏的路径/回收站 footer 与文档状态栏
/// 共用同一高度并对齐顶边，构成贯穿编辑区的视觉底栏。
///
/// 公开供布局与测试共享同一处常量——两侧高度一旦各自漂移，顶边对齐就会破坏，
/// 测试（校验 footer 与 status-bar 高度一致且顶边坐标误差 ≤1px）也会随之失效。
const double workspaceChromeBarHeight = 34;
