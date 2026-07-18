import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  test('parses and joins portable relative paths', () {
    final body = LogicalPath.parse('长夜行/正文');

    expect(body.name, '正文');
    expect(body.parent, LogicalPath.parse('长夜行'));
    expect(body.child('第一章.md').value, '长夜行/正文/第一章.md');
    expect(body.contains(body.child('第一章.md')), isTrue);
  });

  test('represents the library root explicitly', () {
    expect(LogicalPath.parse(''), LogicalPath.root);
    expect(LogicalPath.root.child('小说').value, '小说');
  });

  test('rejects absolute, traversal and platform-specific paths', () {
    for (final value in [
      '/tmp/book',
      '../book',
      'book/../chapter',
      r'book\chapter',
    ]) {
      expect(() => LogicalPath.parse(value), throwsFormatException);
    }
  });
}
