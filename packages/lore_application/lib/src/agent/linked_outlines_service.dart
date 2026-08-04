import 'package:lore_domain/lore_domain.dart';

import '../ports/linked_outlines_repository.dart';

/// 小说大纲关联的组合用例：读默认 + 落库。
final class LinkedOutlinesService {
  const LinkedOutlinesService({required this.repository});

  final LinkedOutlinesRepository repository;

  Future<NovelOutlineLinks> loadOrDefault() async {
    final loaded = await repository.load();
    return loaded ?? const NovelOutlineLinks.empty();
  }

  Future<void> save(NovelOutlineLinks links) => repository.save(links);
}
