/// 手机预览的屏幕外形（顶边开孔形态）。
enum PhoneFrameStyle {
  /// 直屏：顶边无开孔。
  flat('直屏'),

  /// 刘海：顶部中央下凹刘海。
  notch('刘海'),

  /// 灵动岛：顶部中央悬浮药丸形岛屿。
  dynamicIsland('灵动岛'),

  /// 挖孔：顶部中央单孔前摄。
  punchHole('挖孔');

  const PhoneFrameStyle(this.label);

  /// 下拉项与标签展示用的人话名称。
  final String label;
}

/// 预览设备：逻辑分辨率（dp）+ 显示名。
///
/// 预览按设备逻辑尺寸（[width] × [height]）渲染屏幕内容，再由外层 [FittedBox]
/// 等比缩放进预览面板，使不同机型的相对比例真实还原。
final class PhoneDevice {
  const PhoneDevice({
    required this.name,
    required this.width,
    required this.height,
  });

  /// 机型简称（下拉项展示）。
  final String name;

  /// 逻辑宽度（dp）。
  final double width;

  /// 逻辑高度（dp）。
  final double height;

  /// 宽高比。
  double get aspectRatio => width / height;

  /// 常用预设机型（逻辑分辨率，dp）。增删机型在此一处即可。
  static const List<PhoneDevice> presets = [
    PhoneDevice(name: 'iPhone SE', width: 375, height: 667),
    PhoneDevice(name: 'iPhone 15', width: 390, height: 844),
    PhoneDevice(name: 'iPhone 15 Pro Max', width: 430, height: 932),
    PhoneDevice(name: 'Pixel 7', width: 412, height: 915),
    PhoneDevice(name: 'Galaxy S22', width: 360, height: 800),
  ];
}
