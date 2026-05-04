import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _kPrefUrl = 'gateway_url';
const _kPrefToken = 'gateway_token';
const _notifChannelId = 'sms_gateway_service';
const _notifId = 1;

/// Called by [FlutterBackgroundService] in a separate isolate.
@pragma('vm:entry-point')
Future<void> onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  // Show persistent foreground notification
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'SMS Gateway',
      content: 'Connecting…',
    );
  }

  WebSocketChannel? channel;
  Timer? reconnectTimer;
  bool running = true;

  Future<void> updateNotif(String text) async {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'SMS Gateway',
        content: text,
      );
    }
    service.invoke('status', {'message': text});
  }

  Future<void> sendSms(String phone, String message) async {
    final telephony = Telephony.instance;
    final time = DateTime.now().toIso8601String();
    try {
      telephony.sendSms(
        to: phone,
        message: message,
        statusListener: (SendStatus status) async {
          // SENT  = accepted by carrier, DELIVERED = confirmed on device.
          // Both are success; only log DELIVERED to avoid duplicate entries.
          if (status == SendStatus.SENT) return;
          final ok = status == SendStatus.DELIVERED;
          final entry = {
            'phone': phone,
            'message': message,
            'time': time,
            'ok': ok,
            if (!ok) 'error': 'SendStatus: $status',
          };
          service.invoke('sms_sent', entry);
          await updateNotif(
            ok ? 'Last SMS to $phone' : 'SMS failed ($status) to $phone',
          );
        },
      );
    } catch (e) {
      final entry = {
        'phone': phone,
        'message': message,
        'time': time,
        'ok': false,
        'error': e.toString(),
      };
      service.invoke('sms_sent', entry);
      await updateNotif('SMS exception: $e');
    }
  }

  Future<void> connect() async {
    final url = prefs.getString(_kPrefUrl) ?? '';
    final token = prefs.getString(_kPrefToken) ?? '';
    if (url.isEmpty || token.isEmpty) {
      await updateNotif('Not configured. Open app settings.');
      return;
    }

    try {
      await updateNotif('Connecting…');
      final wsUrl = url.replaceFirst(RegExp(r'^http'), 'ws');
      final uri = Uri.parse('$wsUrl/ws/sms-gateway/?gw_token=$token');
      channel = WebSocketChannel.connect(uri);
      await channel!.ready;
      await updateNotif('Connected ✓');

      channel!.stream.listen(
        (raw) {
          try {
            final data = jsonDecode(raw as String) as Map<String, dynamic>;
            if (data['type'] == 'send_sms') {
              sendSms(
                data['phone'] as String,
                data['message'] as String,
              );
            }
          } catch (_) {}
        },
        onDone: () async {
          await updateNotif('Disconnected. Reconnecting…');
          if (running) {
            reconnectTimer = Timer(const Duration(seconds: 5), connect);
          }
        },
        onError: (_) async {
          await updateNotif('Error. Reconnecting…');
          if (running) {
            reconnectTimer = Timer(const Duration(seconds: 5), connect);
          }
        },
      );
    } catch (e) {
      await updateNotif('Connection failed. Retrying…');
      if (running) {
        reconnectTimer = Timer(const Duration(seconds: 5), connect);
      }
    }
  }

  // Listen for commands from UI
  service.on('stop').listen((_) {
    running = false;
    reconnectTimer?.cancel();
    channel?.sink.close();
    service.stopSelf();
  });

  service.on('reconnect').listen((_) async {
    reconnectTimer?.cancel();
    channel?.sink.close();
    await connect();
  });

  await connect();
}

class GatewayService {
  GatewayService._();

  static final _service = FlutterBackgroundService();

  static Future<void> initialize() async {
    // Notification channel for foreground service
    const androidChannel = AndroidNotificationChannel(
      _notifChannelId,
      'SMS Gateway Service',
      description: 'Keeps the SMS OTP gateway running',
      importance: Importance.low,
    );
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onServiceStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: _notifChannelId,
        initialNotificationTitle: 'SMS Gateway',
        initialNotificationContent: 'Starting…',
        foregroundServiceNotificationId: _notifId,
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  static Future<void> start() async {
    final running = await _service.isRunning();
    if (!running) {
      await _service.startService();
    } else {
      _service.invoke('reconnect');
    }
  }

  static Future<void> stop() async {
    _service.invoke('stop');
  }

  static Future<bool> isRunning() => _service.isRunning();

  /// Stream of status messages from the service.
  static Stream<Map<String, dynamic>?> get statusStream =>
      _service.on('status');

  /// Stream of SMS log entries from the service.
  static Stream<Map<String, dynamic>?> get smsSentStream =>
      _service.on('sms_sent');
}
