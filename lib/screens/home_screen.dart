import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:another_telephony/telephony.dart';
import '../services/gateway_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _status = 'Initializing…';
  bool _running = false;
  final List<Map<String, dynamic>> _log = [];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _listenService();
    _syncRunning();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askNameOnFirstRun());
  }

  /// A fresh install only needs a phone name; take the user straight to it.
  Future<void> _askNameOnFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getString(kPrefDeviceName) ?? '').trim().isNotEmpty) return;
    if (!mounted) return;
    await Navigator.of(context).pushNamed('/settings');
    if (_running) GatewayService.start();
  }

  Future<void> _checkPermissions() async {
    final telephony = Telephony.instance;
    final granted = await telephony.requestPhoneAndSmsPermissions ?? false;
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS permission is required to send messages.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _syncRunning() async {
    final running = await GatewayService.isRunning();
    if (mounted) setState(() => _running = running);
  }

  void _listenService() {
    GatewayService.statusStream.listen((data) {
      if (data == null) return;
      if (mounted) {
        setState(() => _status = data['message'] as String? ?? '');
      }
    });

    GatewayService.smsSentStream.listen((data) {
      if (data == null) return;
      if (mounted) {
        setState(() {
          _log.insert(0, data);
          if (_log.length > 50) _log.removeLast();
        });
      }
    });
  }

  Future<void> _toggle() async {
    if (_running) {
      await GatewayService.stop();
      setState(() {
        _running = false;
        _status = 'Stopped.';
      });
    } else {
      await GatewayService.start();
      setState(() {
        _running = true;
        _status = 'Starting…';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS OTP Gateway'),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).pushNamed('/settings');
              // Reconnect after settings change
              if (_running) GatewayService.start();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
            Card(
              color: _running ? Colors.green.shade50 : Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _running ? Icons.wifi : Icons.wifi_off,
                      color: _running ? Colors.green : Colors.grey,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _running ? 'Gateway Running' : 'Gateway Stopped',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _running
                                  ? Colors.green.shade700
                                  : Colors.grey,
                            ),
                          ),
                          Text(
                            _status,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _toggle,
              icon: Icon(_running ? Icons.stop : Icons.play_arrow),
              label: Text(_running ? 'Stop Gateway' : 'Start Gateway'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _running ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'SMS Log',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            Expanded(
              child: _log.isEmpty
                  ? Center(
                      child: Text(
                        'No SMS sent yet.',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _log.length,
                      itemBuilder: (_, i) {
                        final entry = _log[i];
                        final ok = entry['ok'] as bool? ?? false;
                        final time = entry['time'] as String? ?? '';
                        final phone = entry['phone'] as String? ?? '';
                        final msg = entry['message'] as String? ?? '';
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            ok ? Icons.check_circle : Icons.error,
                            color: ok ? Colors.green : Colors.red,
                            size: 18,
                          ),
                          title:
                              Text(phone, style: const TextStyle(fontSize: 13)),
                          subtitle:
                              Text(msg, style: const TextStyle(fontSize: 11)),
                          trailing: Text(
                            time.length > 18 ? time.substring(11, 19) : time,
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
