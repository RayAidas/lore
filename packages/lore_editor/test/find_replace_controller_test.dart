import 'package:flutter_test/flutter_test.dart';
import 'package:lore_editor/src/find_replace/find_replace_controller.dart';

void main() {
  test('recompute updates matches and clamps currentIndex', () {
    final controller = FindReplaceController();
    controller.setPattern('a');
    controller.recompute('banana');
    expect(controller.matchCount, 3);
    expect(controller.currentIndex, 0);
    controller.next();
    controller.next(); // index 2
    controller.setPattern('na'); // matches at 2,4
    controller.recompute('banana');
    expect(controller.matchCount, 2);
    expect(controller.currentIndex, 0); // clamped from 2
  });

  test('next wraps around at end of matches', () {
    final controller = FindReplaceController()
      ..setPattern('a')
      ..recompute('aba');
    expect(controller.currentIndex, 0);
    controller.next();
    expect(controller.currentIndex, 1);
    controller.next();
    expect(controller.currentIndex, 0);
  });

  test('previous wraps around at start of matches', () {
    final controller = FindReplaceController()
      ..setPattern('a')
      ..recompute('aba');
    controller.previous();
    expect(controller.currentIndex, 1);
  });

  test('applyReplaceCurrent splices replacement into text', () {
    final controller = FindReplaceController()
      ..setPattern('cat')
      ..setReplacement('dog')
      ..recompute('a cat b cat');
    final result = controller.applyReplaceCurrent('a cat b cat');
    expect(result.replaced, isTrue);
    expect(result.text, 'a dog b cat');
    expect(result.cursor, 5);
  });

  test('applyReplaceAll replaces all without offset corruption', () {
    final controller = FindReplaceController()
      ..setPattern('cat')
      ..setReplacement('dog')
      ..recompute('cat cat cat');
    expect(controller.applyReplaceAll('cat cat cat'), 'dog dog dog');
  });

  test('applyReplaceAll leaves text unchanged when no matches', () {
    final controller = FindReplaceController()
      ..setPattern('zzz')
      ..setReplacement('dog')
      ..recompute('cat');
    expect(controller.applyReplaceAll('cat'), 'cat');
  });

  test('regex replacement expands numeric capture groups', () {
    final controller = FindReplaceController()
      ..setPattern(r'(\d+)-(\d+)')
      ..setReplacement(r'$2-$1')
      ..setUseRegex(true)
      ..recompute('12-34');
    expect(controller.applyReplaceAll('12-34'), '34-12');
  });

  test('recomputeAsync stays quiet when disposed before it resolves', () async {
    final controller = FindReplaceController()..setPattern('a');
    var notifications = 0;
    controller.addListener(() => notifications += 1);
    // 启动异步重算后立刻 dispose：返回时既不能写过期数据，更不能 notifyListeners
    // （否则会在已 dispose 的 ChangeNotifier 上抛断言）。
    final done = controller.recomputeAsync('banana');
    controller.dispose();
    await done;
    expect(notifications, 0);
  });
}
