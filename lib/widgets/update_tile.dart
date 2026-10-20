import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/update_service.dart';

/// Settings block: installed version, "check for update", and — when the server has
/// a newer build — a download-and-install button with progress. Identical in every
/// Ak Ulag app; [apiBase] and [app] say where to look.
class UpdateTile extends StatefulWidget {
  /// Read when checking, so a host that was changed in settings is picked up.
  final String Function() apiBase;

  /// Release channel: staff, driver, rider or gateway.
  final String app;
  const UpdateTile({super.key, required this.apiBase, required this.app});

  @override
  State<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<UpdateTile> {
  String? _installed;
  UpdateInfo? _update;
  bool _checking = false;
  String? _error;
  bool _upToDate = false;
  bool _downloading = false;
  double _progress = 0;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _installed = '${i.version} (${i.buildNumber})');
    });
    _check();
  }

  String _describe(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      return code != null ? 'HTTP $code' : (e.message ?? e.type.name);
    }
    return e.toString();
  }

  Future<void> _check() async {
    setState(() { _checking = true; _error = null; _upToDate = false; });
    try {
      final r = await checkForUpdate(apiBase: widget.apiBase(), app: widget.app);
      if (mounted) setState(() { _update = r.update; _upToDate = r.update == null; });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not check: ${_describe(e)}');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _install(UpdateInfo update) async {
    final messenger = ScaffoldMessenger.of(context);
    final token = CancelToken();
    setState(() { _downloading = true; _progress = 0; _cancel = token; });
    try {
      await downloadAndInstall(
        update,
        cancelToken: token,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } catch (e) {
      if (!(e is DioException && CancelToken.isCancel(e))) {
        messenger.showSnackBar(SnackBar(content: Text('Download failed: ${_describe(e)}')));
      }
    } finally {
      if (mounted) setState(() { _downloading = false; _cancel = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = _update;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
        leading: const Icon(Icons.system_update),
        title: const Text('App version'),
        subtitle: Text(_installed == null
            ? '…'
            : _upToDate ? '$_installed · up to date' : _installed!),
        trailing: IconButton(
          tooltip: 'Check for update',
          onPressed: _checking || _downloading ? null : _check,
          icon: _checking
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      if (update != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_downloading) ...[
              Row(children: [
                Expanded(child: LinearProgressIndicator(value: _progress > 0 ? _progress : null)),
                IconButton(
                  icon: const Icon(Icons.stop_circle_outlined),
                  tooltip: 'Stop download',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _cancel?.cancel(),
                ),
              ]),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: _downloading ? null : () => _install(update),
              icon: const Icon(Icons.download),
              label: Text('Download and install ${update.versionName}'),
            ),
          ]),
        ),
    ]);
  }
}
