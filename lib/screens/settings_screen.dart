import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/update_tile.dart';

const _kPrefUrl = 'gateway_url';
const _kPrefToken = 'gateway_token';
const _kPrefName = 'gateway_device_name';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _urlCtrl.text = prefs.getString(_kPrefUrl) ?? 'http://45.39.230.200';
    _tokenCtrl.text = prefs.getString(_kPrefToken) ?? '';
    _nameCtrl.text = prefs.getString(_kPrefName) ?? '';
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefUrl, _urlCtrl.text.trim());
    await prefs.setString(_kPrefToken, _tokenCtrl.text.trim());
    await prefs.setString(_kPrefName, _nameCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved.')),
      );
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Phone name',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  hintText: "e.g. Azat's phone",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Must be unique. Admins see this name in the staff app.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              const Text(
                'Backend URL',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  hintText: 'http://45.39.230.200',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('45.39.230.200'),
                    onPressed: () => _urlCtrl.text = 'http://45.39.230.200',
                  ),
                  ActionChip(
                    label: const Text('localhost:8000'),
                    onPressed: () => _urlCtrl.text = 'http://localhost:8000',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Gateway Token',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _tokenCtrl,
                decoration: const InputDecoration(
                  hintText: 'secret token from backend .env',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              Text(
                'Must match SMS_GATEWAY_TOKEN in the backend .env file.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Save & Reconnect'),
              ),
              const Divider(height: 40),
              // The gateway URL is the server root; the release API lives under /api.
              UpdateTile(
                  apiBase: () => '${_urlCtrl.text.trim()}/api', app: 'gateway'),
            ],
          ),
        ),
      ),
    );
  }
}
