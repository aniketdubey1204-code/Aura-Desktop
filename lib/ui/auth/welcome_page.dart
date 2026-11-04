import 'dart:io' show Platform;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/accessibility.dart';
import '../../core/storage/prefs.dart';
import '../../features/home/home_providers.dart';
import '../../features/innertube/yt_auth_actions.dart';
import '../../features/lastfm/auth_repository.dart';
import '../components/buttons.dart';
import '../components/inputs.dart';
import '../settings/spotify_connect.dart';
import '../theme/tokens.dart';
import '../theme/wave_icons.dart';
import 'lastfm_key_guide.dart';

const _githubUrl = 'https://github.com/aniketdubey1204-code/LastWave-Desktop';

enum _WelcomeBusyAction { none, ytWeb, ytCookie, spotify, guest, lastfm }

/// Entry screen for Aura: sign in with YouTube Music, connect Spotify,
/// continue as guest, or connect Last.fm.
class WaveWelcomePage extends ConsumerStatefulWidget {
  const WaveWelcomePage({super.key});

  @override
  ConsumerState<WaveWelcomePage> createState() => _WaveWelcomePageState();
}

class _WaveWelcomePageState extends ConsumerState<WaveWelcomePage> {
  WebAuthHandshake? _handshake;
  bool _busy = false;
  _WelcomeBusyAction _busyAction = _WelcomeBusyAction.none;
  String? _error;

  Future<void> _signInWithYouTube() async {
    setState(() {
      _busy = true;
      _busyAction = _WelcomeBusyAction.ytWeb;
      _error = null;
    });
    try {
      final ok = await ytWebSignIn(context, ref, showSuccessDialog: false);
      if (ok) {
        await ref.read(authRepositoryProvider.notifier).enterGuestMode();
        ref.invalidate(feedProvider);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not sign in to YouTube Music: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyAction = _WelcomeBusyAction.none;
        });
      }
    }
  }

  Future<void> _connectWithCookies() async {
    setState(() {
      _busy = true;
      _busyAction = _WelcomeBusyAction.ytCookie;
      _error = null;
    });
    try {
      final ok = await ytConnectWithCookies(context, ref, showSuccessDialog: false);
      if (ok) {
        await ref.read(authRepositoryProvider.notifier).enterGuestMode();
        ref.invalidate(feedProvider);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not connect cookies: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyAction = _WelcomeBusyAction.none;
        });
      }
    }
  }

  Future<void> _connectSpotify() async {
    setState(() {
      _busy = true;
      _busyAction = _WelcomeBusyAction.spotify;
      _error = null;
    });
    try {
      final ok = await spotifyConnectWithWebView(context, ref);
      if (ok) {
        await ref.read(authRepositoryProvider.notifier).enterGuestMode();
        ref.invalidate(feedProvider);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not connect Spotify: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyAction = _WelcomeBusyAction.none;
        });
      }
    }
  }

  Future<void> _beginWebAuth() async {
    setState(() {
      _busy = true;
      _busyAction = _WelcomeBusyAction.lastfm;
      _error = null;
    });
    try {
      final handshake = await ref
          .read(authRepositoryProvider.notifier)
          .beginWebAuth();
      if (!mounted) return;
      setState(() => _handshake = handshake);
      AppAccessibility.announce(
        context,
        'Opening Last.fm in your browser. Approve Aura there, then '
        'come back and press "I\'ve approved - finish sign-in".',
      );
      final uri = Uri.parse(handshake.url);
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() => _error =
          'Could not reach Last.fm. Check your connection and retry.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyAction = _WelcomeBusyAction.none;
        });
      }
    }
  }

  Future<void> _completeWebAuth() async {
    final handshake = _handshake;
    if (handshake == null) return;
    setState(() {
      _busy = true;
      _busyAction = _WelcomeBusyAction.lastfm;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider.notifier)
          .completeWebAuth(handshake.token);
      ref.invalidate(feedProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error =
          'Not approved yet — approve Aura in the browser, then retry.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyAction = _WelcomeBusyAction.none;
        });
      }
    }
  }

  Future<void> _enterGuest() async {
    setState(() {
      _busy = true;
      _busyAction = _WelcomeBusyAction.guest;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider.notifier).enterGuestMode();
      ref.invalidate(feedProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not continue as guest. Retry.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyAction = _WelcomeBusyAction.none;
        });
      }
    }
  }

  Future<void> _openGitHub() async {
    final uri = Uri.parse(_githubUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final dark = waveIsDark(context);
    final accent = waveAccent(context);
    return Mica(
      backgroundColor: waveBackground(context),
      child: Column(
        children: [
          const _WelcomeChrome(),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 0.9,
                  colors: [
                    accent.withValues(alpha: dark ? 0.12 : 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
              child: _CenterScroll(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: _AuthPanel(
                      handshake: _handshake,
                      busy: _busy,
                      busyAction: _busyAction,
                      error: _error,
                      onYtSignIn: _signInWithYouTube,
                      onYtCookies: _connectWithCookies,
                      onSpotify: _connectSpotify,
                      onConnect: _beginWebAuth,
                      onFinish: _completeWebAuth,
                      onSkip: _enterGuest,
                      onGitHub: _openGitHub,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterScroll extends StatelessWidget {
  final Widget child;
  const _CenterScroll({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}

class _WelcomeChrome extends StatelessWidget {
  const _WelcomeChrome();

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: SizedBox(
        height: WaveDensity.titleBar,
        child: Row(
          children: [
            SizedBox(width: Platform.isMacOS ? 84 : 16),
            Text(
              'AURA',
              style: WaveType.overline.copyWith(
                color: waveTextTertiary(context),
              ),
            ),
            const Spacer(),
            if (!Platform.isMacOS) ...[
              _ChromeBtn(
                tooltip: 'Minimize',
                icon: WaveIcons.minimize,
                onTap: () async {
                  try {
                    await windowManager.minimize();
                  } catch (_) {}
                },
              ),
              _ChromeBtn(
                tooltip: 'Maximize',
                icon: WaveIcons.maximize,
                iconSize: 12,
                onTap: () async {
                  try {
                    if (await windowManager.isMaximized()) {
                      await windowManager.unmaximize();
                    } else {
                      await windowManager.maximize();
                    }
                  } catch (_) {}
                },
              ),
              _ChromeBtn(
                tooltip: 'Close',
                icon: WaveIcons.close,
                danger: true,
                onTap: () async {
                  try {
                    await windowManager.close();
                  } catch (_) {}
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChromeBtn extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final bool danger;
  final VoidCallback onTap;
  const _ChromeBtn({
    required this.tooltip,
    required this.icon,
    this.iconSize = 14,
    this.danger = false,
    required this.onTap,
  });

  @override
  State<_ChromeBtn> createState() => _ChromeBtnState();
}

class _ChromeBtnState extends State<_ChromeBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = waveIsDark(context);
    return WaveA11yButton(
      label: widget.tooltip,
      onTap: widget.onTap,
      child: LWTooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: waveMotion(context, WaveMotion.fast),
              width: 46,
              height: WaveDensity.titleBar,
              color: _hover
                  ? (widget.danger
                      ? WaveColors.danger
                      : (dark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.black.withValues(alpha: 0.06)))
                  : Colors.transparent,
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: _hover && widget.danger
                    ? Colors.white
                    : (dark
                        ? WaveColors.textSecondary
                        : WaveColors.lightTextSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EqualizerRow extends StatelessWidget {
  const _EqualizerRow();

  @override
  Widget build(BuildContext context) {
    const heights = [
      18.0, 34.0, 52.0, 28.0, 64.0, 44.0, 72.0, 36.0, 56.0,
      24.0, 48.0, 68.0, 40.0, 58.0, 30.0, 50.0, 22.0, 42.0,
      60.0, 32.0, 46.0, 20.0, 38.0, 54.0,
    ];
    final accent = waveAccent(context);
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < heights.length; i++)
            Container(
              width: 5,
              height: heights[i],
              decoration: BoxDecoration(
                borderRadius: WaveRadius.tinyRadius,
                color: i % 5 == 2
                    ? accent
                    : accent.withValues(alpha: 0.25 + (i % 5) * 0.1),
              ),
            ),
        ],
      ),
    );
  }
}

class _AuthPanel extends ConsumerStatefulWidget {
  final WebAuthHandshake? handshake;
  final bool busy;
  final _WelcomeBusyAction busyAction;
  final String? error;
  final VoidCallback onYtSignIn;
  final VoidCallback onYtCookies;
  final VoidCallback onSpotify;
  final VoidCallback onConnect;
  final VoidCallback onFinish;
  final VoidCallback onSkip;
  final VoidCallback onGitHub;

  const _AuthPanel({
    required this.handshake,
    required this.busy,
    required this.busyAction,
    required this.error,
    required this.onYtSignIn,
    required this.onYtCookies,
    required this.onSpotify,
    required this.onConnect,
    required this.onFinish,
    required this.onSkip,
    required this.onGitHub,
  });

  @override
  ConsumerState<_AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends ConsumerState<_AuthPanel> {
  bool _wantsLastFm = false;

  @override
  Widget build(BuildContext context) {
    final dark = waveIsDark(context);
    final accent = waveAccent(context);
    final handshake = widget.handshake;
    final busy = widget.busy;
    final busyAction = widget.busyAction;
    final error = widget.error;
    final tertiary =
        dark ? WaveColors.textTertiary : WaveColors.lightTextTertiary;

    ref.watch(authRepositoryProvider.select((s) => s.status));
    final configured = ref.watch(prefsProvider).isLastFmConfigured;
    final showKeys = !configured && _wantsLastFm;

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 28, 36, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _WelcomeLogo(),
          const SizedBox(height: 20),
          Text(
            'Aura',
            textAlign: TextAlign.center,
            style: WaveType.pageTitle.copyWith(fontSize: 38),
          ),
          const SizedBox(height: 6),
          Text(
            'High-Resolution Lossless Music Player',
            textAlign: TextAlign.center,
            style: WaveType.body.copyWith(
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Stream YouTube Music and lossless FLAC up to 24-bit / '
            '192 kHz, with synced lyrics and offline downloads.',
            textAlign: TextAlign.center,
            style: WaveType.body.copyWith(
              color: dark
                  ? WaveColors.textSecondary
                  : WaveColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 24),
          if (error != null) ...[
            Semantics(
              liveRegion: true,
              container: true,
              label: 'Error: $error',
              child: ExcludeSemantics(
                child: InfoBar(
                  title: const Text('Could not sign in'),
                  content: Text(error),
                  severity: InfoBarSeverity.error,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // 1. YouTube Music primary login
          WaveFilledButton(
            autofocus: handshake == null && !_wantsLastFm,
            onPressed: busy ? null : widget.onYtSignIn,
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 13),
              ),
            ),
            child: busy && busyAction == _WelcomeBusyAction.ytWeb
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 15,
                        height: 15,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Opening sign-in window...'),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.play_solid, size: 14),
                      SizedBox(width: 8),
                      Text('Login with YouTube Music'),
                    ],
                  ),
          ),
          const SizedBox(height: 10),

          // 2. Cookie login + Spotify connect row
          Row(
            children: [
              Expanded(
                child: WaveButton(
                  onPressed: busy ? null : widget.onYtCookies,
                  style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.code, size: 13),
                      SizedBox(width: 6),
                      Text('Cookie Login'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WaveButton(
                  onPressed: busy ? null : widget.onSpotify,
                  style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                  child: busy && busyAction == _WelcomeBusyAction.spotify
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 13,
                              height: 13,
                              child: ProgressRing(strokeWidth: 2),
                            ),
                            SizedBox(width: 6),
                            Text('Connecting...'),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(FluentIcons.music_in_collection, size: 13),
                            SizedBox(width: 6),
                            Text('Connect Spotify'),
                          ],
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. Guest Mode
          WaveButton(
            onPressed: busy ? null : widget.onSkip,
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 11),
              ),
            ),
            child: busy && busyAction == _WelcomeBusyAction.guest
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Entering Aura...'),
                    ],
                  )
                : const Text('Continue as guest'),
          ),
          const SizedBox(height: 6),
          Text(
            'Browse, stream and download right away without an account.',
            textAlign: TextAlign.center,
            style: WaveType.meta.copyWith(color: tertiary),
          ),
          const SizedBox(height: 18),

          // 4. Optional Last.fm expander
          Expander(
            header: Text(
              'Connect Last.fm (Optional)',
              style: WaveType.meta.copyWith(
                fontWeight: FontWeight.w600,
                color: waveTextPrimary(context),
              ),
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Scrobble tracks and sync listening stats with Last.fm.',
                  style: WaveType.meta.copyWith(color: tertiary),
                ),
                const SizedBox(height: 10),
                if (showKeys) ...[
                  const _ApiKeyForm(),
                  const SizedBox(height: 10),
                ],
                WaveButton(
                  onPressed: busy
                      ? null
                      : (!configured && !_wantsLastFm)
                          ? () => setState(() => _wantsLastFm = true)
                          : (!configured ? null : widget.onConnect),
                  style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                  child: busy && handshake == null && _wantsLastFm
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: ProgressRing(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Contacting Last.fm...'),
                          ],
                        )
                      : Text(
                          handshake == null
                              ? 'Connect with Last.fm'
                              : 'Restart approval',
                        ),
                ),
                if (handshake != null) ...[
                  const SizedBox(height: 8),
                  WaveButton(
                    autofocus: true,
                    onPressed: busy ? null : widget.onFinish,
                    style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                    child: busy
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: ProgressRing(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('Confirming...'),
                            ],
                          )
                        : const Text("I've approved - finish sign-in"),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Approve Aura in the browser tab that just opened, '
                    'then finish sign-in here.',
                    style: WaveType.meta.copyWith(color: tertiary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),
          const ExcludeSemantics(child: _EqualizerRow()),
          const SizedBox(height: 20),
          Container(height: 1, color: waveDivider(context)),
          const SizedBox(height: 12),
          WaveLink(
            onPressed: widget.onGitHub,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(FluentIcons.favorite_star, size: 14),
                SizedBox(width: 6),
                Text('Star Aura on GitHub'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiKeyForm extends ConsumerStatefulWidget {
  const _ApiKeyForm();
  @override
  ConsumerState<_ApiKeyForm> createState() => _ApiKeyFormState();
}

class _ApiKeyFormState extends ConsumerState<_ApiKeyForm> {
  TextEditingController? _key;
  TextEditingController? _secret;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _key?.dispose();
    _secret?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider.notifier).saveCustomKeys(
            _key?.text ?? '',
            _secret?.text ?? '',
          );
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e.toString().replaceFirst('LastFmException(null): ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = waveIsDark(context);
    ref.watch(authRepositoryProvider.select((s) => s.status));
    final saved = ref.watch(prefsProvider).isLastFmConfigured;
    _key ??= TextEditingController(text: ref.read(prefsProvider).lastFmApiKey);
    _secret ??= TextEditingController(text: ref.read(prefsProvider).lastFmApiSecret);
    if (saved && !_busy) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: WaveRadius.floatingRadius,
          border: Border.all(color: waveDivider(context)),
        ),
        child: Row(
          children: [
            const Icon(FluentIcons.check_mark, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  'Keys validated — connect with Last.fm below.',
                  style: WaveType.meta.copyWith(color: Colors.green),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: WaveRadius.floatingRadius,
        border: Border.all(color: waveDivider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Last.fm API keys', style: WaveType.label),
          const SizedBox(height: 4),
          const LastFmKeyGuide(),
          const SizedBox(height: 8),
          Semantics(
            label: 'Last.fm API key',
            textField: true,
            child: TextBox(
              decoration: waveInputDecoration(),
              controller: _key,
              placeholder: 'API key',
              autofocus: true,
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: 'Last.fm shared secret',
            textField: true,
            obscured: true,
            child: TextBox(
              decoration: waveInputDecoration(),
              controller: _secret,
              placeholder: 'Shared secret',
              obscureText: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: WaveType.meta.copyWith(color: Colors.red),
              ),
            ),
          ],
          const SizedBox(height: 10),
          WaveButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Validating…'),
                    ],
                  )
                : const Text('Save keys'),
          ),
          const SizedBox(height: 6),
          Text(
            'Aura ships with no keys of its own — these stay on this device.',
            style: WaveType.meta.copyWith(
              color: dark ? WaveColors.textTertiary : WaveColors.lightTextTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _WelcomeLogo extends StatelessWidget {
  const _WelcomeLogo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        'assets/brand/aura-logo.png',
        width: 96,
        height: 96,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Aura logo',
      ),
    );
  }
}
