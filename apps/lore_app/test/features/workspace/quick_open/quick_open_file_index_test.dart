import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/quick_open/quick_open_file_index.dart';
import 'package:lore_domain/lore_domain.dart';

void main() {
  group('displayName', () {
    test('textFile 去掉 .txt 后缀', () {
      final entry = LibraryEntry(
        name: '第1章 初出茅庐.txt',
        relativePath: '卷一/第1章 初出茅庐.txt',
        type: LibraryEntryType.textFile,
      );
      expect(displayName(entry), '第1章 初出茅庐');
    });

    test('textFile 大小写不敏感去 .TXT', () {
      final entry = LibraryEntry(
        name: 'notes.TXT',
        relativePath: 'notes.TXT',
        type: LibraryEntryType.textFile,
      );
      expect(displayName(entry), 'notes');
    });

    test('纯 .txt 名原样返回(不剥成空串)', () {
      final entry = LibraryEntry(
        name: '.txt',
        relativePath: '.txt',
        type: LibraryEntryType.textFile,
      );
      expect(displayName(entry), '.txt');
    });

    test('markdownFile 保留全名(含 .md)', () {
      final entry = LibraryEntry(
        name: '大纲.md',
        relativePath: '大纲.md',
        type: LibraryEntryType.markdownFile,
      );
      expect(displayName(entry), '大纲.md');
    });
  });
}
