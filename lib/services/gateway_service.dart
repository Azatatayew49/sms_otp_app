import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _kPrefUrl = 'gateway_url';
const _kPrefToken = 'gateway_token';
const _kPrefDeviceId = 'gateway_device_id';
const kPrefDeviceName = 'gateway_device_name';
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
  Timer? heartbeatTimer;
  bool running = true;
  // Bumped on every (re)connect so callbacks of an old socket are ignored.
  int generation = 0;
  Future<void> Function()? connectRef;
  DateTime lastPong = DateTime.now();

  Future<void> updateNotif(String text) async {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'SMS Gateway',
        content: text,
      );
    }
    service.invoke('status', {'message': text});
  }

  void sendAck(int? smsId, String status, [String? error]) {
    if (smsId == null) return;
    try {
      channel?.sink.add(jsonEncode({
        'type': 'sms_status',
        'sms_id': smsId,
        'status': status,
        if (error != null) 'error': error,
      }));
    } catch (_) {}
  }

  Future<void> sendSms(int? smsId, String phone, String message) async {
    final telephony = Telephony.instance;
    final time = DateTime.now().toIso8601String();

    void logLocal(bool ok, [String? error]) {
      service.invoke('sms_sent', {
        'phone': phone,
        'message': message,
        'time': time,
        'ok': ok,
        if (error != null) 'error': error,
      });
    }

    try {
      telephony.sendSms(
        to: phone,
        message: message,
        statusListener: (SendStatus status) async {
          if (status == SendStatus.SENT) {
            // Handed to the carrier: that is success for monitoring purposes.
            sendAck(smsId, 'sent');
            logLocal(true);
            await updateNotif('Last SMS to $phone');
          } else if (status == SendStatus.DELIVERED) {
            sendAck(smsId, 'delivered');
          }
        },
      );
    } catch (e) {
      sendAck(smsId, 'failed', e.toString());
      logLocal(false, e.toString());
      await updateNotif('SMS exception: $e');
    }
  }

  void scheduleReconnect(int gen) {
    if (!running || gen != generation) return;
    heartbeatTimer?.cancel();
    reconnectTimer?.cancel();
    reconnectTimer = Timer(const Duration(seconds: 5), () => connectRef?.call());
  }

  Future<void> connect() async {
    final gen = ++generation;
    reconnectTimer?.cancel();
    heartbeatTimer?.cancel();
    final url = prefs.getString(_kPrefUrl) ?? '';
    final token = prefs.getString(_kPrefToken) ?? '';
    final name = (prefs.getString(kPrefDeviceName) ?? '').trim();
    var deviceId = prefs.getString(_kPrefDeviceId) ?? '';
    if (deviceId.isEmpty) {
      final r = Random.secure();
      deviceId = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
      await prefs.setString(_kPrefDeviceId, deviceId);
    }
    if (url.isEmpty || token.isEmpty || name.isEmpty) {
      await updateNotif('Not configured. Open app settings (name, URL, token).');
      return;
    }

    try {
      await updateNotif('Connecting…');
      final base = Uri.parse(url.replaceFirst(RegExp(r'^http'), 'ws'));
      final uri = base.replace(
        path: '/ws/sms-gateway/',
        queryParameters: {
          'gw_token': token,
          'device_id': deviceId,
          'name': name,
        },
      );
      final ch = WebSocketChannel.connect(uri);
      channel = ch;
      await ch.ready;
      if (gen != generation) return;
      lastPong = DateTime.now();
      final capable = await Telephony.instance.isSmsCapable ?? true;
      ch.sink.add(jsonEncode({
        'type': 'hello',
        'can_send': capable,
        'version': '2.0.0',
      }));
      await updateNotif('Connected as "$name" ✓');

      // Heartbeat: lets the server know we are alive and detects dead sockets.
      heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (gen != generation) return;
        if (DateTime.now().difference(lastPong) > const Duration(seconds: 50)) {
          ch.sink.close();
          return;
        }
        try {
          ch.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      });

      ch.stream.listen(
        (raw) async {
          try {
            final data = jsonDecode(raw as String) as Map<String, dynamic>;
            lastPong = DateTime.now();
            switch (data['type']) {
              case 'send_sms':
                sendSms(
                  data['sms_id'] as int?,
                  data['phone'] as String,
                  data['message'] as String,
                );
              case 'error':
                await updateNotif(data['message'] as String? ?? 'Server error');
            }
          } catch (_) {}
        },
        onDone: () async {
          if (gen != generation) return;
          final code = ch.closeCode;
          if (code == 4009) {
            running = false;
            await updateNotif(
                'Name "$name" is already used by another phone. Change it in settings.');
            return;
          }
          if (code == 4003) {
            running = false;
            await updateNotif('Rejected: wrong token. Check settings.');
            return;
          }
          await updateNotif('Disconnected. Reconnecting…');
          scheduleReconnect(gen);
        },
        onError: (_) async {
          if (gen != generation) return;
          await updateNotif('Error. Reconnecting…');
          scheduleReconnect(gen);
        },
      );
    } catch (e) {
      if (gen != generation) return;
      await updateNotif('Connection failed. Retrying…');
      scheduleReconnect(gen);
    }
  }

  connectRef = connect;

  // Listen for commands from UI
  service.on('stop').listen((_) {
    running = false;
    generation++;
    reconnectTimer?.cancel();
    heartbeatTimer?.cancel();
    channel?.sink.close();
    service.stopSelf();
  });

  service.on('reconnect').listen((_) async {
    running = true;
    generation++;
    reconnectTimer?.cancel();
    heartbeatTimer?.cancel();
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
