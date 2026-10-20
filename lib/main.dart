import 'package:flutter/material.dart';
import 'core/brand.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/gateway_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GatewayService.initialize();
  runApp(const SmsOtpApp());
}

class SmsOtpApp extends StatelessWidget {
  const SmsOtpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMS OTP Gateway',
      debugShowCheckedModeBanner: false,
      theme: buildBrandTheme(),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}
