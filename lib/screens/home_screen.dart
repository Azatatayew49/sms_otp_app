import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:another_telephony/telephony.dart';
import '../core/brand.dart';
import '../services/gateway_service.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _status = 'Initializing…';
  bool _running = false;
  // From the server: the name an admin gave this phone and the admin's on/off switch.
  String _name = '';
  String _login = '';
  bool _enabled = false;
  bool _online = false;
  String _sim = '';
  final List<Map<String, dynamic>> _log = [];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _listenService();
    _syncRunning();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!mounted) return;
    setState(() {
      _name = prefs.getString(kPrefDeviceName) ?? '';
      _login = prefs.getString(kPrefLogin) ?? '';
      _enabled = prefs.getBool(kPrefEnabled) ?? false;
      _sim = prefs.getString(kPrefSimLabel) ?? '';
    });
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

    GatewayService.stateStream.listen((data) {
      if (data == null || !mounted) return;
      setState(() {
        _name = data['name'] as String? ?? _name;
        _enabled = data['enabled'] == true;
        _online = data['online'] == true;
        _sim = data['sim'] as String? ?? _sim;
      });
    });

    GatewayService.signedOutStream.listen((data) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginScreen(message: data?['message'] as String?)),
        (_) => false,
      );
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
        _online = false;
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
        title: const Text('Ak Ulag SMS Gateway'),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).pushNamed('/settings');
              _loadSaved();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SwitchCard(name: _name, login: _login, enabled: _enabled, online: _running && _online, sim: _sim),
            const SizedBox(height: 12),
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


/// What the admin decided: is this phone turned on to send login codes?
class _SwitchCard extends StatelessWidget {
  final String name;
  final String login;
  final bool enabled;
  final bool online;
  final String sim;
  const _SwitchCard(
      {required this.name, required this.login, required this.enabled, required this.online, required this.sim});

  @override
  Widget build(BuildContext context) {
    final color = enabled ? Brand.success : Brand.textTertiary;
    return Card(
      color: enabled ? Brand.success.withValues(alpha: 0.08) : Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.smartphone, color: Brand.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name.isEmpty ? 'This phone' : name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
              child: Text(enabled ? 'ON' : 'OFF',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            enabled ? 'Turned on by an admin: this phone sends login codes.'
                    : 'Turned off by an admin: no login codes are sent from this phone until an admin turns it on.',
            style: TextStyle(color: enabled ? Brand.success : Brand.textSecondary),
          ),
          if (sim.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.sim_card_outlined, size: 16, color: Brand.textTertiary),
              const SizedBox(width: 4),
              Text('Sends from: $sim (chosen by an admin)',
                  style: const TextStyle(fontSize: 12, color: Brand.textSecondary)),
            ]),
          ],
          const SizedBox(height: 4),
          Text(
            '${login.isEmpty ? '' : 'Signed in as $login · '}${online ? 'connected' : 'not connected'}'
            '${enabled || !online ? '' : ' · waiting for an admin'}',
            style: const TextStyle(fontSize: 12, color: Brand.textTertiary),
          ),
        ]),
      ),
    );
  }
}
