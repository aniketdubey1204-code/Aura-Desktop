import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/dio_factory.dart';
import '../../core/network/external_launcher.dart';

/// Data returned by Google OAuth Device Code endpoint.
class GoogleDeviceCode {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int expiresIn;
  final int interval;

  const GoogleDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.expiresIn,
    required this.interval,
  });

  factory GoogleDeviceCode.fromJson(Map<String, dynamic> json) {
    return GoogleDeviceCode(
      deviceCode: json['device_code'] as String? ?? '',
      userCode: json['user_code'] as String? ?? '',
      verificationUrl: json['verification_url'] as String? ?? 'https://www.google.com/device',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 1800,
      interval: (json['interval'] as num?)?.toInt() ?? 5,
    );
  }
}

/// Tokens returned upon approval.
class GoogleAuthTokens {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final String name;
  final String email;
  final String picture;

  const GoogleAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    this.name = '',
    this.email = '',
    this.picture = '',
  });
}

/// Handles Google OAuth 2.0 Device Authorization Grant flow for YouTube.
/// Opens the external browser to https://www.google.com/device and polls for approval.
class GoogleDeviceAuth {
  GoogleDeviceAuth._();

  static const _clientId =
      '861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com';
  static const _clientSecret = 'SboVhoG9s0rNafixCSGGKXAT';
  static const _deviceEndpoint = 'https://oauth2.googleapis.com/device/code';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _userInfoEndpoint = 'https://www.googleapis.com/oauth2/v3/userinfo';

  static const _scopes =
      'http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email';

  static final Dio _dio = DioFactory.create();

  /// Step 1: Request a user code and device code from Google.
  static Future<GoogleDeviceCode> requestDeviceCode() async {
    final response = await _dio.post(
      _deviceEndpoint,
      data: {
        'client_id': _clientId,
        'scope': _scopes,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
      ),
    );

    final data = response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : jsonDecode(response.data.toString()) as Map<String, dynamic>;

    return GoogleDeviceCode.fromJson(data);
  }

  /// Launch external browser to the Google device activation page.
  static Future<bool> launchActivationPage(String url) async {
    return launchExternalBrowser(url);
  }

  /// Step 2: Poll Google token endpoint until user approves or code expires.
  static Future<GoogleAuthTokens?> pollForTokens({
    required String deviceCode,
    int interval = 5,
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final startTime = DateTime.now();
    final delay = Duration(seconds: interval < 3 ? 3 : interval);

    while (DateTime.now().difference(startTime) < timeout) {
      await Future<void>.delayed(delay);
      try {
        final response = await _dio.post(
          _tokenEndpoint,
          data: {
            'client_id': _clientId,
            'client_secret': _clientSecret,
            'device_code': deviceCode,
            'grant_type': 'http://oauth.net/grant_type/device/1.0',
          },
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            responseType: ResponseType.json,
            validateStatus: (status) => true,
          ),
        );

        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : (response.data is String
                ? jsonDecode(response.data as String) as Map<String, dynamic>
                : <String, dynamic>{});

        final error = data['error'] as String?;
        if (error != null) {
          if (error == 'authorization_pending') {
            // User hasn't finished typing the code yet; continue polling.
            continue;
          } else if (error == 'slow_down') {
            await Future<void>.delayed(const Duration(seconds: 5));
            continue;
          } else {
            // access_denied, expired_token, etc.
            if (kDebugMode) debugPrint('GoogleDeviceAuth poll error: $error');
            return null;
          }
        }

        final accessToken = data['access_token'] as String?;
        final refreshToken = data['refresh_token'] as String? ?? '';
        final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;

        if (accessToken != null && accessToken.isNotEmpty) {
          // Fetch profile info using access token
          final user = await _fetchUserInfo(accessToken);
          return GoogleAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            name: user.name,
            email: user.email,
            picture: user.picture,
          );
        }
      } catch (e) {
        if (kDebugMode) debugPrint('GoogleDeviceAuth poll exception: $e');
      }
    }
    return null;
  }

  /// Refresh an expired access token using the stored refresh token.
  static Future<GoogleAuthTokens?> refreshToken(String refreshToken) async {
    try {
      final response = await _dio.post(
        _tokenEndpoint,
        data: {
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.json,
        ),
      );

      final data = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : jsonDecode(response.data.toString()) as Map<String, dynamic>;

      final accessToken = data['access_token'] as String?;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;

      if (accessToken != null && accessToken.isNotEmpty) {
        final user = await _fetchUserInfo(accessToken);
        return GoogleAuthTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresIn: expiresIn,
          name: user.name,
          email: user.email,
          picture: user.picture,
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<({String name, String email, String picture})> _fetchUserInfo(
      String accessToken) async {
    try {
      final res = await _dio.get(
        _userInfoEndpoint,
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          responseType: ResponseType.json,
        ),
      );
      final data = res.data is Map<String, dynamic>
          ? res.data as Map<String, dynamic>
          : jsonDecode(res.data.toString()) as Map<String, dynamic>;
      return (
        name: data['name'] as String? ?? '',
        email: data['email'] as String? ?? '',
        picture: data['picture'] as String? ?? '',
      );
    } catch (_) {
      return (name: '', email: '', picture: '');
    }
  }
}
