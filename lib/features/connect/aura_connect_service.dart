import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents a remote Aura device (e.g. Android phone connected to a speaker).
@immutable
class AuraConnectDevice {
  final String id;
  final String name;
  final String type; // 'phone', 'desktop'
  final String outputRoute; // e.g. "Bluetooth: JBL Flip 6", "Phone speaker"
  final String ip;
  final int port;
  final DateTime lastSeen;

  const AuraConnectDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.outputRoute,
    required this.ip,
    required this.port,
    required this.lastSeen,
  });

  AuraConnectDevice copyWith({
    String? id,
    String? name,
    String? type,
    String? outputRoute,
    String? ip,
    int? port,
    DateTime? lastSeen,
  }) {
    return AuraConnectDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      outputRoute: outputRoute ?? this.outputRoute,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

/// Remote track metadata mirrored from the remote device.
@immutable
class AuraRemoteTrack {
  final String title;
  final String artist;
  final String album;
  final String artworkUrl;
  final String videoId;
  final Duration duration;

  const AuraRemoteTrack({
    required this.title,
    required this.artist,
    this.album = '',
    this.artworkUrl = '',
    this.videoId = '',
    this.duration = Duration.zero,
  });

  factory AuraRemoteTrack.fromJson(Map<String, dynamic> json) {
    final durMs = (json['durationMs'] as num?)?.toInt() ?? 0;
    return AuraRemoteTrack(
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      album: json['album'] as String? ?? '',
      artworkUrl: json['artworkUrl'] as String? ?? '',
      videoId: json['videoId'] as String? ?? '',
      duration: Duration(milliseconds: durMs),
    );
  }
}

/// Live snapshot of the Aura Connect mesh state.
@immutable
class AuraConnectState {
  final List<AuraConnectDevice> discoveredDevices;
  final AuraConnectDevice? activeDevice;
  final bool isRemoteActive;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double volume;
  final AuraRemoteTrack? currentTrack;

  const AuraConnectState({
    this.discoveredDevices = const [],
    this.activeDevice,
    this.isRemoteActive = false,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.currentTrack,
  });

  AuraConnectState copyWith({
    List<AuraConnectDevice>? discoveredDevices,
    AuraConnectDevice? activeDevice,
    bool? isRemoteActive,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? volume,
    AuraRemoteTrack? currentTrack,
    bool clearActiveDevice = false,
    bool clearTrack = false,
  }) {
    return AuraConnectState(
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      activeDevice: clearActiveDevice ? null : (activeDevice ?? this.activeDevice),
      isRemoteActive: isRemoteActive ?? this.isRemoteActive,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      currentTrack: clearTrack ? null : (currentTrack ?? this.currentTrack),
    );
  }
}

final auraConnectProvider =
    StateNotifierProvider<AuraConnectNotifier, AuraConnectState>((ref) {
  final notifier = AuraConnectNotifier();
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

class AuraConnectNotifier extends StateNotifier<AuraConnectState> {
  static const int connectUdpPort = 8766;
  static const int defaultHttpPort = 8765;

  RawDatagramSocket? _udpSocket;
  Timer? _discoveryTimer;
  Timer? _pollTimer;
  Timer? _tickerTimer;
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3);

  AuraConnectNotifier() : super(const AuraConnectState()) {
    _initDiscovery();
  }

  void _initDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket?.broadcastEnabled = true;
      _udpSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket?.receive();
          if (datagram != null) {
            _handleDatagram(datagram);
          }
        }
      });

      // Send immediate discovery beacon and every 3 seconds thereafter
      _sendDiscoveryPing();
      _discoveryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _sendDiscoveryPing();
        _pruneStaleDevices();
      });

      // Local 1-second position ticker for smooth scrubbing display while playing
      _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (state.isRemoteActive && state.isPlaying) {
          final nextPos = state.position + const Duration(seconds: 1);
          if (state.duration > Duration.zero && nextPos <= state.duration) {
            state = state.copyWith(position: nextPos);
          }
        }
      });
    } catch (e) {
      debugPrint('[AuraConnect] UDP discovery setup failed: $e');
    }
  }

  void _sendDiscoveryPing() {
    try {
      final msg = utf8.encode(jsonEncode({
        'type': 'aura_discover',
        'fromDevice': 'Aura-Desktop',
        'clientTime': DateTime.now().millisecondsSinceEpoch,
      }));
      _udpSocket?.send(msg, InternetAddress('255.255.255.255'), connectUdpPort);
    } catch (_) {}
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final text = utf8.decode(datagram.data).trim();
      if (!text.startsWith('{')) return;
      final json = jsonDecode(text) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';

      if (type == 'aura_presence' || type == 'aura_state') {
        final devJson = json['device'] as Map<String, dynamic>?;
        final devId = devJson?['id'] as String? ??
            json['deviceId'] as String? ??
            'unknown-device';
        final devName = devJson?['name'] as String? ??
            json['deviceName'] as String? ??
            'Aura Device';
        final devType = devJson?['type'] as String? ??
            json['deviceType'] as String? ??
            'phone';
        final outputRoute = devJson?['outputRoute'] as String? ??
            json['outputRoute'] as String? ??
            'Speaker';
        final port = (devJson?['httpPort'] as num?)?.toInt() ??
            (json['httpPort'] as num?)?.toInt() ??
            defaultHttpPort;
        final senderIp = datagram.address.address;

        final device = AuraConnectDevice(
          id: devId,
          name: devName,
          type: devType,
          outputRoute: outputRoute,
          ip: senderIp,
          port: port,
          lastSeen: DateTime.now(),
        );

        _upsertDevice(device);

        // Instant parse from UDP broadcast packet for zero-latency reflection
        final playback = json['playback'] as Map<String, dynamic>?;
        final isPlaying = playback?['isPlaying'] as bool? ??
            json['isPlaying'] as bool? ??
            false;
        final trackObj = playback?['track'] as Map<String, dynamic>?;
        final hasTrack = trackObj != null;

        if (playback != null && (state.activeDevice?.id == device.id || state.activeDevice == null)) {
          final posMs = (playback['positionMs'] as num?)?.toInt() ?? 0;
          final durMs = (playback['durationMs'] as num?)?.toInt() ?? 0;
          final vol = (playback['volume'] as num?)?.toDouble() ?? 1.0;
          final track = trackObj != null ? AuraRemoteTrack.fromJson(trackObj) : null;

          if (hasTrack || isPlaying) {
            state = state.copyWith(
              activeDevice: device,
              isRemoteActive: true,
              isPlaying: isPlaying,
              position: Duration(milliseconds: posMs),
              duration: Duration(milliseconds: durMs),
              volume: vol,
              currentTrack: track,
              clearTrack: track == null,
            );
          }
        }

        if (isPlaying || (hasTrack && state.activeDevice == null)) {
          _setActiveDevice(device, autoSwitch: true);
        }
      }
    } catch (e) {
      debugPrint('[AuraConnect] Error parsing datagram: $e');
    }
  }

  void _upsertDevice(AuraConnectDevice device) {
    final list = List<AuraConnectDevice>.from(state.discoveredDevices);
    final idx = list.indexWhere((d) => d.id == device.id || d.ip == device.ip);
    if (idx >= 0) {
      list[idx] = device;
    } else {
      list.add(device);
    }
    state = state.copyWith(discoveredDevices: list);
  }

  void _pruneStaleDevices() {
    final now = DateTime.now();
    final fresh = state.discoveredDevices.where((d) {
      return now.difference(d.lastSeen) < const Duration(seconds: 15);
    }).toList();

    if (fresh.length != state.discoveredDevices.length) {
      final activeStale = state.activeDevice != null &&
          !fresh.any((d) => d.id == state.activeDevice!.id);
      state = state.copyWith(
        discoveredDevices: fresh,
        clearActiveDevice: activeStale,
        isRemoteActive: activeStale ? false : state.isRemoteActive,
      );
    }
  }

  void _setActiveDevice(AuraConnectDevice device, {bool autoSwitch = false}) {
    state = state.copyWith(
      activeDevice: device,
      isRemoteActive: autoSwitch ? true : state.isRemoteActive,
    );
    _startPolling(device);
  }

  void _startPolling(AuraConnectDevice device) {
    _pollTimer?.cancel();
    _pollDeviceState(device);
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      _pollDeviceState(device);
    });
  }

  Future<void> _pollDeviceState(AuraConnectDevice device) async {
    try {
      final uri = Uri.parse('http://${device.ip}:${device.port}/aura-connect/state');
      final req = await _httpClient.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200) return;

      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final devObj = json['device'] as Map<String, dynamic>?;
      final playback = json['playback'] as Map<String, dynamic>?;
      if (playback == null) return;

      final isPlaying = playback['isPlaying'] as bool? ?? false;
      final posMs = (playback['positionMs'] as num?)?.toInt() ?? 0;
      final durMs = (playback['durationMs'] as num?)?.toInt() ?? 0;
      final vol = (playback['volume'] as num?)?.toDouble() ?? 1.0;
      final trackObj = playback['track'] as Map<String, dynamic>?;

      AuraRemoteTrack? track;
      if (trackObj != null) {
        track = AuraRemoteTrack.fromJson(trackObj);
      }

      final updatedDevice = device.copyWith(
        outputRoute: devObj?['outputRoute'] as String? ?? device.outputRoute,
        lastSeen: DateTime.now(),
      );

      _upsertDevice(updatedDevice);

      state = state.copyWith(
        activeDevice: updatedDevice,
        isPlaying: isPlaying,
        position: Duration(milliseconds: posMs),
        duration: Duration(milliseconds: durMs),
        volume: vol,
        currentTrack: track,
        clearTrack: track == null,
      );
    } catch (_) {}
  }

  // Remote transport controls dispatched directly to the active remote phone:

  Future<void> _postAction(Map<String, dynamic> actionData) async {
    final dev = state.activeDevice;
    if (dev == null) return;
    try {
      final uri = Uri.parse('http://${dev.ip}:${dev.port}/aura-connect/action');
      final req = await _httpClient.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(actionData));
      final resp = await req.close();
      await resp.drain();
      // Immediately refresh state
      _pollDeviceState(dev);
    } catch (e) {
      debugPrint('[AuraConnect] Action failed: $e');
    }
  }

  void play() {
    state = state.copyWith(isPlaying: true);
    _postAction({'action': 'play'});
  }

  void pause() {
    state = state.copyWith(isPlaying: false);
    _postAction({'action': 'pause'});
  }

  void togglePlayPause() {
    if (state.isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void seek(Duration position) {
    state = state.copyWith(position: position);
    _postAction({
      'action': 'seek',
      'positionMs': position.inMilliseconds,
    });
  }

  void next() {
    _postAction({'action': 'skip_next'});
  }

  void previous() {
    _postAction({'action': 'skip_previous'});
  }

  void setVolume(double fraction) {
    state = state.copyWith(volume: fraction.clamp(0.0, 1.0));
    _postAction({
      'action': 'volume',
      'value': fraction.clamp(0.0, 1.0),
    });
  }

  void playTrack({
    required String title,
    required String artist,
    String album = '',
    String artworkUrl = '',
    String videoId = '',
    Duration? duration,
  }) {
    state = state.copyWith(
      isRemoteActive: true,
      isPlaying: true,
      currentTrack: AuraRemoteTrack(
        title: title,
        artist: artist,
        album: album,
        artworkUrl: artworkUrl,
        videoId: videoId,
        duration: duration ?? Duration.zero,
      ),
      position: Duration.zero,
      duration: duration ?? Duration.zero,
    );
    _postAction({
      'action': 'play_track',
      'track': {
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'videoId': videoId,
        'durationMs': duration?.inMilliseconds ?? 0,
      },
    });
  }

  /// Transfer playback to local PC speakers.
  void switchToLocal() {
    state = state.copyWith(isRemoteActive: false);
  }

  /// Resume remote control of phone.
  void switchToRemote() {
    if (state.activeDevice != null) {
      state = state.copyWith(isRemoteActive: true);
    }
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _pollTimer?.cancel();
    _tickerTimer?.cancel();
    _udpSocket?.close();
    _httpClient.close(force: true);
    super.dispose();
  }
}
