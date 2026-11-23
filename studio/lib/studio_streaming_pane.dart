import 'package:flutter/material.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

/// Left-pane interactive LLM streaming simulator controls and live incremental
/// parse telemetry.
final class StudioStreamingPane extends StatelessWidget {
  /// Creates a [StudioStreamingPane].
  const StudioStreamingPane({
    super.key,
    required this.streamController,
    required this.isPlaying,
    required this.appliedChunkCount,
    required this.totalChunkCount,
    required this.chunkIntervalMs,
    required this.lastChunkParseMicros,
    required this.averageChunkParseMicros,
    required this.lastChunkText,
    required this.onTogglePlayPause,
    required this.onStep,
    required this.onReset,
    required this.onFinish,
    required this.onIntervalChanged,
  });

  /// Incremental streaming controller driving the live document.
  final StreamingMarkdownController streamController;

  /// Whether timed chunk playback is currently running.
  final bool isPlaying;

  /// Number of chunks appended so far.
  final int appliedChunkCount;

  /// Total chunks available in the streaming script.
  final int totalChunkCount;

  /// Delay in milliseconds between streamed chunks during playback.
  final int chunkIntervalMs;

  /// Measured microseconds for the most recent `append` / `finish` call.
  final int lastChunkParseMicros;

  /// Running average microseconds across applied chunks.
  final int averageChunkParseMicros;

  /// Text of the most recently appended chunk, if any.
  final String lastChunkText;

  /// Toggles automatic timed playback between running and paused states.
  final VoidCallback onTogglePlayPause;

  /// Appends the next single chunk.
  final VoidCallback onStep;

  /// Clears all streamed state back to zero chunks.
  final VoidCallback onReset;

  /// Immediately appends remaining chunks and calls `finish()`.
  final VoidCallback onFinish;

  /// Updates the timed playback delay in milliseconds.
  final ValueChanged<int> onIntervalChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int settledCount = streamController.settledBlockCount;
    final int totalBlocks = streamController.currentDocument.blocks.length;
    final int activeTailCount = streamController.activeBlocks.length;
    final bool isComplete =
        appliedChunkCount >= totalChunkCount && streamController.isFinished;
    final double progress = totalChunkCount == 0
        ? 0.0
        : (appliedChunkCount / totalChunkCount).clamp(0.0, 1.0);
    final String buffer = streamController.buffer;
    final int highlightStart =
        lastChunkText.isNotEmpty && buffer.endsWith(lastChunkText)
        ? buffer.length - lastChunkText.length
        : buffer.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.bolt_rounded, size: 16.0, color: scheme.primary),
              const SizedBox(width: 6.0),
              Expanded(
                child: Text(
                  'LLM Streaming Simulator',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6.0,
                  vertical: 2.0,
                ),
                decoration: BoxDecoration(
                  color: isComplete
                      ? scheme.tertiaryContainer
                      : (isPlaying
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest),
                  borderRadius: BorderRadius.circular(5.0),
                ),
                child: Text(
                  isComplete ? 'Finished' : (isPlaying ? 'Streaming' : 'Ready'),
                  style: TextStyle(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w600,
                    color: isComplete
                        ? scheme.onTertiaryContainer
                        : (isPlaying
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: <Widget>[
                  FilledButton.icon(
                    key: const Key('studio-stream-play-pause'),
                    onPressed: onTogglePlayPause,
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 18.0,
                    ),
                    label: Text(isPlaying ? 'Pause' : 'Play'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('studio-stream-step'),
                    onPressed: appliedChunkCount < totalChunkCount
                        ? onStep
                        : null,
                    icon: const Icon(Icons.skip_next_rounded, size: 18.0),
                    label: const Text('Step'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('studio-stream-reset'),
                    onPressed: onReset,
                    icon: const Icon(Icons.replay_rounded, size: 16.0),
                    label: const Text('Reset'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('studio-stream-finish'),
                    onPressed: isComplete ? null : onFinish,
                    icon: const Icon(Icons.fast_forward_rounded, size: 16.0),
                    label: const Text('Finish'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Speed',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Text(
                    '$chunkIntervalMs ms/chunk',
                    key: const Key('studio-stream-speed-label'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                      fontFamily: 'SF Mono',
                      fontFamilyFallback:
                          MarkdownThemeData.defaultCodeFontFallback,
                    ),
                  ),
                ],
              ),
              Slider(
                key: const Key('studio-stream-speed-slider'),
                min: 20.0,
                max: 400.0,
                divisions: 19,
                value: chunkIntervalMs.clamp(20, 400).toDouble(),
                onChanged: (double v) => onIntervalChanged(v.round()),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Chunks: $appliedChunkCount / $totalChunkCount',
                      key: const Key('studio-stream-progress-label'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                        fontFamily: 'SF Mono',
                        fontFamilyFallback:
                            MarkdownThemeData.defaultCodeFontFallback,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Text(
                    '${(progress * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                      fontFamily: 'SF Mono',
                      fontFamilyFallback:
                          MarkdownThemeData.defaultCodeFontFallback,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4.0),
              ClipRRect(
                borderRadius: BorderRadius.circular(4.0),
                child: LinearProgressIndicator(value: progress, minHeight: 6.0),
              ),
              const SizedBox(height: 12.0),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: <Widget>[
                  _TelemetryCard(
                    valueKey: const Key('studio-stream-settled'),
                    label: 'Settled Blocks',
                    value: '$settledCount',
                    detail: 'frozen prefix',
                    accent: scheme.tertiary,
                    scheme: scheme,
                  ),
                  _TelemetryCard(
                    valueKey: const Key('studio-stream-total-blocks'),
                    label: 'Total Blocks',
                    value: '$totalBlocks',
                    detail: '$activeTailCount active tail',
                    accent: scheme.primary,
                    scheme: scheme,
                  ),
                  _TelemetryCard(
                    valueKey: const Key('studio-stream-parse-us'),
                    label: 'Chunk Parse',
                    value: '$lastChunkParseMicros µs',
                    detail: 'avg $averageChunkParseMicros µs',
                    accent: scheme.secondary,
                    scheme: scheme,
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1.0),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          color: scheme.surfaceContainerLowest,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Live Stream Buffer',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 6.0),
              Text(
                '${buffer.length} ch',
                style: TextStyle(
                  fontSize: 11.0,
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'SF Mono',
                  fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12.0),
            child: buffer.isEmpty
                ? Text(
                    'Press Play or Step to stream Markdown chunks incrementally.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : SelectableText.rich(
                    TextSpan(
                      style: TextStyle(
                        fontFamily: 'SF Mono',
                        fontFamilyFallback:
                            MarkdownThemeData.defaultCodeFontFallback,
                        fontSize: 12.0,
                        height: 1.45,
                        color: scheme.onSurface,
                      ),
                      children: <TextSpan>[
                        TextSpan(text: buffer.substring(0, highlightStart)),
                        if (highlightStart < buffer.length)
                          TextSpan(
                            text: buffer.substring(highlightStart),
                            style: TextStyle(
                              backgroundColor: scheme.primaryContainer,
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

final class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard({
    required this.valueKey,
    required this.label,
    required this.value,
    required this.detail,
    required this.accent,
    required this.scheme,
  });

  final Key valueKey;
  final String label;
  final String value;
  final String detail;
  final Color accent;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 102.0),
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2.0),
          Text(
            value,
            key: valueKey,
            style: TextStyle(
              fontSize: 15.0,
              fontWeight: FontWeight.w700,
              color: accent,
              fontFamily: 'SF Mono',
              fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
            ),
          ),
          Text(
            detail,
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
