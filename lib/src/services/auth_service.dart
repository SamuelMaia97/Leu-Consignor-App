import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_settings.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService(this.settings);

  final AppSettings settings;

  static DateTime? getAccessTokenExpiryUtc(String token) {
    final payload = _decodeJwtPayload(token);
    final exp = payload?['exp'];

    if (exp is int) {
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    }

    if (exp is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
    }

    if (exp is String) {
      final parsed = int.tryParse(exp);
      if (parsed != null) {
        return DateTime.fromMillisecondsSinceEpoch(
          parsed * 1000,
          isUtc: true,
        );
      }
    }

    return null;
  }

  static bool hasUsableAccessToken(
    String token, {
    Duration clockSkew = const Duration(minutes: 1),
  }) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    return !isTokenExpired(trimmed, clockSkew: clockSkew);
  }

  static bool isTokenExpired(
    String token, {
    Duration clockSkew = const Duration(minutes: 1),
  }) {
    final expiryUtc = getAccessTokenExpiryUtc(token);
    if (expiryUtc == null) {
      return false;
    }

    final nowUtc = DateTime.now().toUtc().add(clockSkew);
    return !expiryUtc.isAfter(nowUtc);
  }

  static bool isTokenExpiringSoon(
    String token, {
    Duration threshold = const Duration(minutes: 10),
    Duration clockSkew = const Duration(minutes: 1),
  }) {
    final expiryUtc = getAccessTokenExpiryUtc(token);
    if (expiryUtc == null) {
      return false;
    }

    final nowUtc = DateTime.now().toUtc().add(clockSkew);
    if (!expiryUtc.isAfter(nowUtc)) {
      return false;
    }

    return expiryUtc.isBefore(nowUtc.add(threshold));
  }

  Future<String> signInWithMicrosoft() async {
    if (kIsWeb) {
      throw AuthException(
        'Microsoft sign-in in this project is currently supported for desktop/mobile builds, not Flutter Web. '
        'Use `flutter run -d windows` or add a backend proxy / web auth callback for browser use.',
      );
    }

    final tenant = settings.oauthTenantId.trim();
    final clientId = settings.oauthClientId.trim();
    final scope = settings.oauthScope.trim();
    final redirectUri = settings.oauthRedirectUri.trim();

    if ([tenant, clientId, scope, redirectUri].any((e) => e.isEmpty)) {
      throw AuthException(
        'OAuth settings are incomplete. Fill in tenant, client ID, scope, and redirect URI.',
      );
    }

    final redirect = Uri.parse(redirectUri);
    if (!redirect.isScheme('http') &&
        (redirect.host != '127.0.0.1' && redirect.host != 'localhost')) {
      throw AuthException(
        'This desktop sign-in flow requires a loopback redirect URI like http://127.0.0.1:12345.',
      );
    }

    final codeVerifier = _randomString(64);
    final codeChallenge = base64Url
        .encode(sha256.convert(ascii.encode(codeVerifier)).bytes)
        .replaceAll('=', '');
    final state = _randomString(32);

    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      redirect.port,
    );

    try {
      final authorizeUri = Uri.https(
        'login.microsoftonline.com',
        '/$tenant/oauth2/v2.0/authorize',
        {
          'client_id': clientId,
          'response_type': 'code',
          'redirect_uri': redirectUri,
          'response_mode': 'query',
          'scope': scope,
          'state': state,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
          'prompt': 'select_account',
        },
      );

      final launched = await launchUrl(
        authorizeUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw AuthException(
          'Could not open the Microsoft sign-in page in your browser.',
        );
      }

      final request = await server.first.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw AuthException(
          'Timed out waiting for Microsoft sign-in to complete.',
        ),
      );

      final params = request.uri.queryParameters;
      final returnedState = params['state'];
      final code = params['code'];
      final error = params['error'];
      final errorDescription = params['error_description'];

      request.response.headers.contentType = ContentType.html;

      if (error != null) {
        request.response.write(
          '<html><body><h2>Sign-in failed</h2><p>${htmlEscape.convert(errorDescription ?? error)}</p></body></html>',
        );
        await request.response.close();
        throw AuthException(
          'Microsoft sign-in failed: ${errorDescription ?? error}',
        );
      }

      if (returnedState != state || code == null || code.isEmpty) {
        request.response.write(
          '<html><body><h2>Sign-in failed</h2><p>Invalid authorization response.</p></body></html>',
        );
        await request.response.close();
        throw AuthException(
          'Invalid authorization response received from Microsoft sign-in.',
        );
      }

      request.response.write(
        '<!doctype html><html><head><meta charset="utf-8"><title>Sign-in complete</title></head>'
        '<body style="font-family:Segoe UI,Arial,sans-serif;padding:24px;line-height:1.45;">'
        '<h2>Sign-in complete</h2>'
        '<p>You can close this browser tab and return to the Leu Consignor App.</p>'
        '<script>'
        'setTimeout(function(){window.close();}, 750);'
        '</script>'
        '</body></html>',
      );
      await request.response.close();

      final dio = Dio();
      final tokenUri = Uri.https(
        'login.microsoftonline.com',
        '/$tenant/oauth2/v2.0/token',
      );

      final response = await dio.postUri(
        tokenUri,
        data: {
          'client_id': clientId,
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri,
          'code_verifier': codeVerifier,
          'scope': scope,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final token = (response.data as Map)['access_token']?.toString() ?? '';
      if (token.isEmpty) {
        throw AuthException(
          'Microsoft sign-in completed, but no access token was returned.',
        );
      }

      return token;
    } on DioException catch (e) {
      final details = e.response?.data?.toString() ?? e.message ?? e.toString();
      throw AuthException('Token exchange failed: $details');
    } finally {
      await server.close(force: true);
    }
  }

  static Map<String, dynamic>? _decodeJwtPayload(String token) {
    final parts = token.trim().split('.');
    if (parts.length < 2) {
      return null;
    }

    try {
      final normalized = _normalizeBase64(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded);

      if (json is Map<String, dynamic>) {
        return json;
      }

      if (json is Map) {
        return json.cast<String, dynamic>();
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static String _normalizeBase64(String value) {
    final remainder = value.length % 4;
    if (remainder == 0) {
      return value;
    }

    return value.padRight(value.length + (4 - remainder), '=');
  }

  String _randomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }
}
