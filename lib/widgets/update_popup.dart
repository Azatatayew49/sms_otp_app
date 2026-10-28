import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/update_service.dart';

// "A new version is available" pop-up, shown as often as admins chose in the staff
// app (every launch, once a day, once a week, never). Identical in every Ak Ulag app.

const _kLastShown = 'update_popup_last_shown';
bool _shownThisLaunch = false;

/// Call once the first screen is up. Quietly does nothing when offline or up to date.
Future<void> maybeShowUpdatePopup(BuildContext context, {required String apiBase, required String app}) async {
  if (_shownThisLaunch) return;
  UpdateInfo? update;
  try {
    update = (await checkForUpdate(apiBase: apiBase, app: app)).update;
  } catch (_) {
    return;
  }
  if (update == null || update.popup == 'never' || !context.mounted) return;
  final prefs = await SharedPreferences.getInstance();
  final last = DateTime.tryParse(prefs.getString(_kLastShown) ?? '');
  final wait = switch (update.popup) {
    'weekly' => const Duration(days: 7),
    'daily' => const Duration(days: 1),
    _ => Duration.zero, // every_launch
  };
  if (last != null && DateTime.now().difference(last) < wait) return;
  _shownThisLaunch = true;
  await prefs.setString(_kLastShown, DateTime.now().toIso8601String());
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(update: update!),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo update;
  const _UpdateDialog({required this.update});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;
  CancelToken? _cancel;

  Future<void> _install() async {
    final token = CancelToken();
    setState(() { _downloading = true; _progress = 0; _error = null; _cancel = token; });
    try {
      await downloadAndInstall(widget.update, cancelToken: token, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      if (e is DioException && CancelToken.isCancel(e)) {
        setState(() => _downloading = false);
      } else {
        setState(() { _downloading = false; _error = 'Download failed. Check the internet and try again.'; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.system_update, size: 36),
      title: const Text('Update available'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Version ${widget.update.versionName} is ready. Update now to get the latest fixes.'),
        if (_downloading) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ]),
      actions: [
        TextButton(
          onPressed: () {
            _cancel?.cancel();
            Navigator.of(context).pop();
          },
          child: Text(_downloading ? 'Cancel' : 'Later'),
        ),
        if (!_downloading)
          FilledButton(onPressed: _install, child: const Text('Update')),
      ],
    );
  }
}
