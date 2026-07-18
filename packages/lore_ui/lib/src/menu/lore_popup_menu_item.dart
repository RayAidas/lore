import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'lore_menu_metrics.dart';

final class LorePopupMenuItem<T> extends PopupMenuItem<T> {
  LorePopupMenuItem({
    required this.label,
    super.value,
    super.enabled,
    this.destructive = false,
    super.key,
  }) : super(
         height: LoreMenuMetrics.itemHeight(defaultTargetPlatform),
         child: const SizedBox.shrink(),
       );

  final String label;
  final bool destructive;

  @override
  PopupMenuItemState<T, LorePopupMenuItem<T>> createState() =>
      _LorePopupMenuItemState<T>();
}

final class _LorePopupMenuItemState<T>
    extends PopupMenuItemState<T, LorePopupMenuItem<T>> {
  @override
  Widget buildChild() {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      widget.label,
      style: widget.enabled && widget.destructive
          ? TextStyle(color: colorScheme.error)
          : null,
    );
  }
}
