export 'src/annotation/annotation_spans.dart';
export 'src/annotation/grid_line_painter.dart';
export 'src/annotation/text_annotation.dart';
export 'src/editor_style.dart';
export 'src/editor_typography.dart';

/// [EditorStyle.gridLineMode] 的类型来自领域层，随编辑器样式一并暴露，
/// 使消费者构造 [EditorStyle] 时无需单独 import lore_domain。
export 'package:lore_domain/lore_domain.dart' show GridLineMode;
export 'src/find_replace/find_replace_controller.dart';
export 'src/find_replace/find_replace_overlay.dart';
export 'src/find_replace/search_query.dart';
export 'src/large_text/chunked_text_buffer.dart';
export 'src/large_text/lore_large_text_controller.dart';
export 'src/large_text/lore_large_text_editor.dart';
export 'src/large_text/pasted_text_normalizer.dart';
export 'src/lore_markdown_preview.dart';
export 'src/lore_text_controller.dart';
export 'src/lore_text_editor.dart';
export 'src/document_controller.dart';
