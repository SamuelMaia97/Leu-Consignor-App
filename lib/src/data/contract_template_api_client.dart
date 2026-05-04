import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import 'contract_template_payload.dart';

class ContractTemplateApiClient {
  ContractTemplateApiClient({
    required AppSettings settings,
    required String bearerToken,
  })  : _settings = settings,
        _bearerToken = bearerToken,
        _dio = Dio(
          BaseOptions(
            baseUrl: settings.apiBaseUrl,
            headers: bearerToken.trim().isEmpty
                ? const {}
                : {'Authorization': 'Bearer $bearerToken'},
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(minutes: 2),
            sendTimeout: const Duration(minutes: 2),
          ),
        );

  static const String renderPdfPath = '/api/consignor-contracts/render-pdf';

  final AppSettings _settings;
  final String _bearerToken;
  final Dio _dio;

  Future<Uint8List> renderPdf(ContractRenderPayload payload) async {
    _ensureConfigured();

    try {
      final response = await _dio.post<List<int>>(
        renderPdfPath,
        data: payload.toJson(),
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {'Accept': 'application/pdf'},
        ),
      );

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('The contract renderer returned an empty PDF.');
      }

      return Uint8List.fromList(bytes);
    } on DioException catch (error) {
      throw Exception(_friendlyDioError(error));
    }
  }

  void _ensureConfigured() {
    final baseUrl = _settings.apiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw Exception('API base URL is empty.');
    }

    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme) {
      throw Exception('API base URL must include an https:// scheme.');
    }

    final localDevelopmentHost = uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1';
    if (uri.scheme != 'https' && (kReleaseMode || !localDevelopmentHost)) {
      throw Exception('API base URL must use HTTPS.');
    }

    if (_bearerToken.trim().isEmpty) {
      throw Exception('No bearer token is set. Sign in with Microsoft first.');
    }
  }

  String _friendlyDioError(DioException error) {
    final status = error.response?.statusCode;
    final responseData = error.response?.data;
    final body = responseData is List<int>
        ? String.fromCharCodes(responseData)
        : responseData?.toString();

    if (status == 401 || status == 403) {
      return 'Authentication failed ($status). Sign in again or verify the token scope.';
    }
    if (status != null) {
      return 'Template PDF rendering failed with HTTP $status${body == null ? '' : ': $body'}';
    }
    if (error.type == DioExceptionType.connectionError) {
      return 'Could not reach the contract rendering API. Check VPN, DNS, certificates, and API host availability.';
    }
    return error.message ?? error.toString();
  }
}
