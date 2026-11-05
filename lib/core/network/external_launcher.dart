import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// Opens an external URL in the system's default web browser reliably.
///
/// Windows desktop `canLaunchUrl` frequently returns `false` due to registry
/// protocol checks; calling `launchUrl` directly avoids this false negative.
/// If `launchUrl` fails, fallback to platform process execution (`cmd.exe /c start`
/// on Windows, `xdg-open` on Linux, `open` on macOS) guarantees the browser opens.
Future<bool> launchExternalBrowser(String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri != null) {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {}
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (ok) return true;
    } catch (_) {}
  }
  if (Platform.isWindows) {
    try {
      final p = await Process.start(
        'cmd.exe',
        ['/c', 'start', '', trimmed],
        runInShell: true,
      );
      return await p.exitCode == 0;
    } catch (_) {}
  } else if (Platform.isLinux) {
    try {
      final p = await Process.start('xdg-open', [trimmed]);
      return await p.exitCode == 0;
    } catch (_) {}
  } else if (Platform.isMacOS) {
    try {
      final p = await Process.start('open', [trimmed]);
      return await p.exitCode == 0;
    } catch (_) {}
  }
  return false;
}
