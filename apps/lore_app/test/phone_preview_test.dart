import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/phone_preview/phone_device.dart';
import 'package:lore_app/features/workspace/phone_preview/phone_device_frame.dart';

void main() {
  group('PhoneDevice 预设', () {
    test('预设非空且含常用机型', () {
      final names = PhoneDevice.presets.map((d) => d.name).toList();
      expect(
        names,
        containsAll(['iPhone SE', 'iPhone 15', 'iPhone 15 Pro Max']),
      );
      expect(PhoneDevice.presets.length, greaterThanOrEqualTo(4));
    });

    test('宽高比由逻辑分辨率派生', () {
      const device = PhoneDevice(name: 'iPhone 15', width: 390, height: 844);
      expect(device.aspectRatio, closeTo(390 / 844, 1e-9));
    });

    test('每个预设均为正且为竖屏比例（高 > 宽）', () {
      for (final device in PhoneDevice.presets) {
        expect(device.width, greaterThan(0));
        expect(device.height, greaterThan(0));
        expect(device.height, greaterThan(device.width), reason: device.name);
      }
    });
  });

  group('PhoneFrameStyle', () {
    test('四个外形，标签唯一且为预期值', () {
      expect(PhoneFrameStyle.values.length, 4);
      final labels = PhoneFrameStyle.values.map((f) => f.label).toSet();
      expect(labels.length, 4);
      expect(labels, containsAll(['直屏', '刘海', '灵动岛', '挖孔']));
    });
  });

  // 各外形的外框都按设备逻辑尺寸渲染，再用 FittedBox 缩放进测试视口，
  // 断言不产生溢出异常——与面板内真实用法（Center + FittedBox）同口径。
  testWidgets('PhoneDeviceFrame 各外形均无溢出地渲染', (tester) async {
    const device = PhoneDevice(name: 'iPhone 15', width: 390, height: 844);
    for (final style in PhoneFrameStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 600,
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: PhoneDeviceFrame(
                  device: device,
                  frameStyle: style,
                  child: const ColoredBox(
                    color: Colors.white,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: style.name);
      expect(find.byType(PhoneDeviceFrame), findsOneWidget);
    }
  });
}
