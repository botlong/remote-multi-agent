// ignore_for_file: unintended_html_in_doc_comment

/// HTTP client for git operations via the QQBot server.
///
/// Endpoints:
///   GET  /git/status?path=<dir>         → git status output
///   GET  /git/diff?path=<dir>           → git diff output
///   POST /git/commit  {path, message}   → git add -A && git commit
///   POST /git/pull    {path}            → git pull
///   POST /git/push    {path}            → git push
///
/// The QQBot server URL is configured separately from the OpenCode server URL.
library;

import 'package:dio/dio.dart';

class GitClient {
  GitClient({required Uri baseUrl, String? bearerToken})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl.toString().replaceAll(RegExp(r'/$'), ''),
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 60),
            sendTimeout: const Duration(seconds: 30),
            headers: {
              'Accept': 'application/json',
              if (bearerToken != null && bearerToken.isNotEmpty)
                'Authorization': 'Bearer $bearerToken',
            },
          ),
        );

  final Dio _dio;

  /// Returns raw `git status --porcelain` output.
  Future<String> status(String path) async {
    final res = await _dio.get<dynamic>(
      '/git/status',
      queryParameters: {'path': path},
    );
    return _extractOutput(res.data);
  }

  /// Returns raw `git diff` output.
  Future<String> diff(String path) async {
    final res = await _dio.get<dynamic>(
      '/git/diff',
      queryParameters: {'path': path},
    );
    return _extractOutput(res.data);
  }

  /// Commits all changes with the given message.
  Future<String> commit(String path, String message) async {
    final res = await _dio.post<dynamic>(
      '/git/commit',
      data: {'path': path, 'message': message},
    );
    return _extractOutput(res.data);
  }

  /// Pulls from remote.
  Future<String> pull(String path) async {
    final res = await _dio.post<dynamic>(
      '/git/pull',
      data: {'path': path},
    );
    return _extractOutput(res.data);
  }

  /// Pushes to remote.
  Future<String> push(String path) async {
    final res = await _dio.post<dynamic>(
      '/git/push',
      data: {'path': path},
    );
    return _extractOutput(res.data);
  }

  /// Extracts the output string from the response.
  /// Supports both `{output: "..."}` and plain string responses.
  String _extractOutput(dynamic data) {
    if (data is String) return data;
    if (data is Map) {
      return (data['output'] as String?) ??
          (data['stdout'] as String?) ??
          (data['message'] as String?) ??
          data.toString();
    }
    return data?.toString() ?? '';
  }

  void close() => _dio.close(force: true);
}
