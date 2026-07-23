import 'package:flutter/material.dart';
import 'package:lore_editor/lore_editor.dart';

/// 一段会渲染为一行或多行文本的内容片。[newParagraph] 为 true 表示这是一个新
/// 段落的起始（渲染时在其前加段间距）；false 表示它是同段落被分页截断后的续接
/// （不加间距，文本是段中片段，故也无段首缩进）。
final class PhonePreviewPageSegment {
  const PhonePreviewPageSegment({
    required this.text,
    required this.newParagraph,
  });

  final String text;
  final bool newParagraph;
}

/// 一页：按序渲染的若干文本段。
final class PhonePreviewPage {
  const PhonePreviewPage({required this.segments});

  final List<PhonePreviewPageSegment> segments;
}

/// 把章节正文按「一页能容纳的行数」切成多页：用 [TextPainter] 逐段测量，行级
/// 断页（长段落可跨页）。纯逻辑（文本 + 页面盒子 + 样式 → 页列表），便于单测。
///
/// 第 1 页通常要扣除章节标题的高度，故 [firstPageHeight] 与 [pageHeight] 分开。
/// 段首缩进由 [paragraphIndent] 提供（如两个全角空格），仅在段落起始处生效；
/// 续接片段是段中子串，天然不带缩进。
final class PhonePreviewPaginator {
  PhonePreviewPaginator({
    required this.boxWidth,
    required this.pageHeight,
    required this.firstPageHeight,
    required this.style,
    required this.paragraphGap,
    this.paragraphIndent = '',
    this.textDirection = TextDirection.ltr,
  }) : assert(boxWidth > 0),
       assert(pageHeight > 0),
       assert(firstPageHeight >= 0);

  /// 单页正文可用宽度（逻辑像素）。
  final double boxWidth;

  /// 第 2 页及之后每页可用正文高度。
  final double pageHeight;

  /// 第 1 页可用正文高度（已扣除标题区）。
  final double firstPageHeight;

  /// 正文文本样式（字号 / 行高 / 字体）。
  final TextStyle style;

  /// 段间距（像素）。
  final double paragraphGap;

  /// 段首缩进串（如两个全角空格）；空串表示不缩进。
  final String paragraphIndent;

  final TextDirection textDirection;

  /// 浮点容差：TextPainter 测量与渲染之间可能有亚像素差，留 0.5px 余量。
  static const double _eps = 0.5;

  /// 把段落列表分页。返回的页按顺序覆盖全部输入文本（无丢失 / 重复）。
  List<PhonePreviewPage> paginate(List<String> paragraphs) {
    final pages = <PhonePreviewPage>[];
    var current = <PhonePreviewPageSegment>[];
    var remaining = firstPageHeight;
    var firstOnPage = true;

    final painter = TextPainter(textDirection: textDirection);

    void flush() {
      if (current.isNotEmpty) {
        pages.add(PhonePreviewPage(segments: List.of(current)));
      }
      current = <PhonePreviewPageSegment>[];
      remaining = pageHeight;
      firstOnPage = true;
    }

    for (final raw in paragraphs) {
      // 跳过空 / 纯空白段（与 LoreReadingFlowPreview.splitParagraphs 同口径，
      // 即便调用方未预先清洗也不产生空白页）。
      if (raw.trim().isEmpty) continue;
      // 段首缩进复用阅读流的同一份逻辑（ensureIndent），保证翻页与滚动两模式
      // 渲染一致。
      final p = LoreReadingFlowPreview.ensureIndent(raw, paragraphIndent);
      var cursor = 0;
      while (cursor < p.length) {
        final sub = p.substring(cursor);
        // 新段落起始、且非页内首段：本段前面要留段间距。
        final willGap = cursor == 0 && !firstOnPage;
        final available = remaining - (willGap ? paragraphGap : 0);
        if (available <= 0) {
          flush();
          continue; // 新页重试本段。
        }
        final wholeHeight = _layout(painter, sub);
        if (wholeHeight <= available + _eps) {
          // 整段剩余都放得下。
          current.add(
            PhonePreviewPageSegment(text: sub, newParagraph: cursor == 0),
          );
          remaining -= wholeHeight + (willGap ? paragraphGap : 0);
          firstOnPage = false;
          cursor = p.length;
          break;
        }
        // 放不下：二分找最多能放下的字符数（高度随字数单调不减，故落在行末）。
        var lo = 1;
        var hi = sub.length;
        var best = 0;
        var bestHeight = 0.0;
        while (lo <= hi) {
          final mid = (lo + hi) ~/ 2;
          final h = _layout(painter, sub.substring(0, mid));
          if (h <= available + _eps) {
            best = mid;
            bestHeight = h;
            lo = mid + 1;
          } else {
            hi = mid - 1;
          }
        }
        if (best == 0) {
          // 连一行都放不下。
          if (current.isEmpty) {
            // 空页：强制放首行，避免空页 / 死循环（轻微溢出可接受）。
            best = _firstLineCharCount(painter, sub);
            if (best <= 0) best = 1;
            bestHeight = _layout(painter, sub.substring(0, best));
            current.add(
              PhonePreviewPageSegment(
                text: sub.substring(0, best),
                newParagraph: cursor == 0,
              ),
            );
            remaining -= bestHeight;
            firstOnPage = false;
            cursor += best;
          } else {
            flush();
            continue;
          }
        } else {
          current.add(
            PhonePreviewPageSegment(
              text: sub.substring(0, best),
              newParagraph: cursor == 0,
            ),
          );
          remaining -= bestHeight + (willGap ? paragraphGap : 0);
          firstOnPage = false;
          cursor += best;
        }
      }
    }
    flush();
    painter.dispose();
    return pages;
  }

  double _layout(TextPainter painter, String text) {
    painter.text = TextSpan(text: text, style: style);
    painter.layout(maxWidth: boxWidth);
    return painter.height;
  }

  /// 在已 layout 完整 [text] 的 painter 上取首行末字符偏移（首行能放多少字）。
  /// 用于「连一行都放不下」时强制放首行，保证进度。
  int _firstLineCharCount(TextPainter painter, String text) {
    painter.text = TextSpan(text: text, style: style);
    painter.layout(maxWidth: boxWidth);
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return text.length;
    final pos = painter.getPositionForOffset(
      Offset(boxWidth, lines.first.baseline),
    );
    return pos.offset > 0 ? pos.offset : 1;
  }
}
