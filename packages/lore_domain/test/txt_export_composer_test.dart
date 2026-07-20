import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  group('TxtExportComposer', () {
    test('emits title, blank line, body per chapter with default options', () {
      final result = TxtExportComposer.compose(
        chapters: const [
          ExportChapter(title: '第1章 起点', body: '起点正文。'),
          ExportChapter(title: '第2章 远行', body: '远行正文。'),
        ],
        options: const TxtExportOptions(),
      );
      expect(
        result,
        '第1章 起点\n\n起点正文。\n\n'
        '第2章 远行\n\n远行正文。\n',
      );
    });

    test('omits titles when includeTitles is false', () {
      final result = TxtExportComposer.compose(
        chapters: const [
          ExportChapter(title: '第1章', body: '正文1'),
          ExportChapter(title: '第2章', body: '正文2'),
        ],
        options: const TxtExportOptions(includeTitles: false),
      );
      expect(result, '正文1\n\n正文2\n');
    });

    test(
      'joins chapters without blank line when blankLineBetween is false',
      () {
        final result = TxtExportComposer.compose(
          chapters: const [
            ExportChapter(title: '第1章', body: '正文1'),
            ExportChapter(title: '第2章', body: '正文2'),
          ],
          options: const TxtExportOptions(blankLineBetween: false),
        );
        expect(result, '第1章\n\n正文1\n第2章\n\n正文2\n');
      },
    );

    test('skips empty chapters', () {
      final result = TxtExportComposer.compose(
        chapters: const [
          ExportChapter(title: '第1章', body: '正文1'),
          ExportChapter(title: '', body: '   '),
          ExportChapter(title: '第3章', body: '正文3'),
        ],
        options: const TxtExportOptions(),
      );
      expect(result, '第1章\n\n正文1\n\n第3章\n\n正文3\n');
    });

    test('returns empty string when all chapters are empty', () {
      final result = TxtExportComposer.compose(
        chapters: const [ExportChapter(title: '', body: '')],
        options: const TxtExportOptions(),
      );
      expect(result, '');
    });
  });
}
