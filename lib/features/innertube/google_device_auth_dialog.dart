import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/external_launcher.dart';
import '../../ui/components/buttons.dart';
import '../../ui/theme/tokens.dart';
import 'google_device_auth.dart';
import 'innertube_api.dart';

class GoogleDeviceAuthDialog extends ConsumerStatefulWidget {
  const GoogleDeviceAuthDialog({super.key});

  @override
  ConsumerState<GoogleDeviceAuthDialog> createState() =>
      _GoogleDeviceAuthDialogState();
}

class _GoogleDeviceAuthDialogState
    extends ConsumerState<GoogleDeviceAuthDialog> {
  GoogleDeviceCode? _code;
  bool _loading = true;
  bool _copied = false;
  bool _success = false;
  String _connectedName = '';
  String? _error;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _startFlow();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _startFlow() async {
    setState(() {
      _loading = true;
      _error = null;
      _code = null;
      _copied = false;
    });

    try {
      final code = await GoogleDeviceAuth.requestDeviceCode();
      if (!mounted || _cancelled) return;

      setState(() {
        _code = code;
        _loading = false;
      });

      // Automatically copy code to clipboard and launch external browser
      await Clipboard.setData(ClipboardData(text: code.userCode));
      if (mounted) setState(() => _copied = true);

      await GoogleDeviceAuth.launchActivationPage(code.verificationUrl);

      // Start polling for approval
      _pollForApproval(code);
    } catch (e) {
      if (!mounted || _cancelled) return;
      setState(() {
        _loading = false;
        _error = 'Could not request device sign-in code: $e';
      });
    }
  }

  Future<void> _pollForApproval(GoogleDeviceCode code) async {
    final tokens = await GoogleDeviceAuth.pollForTokens(
      deviceCode: code.deviceCode,
      interval: code.interval,
    );

    if (!mounted || _cancelled) return;

    if (tokens != null) {
      final name = tokens.name.isNotEmpty
          ? tokens.name
          : (tokens.email.isNotEmpty ? tokens.email : 'Google Account');

      final api = ref.read(innerTubeProvider);
      await api.connectWithOAuth(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        name: tokens.name,
        email: tokens.email,
        picture: tokens.picture,
      );

      // Update riverpod reactive state
      ref.read(ytConnectionProvider.notifier).state = api.connection;

      setState(() {
        _success = true;
        _connectedName = name;
      });

      // Close dialog with success after brief confirmation
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      if (!_cancelled && mounted) {
        setState(() {
          _error = 'Sign-in was not completed or timed out. Please try again.';
        });
      }
    }
  }

  Future<void> _copyAndOpen() async {
    final code = _code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code.userCode));
    if (mounted) setState(() => _copied = true);
    await GoogleDeviceAuth.launchActivationPage(code.verificationUrl);
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 480),
      title: const Row(
        children: [
          Icon(FluentIcons.play, size: 20),
          SizedBox(width: 10),
          Text('Sign in with Google'),
        ],
      ),
      content: _buildContent(context),
      actions: [
        if (!_success)
          WaveButton(
            onPressed: () {
              _cancelled = true;
              Navigator.of(context).pop(false);
            },
            child: const Text('Cancel'),
          ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressRing(),
            SizedBox(height: 16),
            Text(
              'Connecting to Google Device Auth...',
              style: WaveType.body,
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _error!,
              style: WaveType.body.copyWith(color: Colors.red),
            ),
            const SizedBox(height: 16),
            WaveFilledButton(
              onPressed: _startFlow,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_success) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.check_mark, size: 36, color: Colors.green),
            const SizedBox(height: 12),
            Text(
              'Connected as $_connectedName',
              style: WaveType.trackTitle,
            ),
            const SizedBox(height: 4),
            Text(
              'YouTube Music account linked successfully.',
              style: WaveType.meta.copyWith(color: waveTextSecondary(context)),
            ),
          ],
        ),
      );
    }

    final code = _code;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '1. We copied your code and opened google.com/device in your default browser.',
          style: WaveType.body.copyWith(color: waveTextSecondary(context)),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: waveSurfaceSecondary(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: waveBorderColor(context),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                code?.userCode ?? '',
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(width: 16),
              WaveButton(
                onPressed: _copyAndOpen,
                child: Text(_copied ? 'Copied!' : 'Copy Code'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '2. Sign in with your Google account, paste or confirm the code, and click "Allow".',
          style: WaveType.body.copyWith(color: waveTextSecondary(context)),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: ProgressRing(strokeWidth: 2.5),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Waiting for approval in your browser...',
                style: WaveType.meta.copyWith(color: waveTextSecondary(context)),
              ),
            ),
            WaveButton(
              onPressed: _copyAndOpen,
              child: const Text('Re-open Browser'),
            ),
          ],
        ),
      ],
    );
  }
}

Future<bool> showGoogleDeviceAuthDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => const GoogleDeviceAuthDialog(),
  );
  return result ?? false;
}
