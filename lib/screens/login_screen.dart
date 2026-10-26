import 'package:flutter/material.dart';

import '../core/brand.dart';
import '../services/account.dart';
import '../services/gateway_service.dart';

/// Login and password come from an admin (staff app → More → SMS phone accounts).
class LoginScreen extends StatefulWidget {
  final String? message;
  const LoginScreen({super.key, this.message});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _url = TextEditingController(text: kDefaultUrl);
  bool _busy = false;
  bool _hide = true;
  bool _showServer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.message;
    Account.login().then((l) => _login.text = l);
    Account.serverUrl().then((u) => _url.text = u);
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_login.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter the login and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Account.signIn(_url.text, _login.text, _password.text);
      await GatewayService.start();
      if (mounted) Navigator.of(context).pushReplacementNamed('/');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.sms_outlined, size: 56, color: Brand.amber),
                const SizedBox(height: 12),
                const Text('SMS OTP Gateway',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Sign in with the login an admin gave you.',
                    textAlign: TextAlign.center, style: TextStyle(color: Brand.textTertiary)),
                const SizedBox(height: 28),
                TextField(
                  controller: _login,
                  decoration: const InputDecoration(labelText: 'Login', prefixIcon: Icon(Icons.person_outline)),
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: _hide,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                  onSubmitted: (_) => _signIn(),
                ),
                if (_showServer) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Server', prefixIcon: Icon(Icons.dns_outlined)),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: const TextStyle(color: Brand.error)),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 8),
                if (!_showServer)
                  TextButton(
                    onPressed: () => setState(() => _showServer = true),
                    child: const Text('Change server'),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
