import 'dart:async';

import 'package:flutter/material.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

/// Live document heading outline panel wired to a [MarkdownController].
///
/// Clicking any heading invokes [MarkdownController.scrollToAnchor] for its
/// resolved slug.
final class StudioOutlinePanel extends StatelessWidget {
  /// Creates a [StudioOutlinePanel].
  const StudioOutlinePanel({
    super.key,
    required this.controller,
    required this.onJumpToHeading,
    this.onClose,
  });

  /// Active Markdown controller supplying `outline` and `readingPlace`.
  final MarkdownController controller;

  /// Callback invoked after jumping to a selected [MarkdownOutlineItem].
  final ValueChanged<MarkdownOutlineItem> onJumpToHeading;

  /// Optional close callback shown when rendered inside a drawer or sidebar.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final List<MarkdownOutlineItem> outline = controller.outline;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.toc_rounded, size: 16.0, color: scheme.primary),
                  const SizedBox(width: 6.0),
                  Expanded(
                    child: Text(
                      'Outline (${outline.length})',
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      onPressed: onClose,
                      tooltip: 'Hide Outline',
                      icon: const Icon(Icons.close, size: 16.0),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 26.0,
                        minHeight: 26.0,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            if (outline.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'No headings in document',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ValueListenableBuilder<MarkdownReadingPlace>(
                  valueListenable: controller.readingPlaceNotifier,
                  builder:
                      (
                        BuildContext context,
                        MarkdownReadingPlace place,
                        Widget? child,
                      ) {
                        final List<MarkdownBlockNode> blocks =
                            controller.document.blocks;
                        final int activeBlockIndex = place.blockIndex;
                        final int activeLine =
                            activeBlockIndex >= 0 &&
                                activeBlockIndex < blocks.length
                            ? blocks[activeBlockIndex].span.startLine
                            : 0;
                        int activeOutlineIndex = -1;
                        if (activeLine > 0) {
                          for (int i = 0; i < outline.length; i++) {
                            if (outline[i].line <= activeLine) {
                              activeOutlineIndex = i;
                            } else {
                              break;
                            }
                          }
                        }

                        return ListView.builder(
                          key: const Key('studio-outline-list'),
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          itemCount: outline.length,
                          itemBuilder: (BuildContext context, int index) {
                            final MarkdownOutlineItem item = outline[index];
                            final bool isActive = index == activeOutlineIndex;
                            final double indent =
                                ((item.level - 1).clamp(0, 5)) * 10.0;

                            return InkWell(
                              key: ValueKey<String>(
                                'outline-item-${item.slug}-$index',
                              ),
                              onTap: () {
                                unawaited(controller.scrollToAnchor(item.slug));
                                onJumpToHeading(item);
                              },
                              child: Container(
                                padding: EdgeInsets.fromLTRB(
                                  10.0 + indent,
                                  6.0,
                                  10.0,
                                  6.0,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? scheme.primaryContainer.withValues(
                                          alpha: 0.45,
                                        )
                                      : null,
                                  border: Border(
                                    left: BorderSide(
                                      width: 2.5,
                                      color: isActive
                                          ? scheme.primary
                                          : Colors.transparent,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4.5,
                                        vertical: 1.0,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(
                                          4.0,
                                        ),
                                      ),
                                      child: Text(
                                        'H${item.level}',
                                        style: TextStyle(
                                          fontSize: 10.0,
                                          fontWeight: FontWeight.w700,
                                          color: scheme.primary,
                                          fontFamily: 'SF Mono',
                                          fontFamilyFallback: MarkdownThemeData
                                              .defaultCodeFontFallback,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6.0),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            item.text,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: item.level <= 2
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: scheme.onSurface,
                                            ),
                                          ),
                                          Text(
                                            '#${item.slug} · L${item.line}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: scheme.onSurfaceVariant,
                                              fontFamily: 'SF Mono',
                                              fontFamilyFallback:
                                                  MarkdownThemeData
                                                      .defaultCodeFontFallback,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                ),
              ),
          ],
        );
      },
    );
  }
}
