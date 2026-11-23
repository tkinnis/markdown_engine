import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'src/cli_args.dart';

/// Runs the real macOS `--profile` frame-time benchmark in
/// `studio/lib/profile_benchmark_main.dart`.
Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Usage: dart run tool/run_macos_profile_benchmark.dart '
      '[--timeout=<seconds>] [--no-pub]',
    );
    return;
  }

  if (!Platform.isMacOS) {
    stderr.writeln(
      'ERROR: tool/run_macos_profile_benchmark.dart requires macOS.',
    );
    exitCode = 2;
    return;
  }

  final File target = File('studio/lib/profile_benchmark_main.dart');
  if (!target.existsSync()) {
    stderr.writeln(
      'ERROR: Missing ${target.path}. Run from the markdown_engine repository root.',
    );
    exitCode = 2;
    return;
  }

  final double? timeoutOverride = parseDoubleFlag(args, 'timeout');
  final int timeoutSeconds = (timeoutOverride != null && timeoutOverride > 0)
      ? timeoutOverride.round()
      : 300;
  final bool noPub = args.contains('--no-pub');

  final List<String> flutterArgs = <String>[
    'run',
    '-d',
    'macos',
    '--profile',
    if (noPub) '--no-pub',
    '-t',
    'lib/profile_benchmark_main.dart',
  ];

  stdout.writeln(
    'Running `(cd studio && flutter ${flutterArgs.join(' ')})`...',
  );

  final Process process = await Process.start(
    'flutter',
    flutterArgs,
    workingDirectory: 'studio',
  );

  final StreamSubscription<String> outSub = process.stdout
      .transform(utf8.decoder)
      .listen(stdout.write);
  final StreamSubscription<String> errSub = process.stderr
      .transform(utf8.decoder)
      .listen(stderr.write);

  bool timedOut = false;
  final Timer watchdog = Timer(Duration(seconds: timeoutSeconds), () {
    timedOut = true;
    stderr.writeln(
      'ERROR: macOS profile benchmark timed out after ${timeoutSeconds}s.',
    );
    process.kill(ProcessSignal.sigterm);
  });

  final int code = await process.exitCode;
  watchdog.cancel();
  await outSub.cancel();
  await errSub.cancel();

  if (timedOut) {
    exitCode = 124;
    return;
  }
  exitCode = code;
}
