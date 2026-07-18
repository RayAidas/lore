import 'package:flutter/material.dart';
import 'package:lore_domain/lore_domain.dart';

/// [LibraryEntry] 的图标与配色，供侧栏目录树、卷章面板等复用。
extension LibraryEntryIcons on LibraryEntry {
  IconData get entryIcon {
    final semanticIcon = switch (semanticKind) {
      LibraryEntrySemanticKind.novel => Icons.auto_stories_outlined,
      LibraryEntrySemanticKind.body => Icons.menu_book_outlined,
      LibraryEntrySemanticKind.volume => Icons.folder_copy_outlined,
      LibraryEntrySemanticKind.chapter => Icons.article_outlined,
      null => null,
    };
    if (semanticIcon != null) {
      return semanticIcon;
    }
    return switch (type) {
      LibraryEntryType.directory => Icons.folder_outlined,
      LibraryEntryType.textFile => Icons.notes_outlined,
      LibraryEntryType.markdownFile => Icons.description_outlined,
      LibraryEntryType.otherFile => Icons.insert_drive_file_outlined,
    };
  }

  Color entryIconColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (semanticKind) {
      LibraryEntrySemanticKind.novel => colorScheme.primary,
      LibraryEntrySemanticKind.body => colorScheme.tertiary,
      LibraryEntrySemanticKind.volume => colorScheme.secondary,
      LibraryEntrySemanticKind.chapter => colorScheme.primary,
      null => colorScheme.onSurfaceVariant,
    };
  }
}
