import 'package:flutter/material.dart';
import 'core/brand.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'services/account.dart';
import 'services/gateway_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GatewayService.initialize();
  final signedIn = await Account.signedIn();
  // Nothing to run until someone signs in.
  if (!signedIn) await GatewayService.stop();
  runApp(SmsOtpApp(signedIn: signedIn));
}

class SmsOtpApp extends StatelessWidget {
  final bool signedIn;
  const SmsOtpApp({super.key, required this.signedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMS OTP Gateway',
      debugShowCheckedModeBanner: false,
      theme: buildBrandTheme(),
      initialRoute: signedIn ? '/' : '/login',
      routes: {
        '/': (_) => const HomeScreen(),
        '/login': (_) => const LoginScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}
