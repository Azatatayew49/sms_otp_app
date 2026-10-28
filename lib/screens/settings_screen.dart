import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/brand.dart';
import '../services/account.dart';
import '../services/gateway_service.dart';
import '../widgets/update_tile.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _url = kDefaultUrl;
  String _login = '';
  String _name = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!mounted) return;
    setState(() {
      _url = prefs.getString(kPrefUrl) ?? kDefaultUrl;
      _login = prefs.getString(kPrefLogin) ?? '';
      _name = prefs.getString(kPrefDeviceName) ?? '';
    });
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('This phone stops sending login codes until someone signs in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    await Account.signOut();
    if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String label, String value) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: Brand.textTertiary),
          title: Text(label, style: const TextStyle(fontSize: 12, color: Brand.textTertiary)),
          subtitle: Text(value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 16, color: Brand.text, fontWeight: FontWeight.w600)),
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          row(Icons.person_outline, 'Signed in as', _login),
          row(Icons.smartphone, 'Phone name (set by an admin)', _name),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Brand.error,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const Divider(height: 40),
          // The gateway URL is the server root; the release API lives under /api.
          UpdateTile(apiBase: () => '$_url/api', app: 'gateway'),
        ]),
      ),
    );
  }
}
