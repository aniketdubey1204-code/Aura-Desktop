import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../ui/components/buttons.dart';
import '../../ui/components/inputs.dart';
import '../../ui/theme/tokens.dart';
import 'innertube_api.dart';
import 'yt_profile_chooser.dart';
import 'yt_web_login.dart';

Future<void> refocusMain() async {
  try {
    await windowManager.focus();
  } catch (_) {}
}

Future<void> showYtOk(BuildContext context, String title, String message) {
  return showDialog(
    context: context,
    builder: (dialogContext) => ContentDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        WaveFilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<void> showYtFail(BuildContext context, Object e) {
  return showDialog(
    context: context,
    builder: (dialogContext) => ContentDialog(
      title: const Text('Connection failed'),
      content: Text('$e'),
      actions: [
        WaveFilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<void> ytSignInFailed(BuildContext context, WidgetRef ref) async {
  final failure = YtWebLogin.lastFailure;
  if (failure == YtSignInFailure.windowClosed) return;

  late String title;
  late String body;
  switch (failure) {
    case YtSignInFailure.browserBlocked:
      title = 'Google blocked the built-in browser';
      body =
          'Google refuses to serve its sign-in page to embedded '
          'browsers on some configurations.\n\n'
          'Use "Connect with cookies" instead: sign in to '
          'music.youtube.com in Chrome, Edge or Firefox, copy the cookie '
          'table, and paste it here. That jar is a normal browser '
          'session and works on every platform.';
    case YtSignInFailure.unavailable:
      title = 'No system WebView available';
      body =
          'This machine has no usable WebView runtime (WebView2 on '
          'Windows, WebKitGTK on Linux), so the sign-in window cannot '
          'open. Connect with cookies instead — that path does not need a WebView.';
    case YtSignInFailure.blankPage:
      title = 'The sign-in window did not load';
      body =
          'The browser window stayed on a blank or error page even '
          'after reloading. That usually means the WebView profile '
          'folder is not writable or the runtime is damaged.\n\n'
          'Connecting with cookies does not depend on the WebView and '
          'will work.';
    case YtSignInFailure.timeout:
      title = 'Sign-in timed out';
      body =
          'No session was captured in ten minutes. Make sure the '
          'sign-in finishes on music.youtube.com — an intermediate '
          'accounts.google.com page has no YouTube session yet.\n\n'
          'You can try again, or connect with cookies instead.';
    case YtSignInFailure.noSession:
    case YtSignInFailure.none:
    case YtSignInFailure.windowClosed:
      title = 'Sign-in incomplete';
      body =
          'The browser window closed before a YouTube Music session '
          'was captured. If you use a brand channel or 2FA, complete all '
          'steps until the YouTube Music home page loads.';
  }

  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (dialogContext) => ContentDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        WaveButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        WaveFilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            ytConnectWithCookies(context, ref);
          },
          child: const Text('Connect with cookies'),
        ),
      ],
    ),
  );
}

Future<void> refreshYtIdentity(WidgetRef ref, {String pageId = ''}) async {
  try {
    final cookies = ref.read(innerTubeProvider).connection.cookies;
    if (cookies.isNotEmpty) {
      await upsertYtCapture(ref, cookies: cookies, pageId: pageId);
    }
    ref.invalidate(ytAccountProvider);
  } catch (_) {}
}

Future<bool> ytConnectCaptured(
  BuildContext context,
  WidgetRef ref, {
  required String header,
  required String pageId,
  bool showSuccessDialog = true,
}) async {
  final profile = await upsertYtCapture(ref, cookies: header, pageId: pageId);
  if (profile != null) {
    final discovered = await ref.read(innerTubeProvider).fetchChannelsFor(header);
    if (discovered.isNotEmpty) {
      await upsertYtChannels(
        ref,
        cookies: header,
        email: profile.email,
        channels: discovered,
      );
    }
  }
  if (!context.mounted) return false;
  final roster = ref.read(ytProfilesProvider);
  final conn = ref.read(ytConnectionProvider);
  final sel = await showYtProfileChooser(
    context: context,
    roster: roster,
    activeEmail: profile?.email ?? conn.profileEmail,
    activePageId: pageId,
  );
  if (!context.mounted) return false;
  if (sel == null) {
    // cancelled chooser fallback
    final tube = ref.read(innerTubeProvider);
    try {
      await tube.connectAs(
        cookies: header,
        profileEmail: profile?.email ?? '',
        pageId: pageId,
      );
      ref.read(ytConnectionProvider.notifier).state = tube.connection;
      await refreshYtIdentity(ref, pageId: pageId);
      if (showSuccessDialog && context.mounted) {
        await showYtOk(
          context,
          'YouTube Music connected',
          'Account verified — library, history and uploads are unlocked.',
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        await showYtFail(context, e);
      }
      return false;
    }
  }

  YtProfile? target;
  for (final p in ref.read(ytProfilesProvider)) {
    if (p.email == sel.email) {
      target = p;
      break;
    }
  }
  target ??= profile;
  if (target == null) {
    if (context.mounted) {
      await showYtFail(context, 'Profile vanished — please try again.');
    }
    return false;
  }

  try {
    await switchYtIdentity(ref, profile: target, pageId: sel.pageId);
    await refreshYtIdentity(ref, pageId: sel.pageId);
    if (showSuccessDialog && context.mounted) {
      await showYtOk(
        context,
        'YouTube Music connected',
        'Account verified — library, history and uploads are unlocked.',
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      await showYtFail(context, e);
    }
    return false;
  }
}

Future<bool> ytWebSignIn(
  BuildContext context,
  WidgetRef ref, {
  bool showSuccessDialog = true,
}) async {
  BuildContext? waitDialogContext;
  var cancelled = false;

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        waitDialogContext = dialogContext;
        return ContentDialog(
          title: const Text('Sign in with YouTube Music'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Complete sign-in in the YouTube Music window that just '
                'opened. Aura will finish connecting automatically once '
                'you land on music.youtube.com.',
              ),
              SizedBox(height: 12),
              Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: ProgressRing(),
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Window not visible? Look for "Aura YouTube Sign In" in the taskbar.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            WaveButton(
              onPressed: () {
                YtWebLogin.reloadLoginPage();
              },
              child: const Text('Reload'),
            ),
            WaveButton(
              onPressed: () {
                cancelled = true;
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    ),
  );

  String? header;
  try {
    header = await YtWebLogin.signIn();
  } catch (_) {
    header = null;
  }

  final waitCtx = waitDialogContext;
  if (waitCtx != null && waitCtx.mounted) {
    Navigator.of(waitCtx).maybePop();
  }

  if (cancelled || header == null || header.isEmpty) {
    if (!cancelled && context.mounted) {
      await ytSignInFailed(context, ref);
    }
    return false;
  }

  if (!context.mounted) return false;
  final ok = await ytConnectCaptured(
    context,
    ref,
    header: header,
    pageId: YtWebLogin.lastCapturedPageId ?? '',
    showSuccessDialog: showSuccessDialog,
  );
  await refocusMain();
  return ok;
}

List<String> cookieNamesFrom(String raw) {
  try {
    final normalized = InnerTubeMusicApi.normalizeCookies(raw);
    final out = <String>[];
    for (final part in normalized.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final n = part.substring(0, i).trim();
      if (n.isNotEmpty) out.add(n);
    }
    return out;
  } catch (_) {
    return const [];
  }
}

Future<void> openYtInBrowser() async {
  final uri = Uri.parse('https://music.youtube.com/');
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {}
}

Future<String?> pickCookieFile() async {
  try {
    final f = await FilePicker.pickFile(
      dialogTitle: 'Select a cookies.txt export',
      type: FileType.any,
    );
    if (f == null) return null;
    final size = await f.length();
    if (size > 2 * 1024 * 1024) return null;
    final bytes = await f.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  }
}

class CookieChecklist extends StatelessWidget {
  final List<String> missing;
  final bool hasInput;
  const CookieChecklist({super.key, required this.missing, required this.hasInput});

  @override
  Widget build(BuildContext context) {
    if (!hasInput) return const SizedBox.shrink();
    final ok = missing.isEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? FluentIcons.check_mark : FluentIcons.warning,
          size: 14,
          color: ok ? null : Colors.orange,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ok
                ? 'Session markers detected — this jar looks complete.'
                : 'Not detected yet: ${missing.join(' · ')}. '
                      'YouTube needs these to treat the jar as signed in.',
            style: WaveType.meta.copyWith(color: waveTextSecondary(context)),
          ),
        ),
      ],
    );
  }
}

Future<bool> ytConnectWithCookies(
  BuildContext context,
  WidgetRef ref, {
  bool showSuccessDialog = true,
}) async {
  final controller = TextEditingController();
  String? errorText;
  var missing = const <String>[];
  var hasInput = false;

  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        void analyse() {
          final text = controller.text.trim();
          hasInput = text.isNotEmpty;
          missing = hasInput
              ? YtWebLogin.missingMarkerNames(cookieNamesFrom(text))
              : const [];
        }

        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 540),
          title: const Text('Connect with cookies'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Use this when the built-in sign-in window is blocked or '
                'cannot load. The jar comes from your own browser, so '
                'Google sees a normal desktop session.',
                style: WaveType.meta.copyWith(
                  color: waveTextSecondary(context),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  WaveButton(
                    onPressed: openYtInBrowser,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.open_in_new_window, size: 14),
                        SizedBox(width: 6),
                        Text('Open music.youtube.com'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  WaveButton(
                    onPressed: () async {
                      final text = await pickCookieFile();
                      if (text == null || text.isEmpty) return;
                      if (!context.mounted) return;
                      controller.text = text;
                      setState(() {
                        errorText = null;
                        analyse();
                      });
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.open_folder_horizontal, size: 14),
                        SizedBox(width: 6),
                        Text('Import cookies.txt'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'In Chrome/Edge: sign in to music.youtube.com, press F12 '
                '→ Network, reload the page, open any music.youtube.com '
                'request and copy the value of its Cookie request header. '
                'Paste it below.',
                style: WaveType.meta.copyWith(
                  color: waveTextSecondary(context),
                ),
              ),
              const SizedBox(height: 12),
              TextBox(
                decoration: waveInputDecoration(),
                controller: controller,
                placeholder: 'SID=...; __Secure-3PAPISID=...; SAPISID=...',
                maxLines: 7,
                minLines: 4,
                autofocus: true,
                onChanged: (_) => setState(() {
                  errorText = null;
                  analyse();
                }),
              ),
              const SizedBox(height: 10),
              CookieChecklist(missing: missing, hasInput: hasInput),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorText!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ],
            ],
          ),
          actions: [
            WaveButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            WaveFilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) {
                  setState(() => errorText = 'Paste the cookie text first.');
                  return;
                }
                try {
                  Navigator.of(dialogContext)
                      .pop(InnerTubeMusicApi.normalizeCookies(text));
                } catch (e) {
                  setState(() {
                    errorText = e is FormatException
                        ? e.message
                        : 'Invalid cookies. Make sure SAPISID is present.';
                  });
                }
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();

  if (result != null && result.isNotEmpty && context.mounted) {
    return await ytConnectCaptured(
      context,
      ref,
      header: result,
      pageId: '',
      showSuccessDialog: showSuccessDialog,
    );
  }
  return false;
}
