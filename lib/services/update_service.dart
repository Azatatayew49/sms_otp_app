import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

// Self-hosted in-app updates (no Play Store). The backend serves one APK list per
// app: GET <api>/releases/<app>/version/ (public) and a resumable download.
// This file is identical in every Ak Ulag Flutter app; only the arguments differ.

class UpdateInfo {
  const UpdateInfo({required this.versionCode, required this.versionName, required this.url});

  final int versionCode;
  final String versionName;
  final String url;

  factory UpdateInfo.fromJson(Map<String, dynamic> json, String apiBase) => UpdateInfo(
        versionCode: json['versionCode'] as int,
        versionName: json['versionName'] as String,
        url: _normalizeUrl(json['url'] as String, apiBase),
      );
}

/// The server builds this URL from the incoming request; behind the proxy it can
/// come back as http:// even though we reached it over https. A redirect would
/// drop the Range header, so stay on the scheme the API itself uses.
String _normalizeUrl(String url, String apiBase) {
  if (apiBase.startsWith('https://') && url.startsWith('http://')) {
    return 'https://${url.substring('http://'.length)}';
  }
  return url;
}

class UpdateCheckResult {
  const UpdateCheckResult({required this.currentVersionName, required this.currentBuildNumber, this.update});

  final String currentVersionName;
  final String currentBuildNumber;

  /// Null when the installed build is already current.
  final UpdateInfo? update;
}

/// [apiBase] is the API root, e.g. `http://45.39.230.200/api`; [app] is the
/// release channel: staff, driver, rider or gateway. Uses a bare Dio: the
/// endpoint is public and must not carry a login token or trigger a token refresh.
Future<UpdateCheckResult> checkForUpdate({required String apiBase, required String app}) async {
  final packageInfo = await PackageInfo.fromPlatform();
  final installed = int.tryParse(packageInfo.buildNumber) ?? 0;

  UpdateInfo? latest;
  try {
    final response = await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    )).get<Map<String, dynamic>>('$apiBase/releases/$app/version/');
    latest = UpdateInfo.fromJson(response.data!, apiBase);
  } on DioException catch (e) {
    // 404 just means nothing has been published yet — not a failure.
    if (e.response?.statusCode != 404) rethrow;
  }

  return UpdateCheckResult(
    currentVersionName: packageInfo.version,
    currentBuildNumber: packageInfo.buildNumber,
    update: latest != null && latest.versionCode > installed ? latest : null,
  );
}

const _apkMimeType = 'application/vnd.android.package-archive';
const _filePrefix = 'ak-ulag-update-';

/// Downloads the APK into the app's temp dir and opens Android's package
/// installer on it, so the update stays in-app instead of going through a browser.
///
/// Mobile connections drop often, so the download resumes from where the previous
/// attempt stopped (a Range request) and retries with backoff. The file is named
/// by versionCode so a partial download of an older build is never appended onto
/// a newer one.
Future<void> downloadAndInstall(
  UpdateInfo update, {
  void Function(double progress)? onProgress,
  CancelToken? cancelToken,
}) async {
  final dir = await getTemporaryDirectory();
  final fileName = '$_filePrefix${update.versionCode}.apk';
  final file = File('${dir.path}/$fileName');
  await _deleteOtherUpdateFiles(dir, keep: fileName);

  const maxAttempts = 6;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await _downloadResuming(update.url, file, onProgress: onProgress, cancelToken: cancelToken);
      final result = await OpenFile.open(file.path, type: _apkMimeType);
      if (result.type != ResultType.done) throw Exception(result.message);
      return;
    } catch (e) {
      // A user cancel should stop outright, not be retried like a dropped connection.
      if (e is DioException && CancelToken.isCancel(e)) rethrow;
      // Only network failures are worth retrying; the installer refusing the file won't fix itself.
      if (e is! DioException || attempt == maxAttempts) rethrow;
      await Future.delayed(Duration(seconds: attempt * 2));
    }
  }
}

/// Old half-finished or already-installed downloads would otherwise pile up.
Future<void> _deleteOtherUpdateFiles(Directory dir, {required String keep}) async {
  try {
    await for (final entity in dir.list()) {
      final name = entity.uri.pathSegments.last;
      if (entity is File && name.startsWith(_filePrefix) && name != keep) {
        await entity.delete();
      }
    }
  } catch (_) {
    // Cleanup is best-effort.
  }
}

Future<void> _downloadResuming(
  String url,
  File file, {
  void Function(double progress)? onProgress,
  CancelToken? cancelToken,
}) async {
  final alreadyHave = await file.exists() ? await file.length() : 0;
  final response = await Dio().get<ResponseBody>(
    url,
    cancelToken: cancelToken,
    options: Options(
      headers: alreadyHave > 0 ? {'Range': 'bytes=$alreadyHave-'} : null,
      responseType: ResponseType.stream,
      // A finished file asked to resume past its end gets a 416 — treat that as complete.
      validateStatus: (code) => code != null && (code < 300 || code == 416),
    ),
  );

  if (response.statusCode == 416) {
    onProgress?.call(1);
    return;
  }

  final isResuming = response.statusCode == 206;
  final startOffset = isResuming ? alreadyHave : 0;
  final contentLength = int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
  final total = startOffset + contentLength;
  var received = startOffset;

  final sink = file.openWrite(mode: isResuming ? FileMode.append : FileMode.write);
  try {
    await for (final chunk in response.data!.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0 && onProgress != null) onProgress(received / total);
    }
  } finally {
    await sink.close();
  }

  if (total > 0 && received < total) {
    throw DioException(requestOptions: response.requestOptions, error: 'Download stopped early');
  }
}
