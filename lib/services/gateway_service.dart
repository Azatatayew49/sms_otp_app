import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:another_telephony/telephony.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'account.dart';

const kPrefUrl = 'gateway_url';
// A fresh install talks to the production server without any setup.
const kDefaultUrl = 'http://45.39.230.200';
const kPrefDeviceId = 'gateway_device_id';
// From signing in (see account.dart); valid until this phone signs out.
const kPrefAuthToken = 'gateway_auth_token';
const kPrefLogin = 'gateway_login';
// Set by the admin in the staff app; the server tells the phone.
const kPrefDeviceName = 'gateway_device_name';
const kPrefEnabled = 'gateway_enabled';
// The SIM an admin chose for SMS and the balance check (-1: the phone's SMS SIM),
// and how to describe it ("SIM 2 · TMCELL").
const kPrefSimId = 'gateway_sim_id';
const kPrefSimLabel = 'gateway_sim_label';
const _kPrefBalanceAt = 'gateway_balance_checked_at';
// TMCell balance check; the reply text goes to the server, which reads the amount.
const kBalanceUssd = '*0800#';
const _balanceEvery = Duration(hours: 1);
const _ussd = MethodChannel('akulag/ussd');
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
  Timer? balanceTimer;
  final battery = Battery();
  bool checkingBalance = false;
  bool running = true;
  // Bumped on every (re)connect so callbacks of an old socket are ignored.
  int generation = 0;
  Future<void> Function()? connectRef;
  DateTime lastPong = DateTime.now();
  var version = '';
  var model = '';

  String name() => prefs.getString(kPrefDeviceName) ?? '';
  bool enabled() => prefs.getBool(kPrefEnabled) ?? false;

  /// The admin's on/off switch, as the notification and the app show it.
  String switchText() => enabled()
      ? 'ON · sending login codes as "${name()}"'
      : 'OFF · turned off by an admin, no codes are sent';

  Future<void> updateNotif(String text) async {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'SMS Gateway',
        content: text,
      );
    }
    service.invoke('status', {'message': text});
  }

  Future<void> publishState({required bool online}) async {
    service.invoke('state', {
      'name': name(),
      'enabled': enabled(),
      'online': online,
      'sim': prefs.getString(kPrefSimLabel) ?? '',
    });
    await updateNotif(online ? switchText() : 'Not connected');
  }

  Future<void> signedOut(String message) async {
    running = false;
    generation++;
    heartbeatTimer?.cancel();
    balanceTimer?.cancel();
    reconnectTimer?.cancel();
    await prefs.remove(kPrefAuthToken);
    await prefs.remove(kPrefEnabled);
    service.invoke('signed_out', {'message': message});
    await updateNotif(message);
    service.stopSelf();
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

  int simId() => prefs.getInt(kPrefSimId) ?? -1;

  /// The phone's active SIMs, as the server and admins see them.
  Future<List<Map<String, dynamic>>> listSims() async {
    try {
      final raw = await _ussd.invokeMethod<List<dynamic>>('listSims');
      return [for (final s in raw ?? const []) Map<String, dynamic>.from(s as Map)];
    } catch (_) {
      return [];
    }
  }

  /// Remembers the admin's SIM choice and a label for it.
  Future<void> saveSim(dynamic id) async {
    final sim = id is int ? id : -1;
    await prefs.setInt(kPrefSimId, sim);
    var label = 'Phone default SIM';
    if (sim >= 0) {
      final match = (await listSims()).where((s) => s['id'] == sim);
      label = match.isEmpty
          ? 'Chosen SIM (not found)'
          : 'SIM ${(match.first['slot'] as int? ?? 0) + 1} · ${match.first['carrier'] ?? match.first['name'] ?? ''}';
    }
    await prefs.setString(kPrefSimLabel, label);
  }

  // The SMS plugin keeps a single status listener, so two SMS sent at once would get
  // each other's "sent". Send one at a time, each waiting for its "sent".
  Future<void> sendQueue = Future.value();
  var sendSeq = 0;

  Future<void> sendOne(int? smsId, String phone, String message, int? sim) async {
    final telephony = Telephony.instance;
    final time = DateTime.now().toIso8601String();
    final seq = ++sendSeq;
    final handed = Completer<void>();

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
      // Awaited so platform errors (missing permission, receiver registration)
      // land in the catch below instead of vanishing with no ack or log.
      await telephony.sendSms(
        subscriptionId: sim ?? simId(),
        to: phone,
        message: message,
        // 70 chars is the single-SMS limit once the text needs Unicode.
        isMultipart: message.length > 70,
        statusListener: (SendStatus status) async {
          if (status == SendStatus.SENT) {
            if (handed.isCompleted) return;
            handed.complete();
            // Handed to the carrier: that is success for monitoring purposes.
            sendAck(smsId, 'sent');
            logLocal(true);
            await updateNotif('Last SMS to $phone');
          } else if (status == SendStatus.DELIVERED && seq == sendSeq) {
            // Only while no later SMS replaced the listener: then it is surely ours.
            sendAck(smsId, 'delivered');
          }
        },
      // Without SMS permission the plugin can't ask for it from this background
      // isolate and never answers; report that instead of waiting forever.
      ).timeout(const Duration(seconds: 30),
          onTimeout: () => throw 'No answer from Android. Is SMS permission granted?');
      // No "sent" in time (no signal, no credit…): move on; the server retries the
      // code on another phone.
      await handed.future.timeout(const Duration(seconds: 15), onTimeout: () {
        logLocal(false, 'Not sent within 15 s');
      });
    } catch (e) {
      sendAck(smsId, 'failed', e.toString());
      logLocal(false, e.toString());
      await updateNotif('SMS exception: $e');
    }
  }

  void sendSms(int? smsId, String phone, String message, [int? sim]) {
    sendQueue = sendQueue.then((_) => sendOne(smsId, phone, message, sim)).catchError((_) {});
  }

  /// Battery level and charging state for the server (null fields if unknown).
  Future<Map<String, dynamic>> batteryInfo() async {
    try {
      final level = await battery.batteryLevel;
      final state = await battery.batteryState;
      return {
        'battery': level,
        'charging': state == BatteryState.charging || state == BatteryState.full,
      };
    } catch (_) {
      return {};
    }
  }

  /// Dials the balance USSD at most once per [_balanceEvery] (remembered across
  /// restarts) and reports the reply, or why it failed. [force]: an admin asked
  /// for a check now.
  Future<void> checkBalanceIfDue({bool force = false}) async {
    if (checkingBalance || channel == null) return;
    final last = DateTime.tryParse(prefs.getString(_kPrefBalanceAt) ?? '');
    if (!force && last != null && DateTime.now().difference(last) < _balanceEvery) return;
    checkingBalance = true;
    await prefs.setString(_kPrefBalanceAt, DateTime.now().toIso8601String());
    Map<String, dynamic> report;
    try {
      final reply = await _ussd
          .invokeMethod<String>('sendUssd', {'code': kBalanceUssd, 'sub_id': simId()})
          .timeout(const Duration(seconds: 60));
      report = {'type': 'balance', 'code': kBalanceUssd, 'text': reply ?? ''};
    } on PlatformException catch (e) {
      report = {'type': 'balance', 'code': kBalanceUssd, 'error': e.message ?? e.code};
    } on TimeoutException {
      report = {'type': 'balance', 'code': kBalanceUssd, 'error': 'No reply from the network'};
    } catch (e) {
      report = {'type': 'balance', 'code': kBalanceUssd, 'error': e.toString()};
    }
    checkingBalance = false;
    try {
      channel?.sink.add(jsonEncode(report));
    } catch (_) {}
  }

  void scheduleReconnect(int gen) {
    if (!running || gen != generation) return;
    heartbeatTimer?.cancel();
    balanceTimer?.cancel();
    reconnectTimer?.cancel();
    reconnectTimer = Timer(const Duration(seconds: 5), () => connectRef?.call());
  }

  Future<void> connect() async {
    final gen = ++generation;
    reconnectTimer?.cancel();
    heartbeatTimer?.cancel();
    balanceTimer?.cancel();
    await prefs.reload(); // signing in happens in the app's own isolate
    final url = prefs.getString(kPrefUrl) ?? kDefaultUrl;
    final token = prefs.getString(kPrefAuthToken) ?? '';
    if (token.isEmpty) {
      await signedOut('Not signed in. Open the app and sign in.');
      return;
    }

    try {
      await updateNotif('Connecting…');
      final base = Uri.parse(url.replaceFirst(RegExp(r'^http'), 'ws'));
      final uri = base.replace(
        path: '/ws/sms-gateway/',
        queryParameters: {'token': token},
      );
      final ch = WebSocketChannel.connect(uri);
      channel = ch;
      await ch.ready;
      if (gen != generation) return;
      lastPong = DateTime.now();
      final capable = await Telephony.instance.isSmsCapable ?? true;
      ch.sink.add(jsonEncode({
        ...await batteryInfo(),
        'type': 'hello',
        'can_send': capable,
        'version': version,
        'model': model,
        'sims': await listSims(),
      }));

      // Heartbeat: lets the server know we are alive and detects dead sockets.
      // Balance: shortly after connecting if due, then re-checked every few minutes.
      balanceTimer?.cancel();
      balanceTimer = Timer(const Duration(seconds: 30), () {
        if (gen == generation) checkBalanceIfDue();
        balanceTimer = Timer.periodic(const Duration(minutes: 5), (_) {
          if (gen == generation) checkBalanceIfDue();
        });
      });

      heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
        if (gen != generation) return;
        if (DateTime.now().difference(lastPong) > const Duration(seconds: 50)) {
          ch.sink.close();
          return;
        }
        try {
          ch.sink.add(jsonEncode({'type': 'ping', ...await batteryInfo()}));
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
                  data['sim_id'] as int?,
                );
              case 'registered':
                await prefs.setString(kPrefDeviceName, data['name'] as String? ?? name());
                await prefs.setBool(kPrefEnabled, data['enabled'] == true);
                await saveSim(data['sim_id']);
                await publishState(online: true);
              case 'settings':
                // An admin chose another SIM: its balance is unknown, check it now.
                await saveSim(data['sim_id']);
                await publishState(online: true);
                checkBalanceIfDue(force: true);
              case 'enabled':
                await prefs.setBool(kPrefEnabled, data['enabled'] == true);
                await publishState(online: true);
              case 'renamed':
                await prefs.setString(kPrefDeviceName, data['name'] as String? ?? name());
                await publishState(online: true);
              case 'signed_out':
                await signedOut(data['message'] as String? ?? 'Signed out.');
              case 'check_balance':
                checkBalanceIfDue(force: true);
              case 'error':
                await updateNotif(data['message'] as String? ?? 'Server error');
            }
          } catch (_) {}
        },
        onDone: () async {
          if (gen != generation) return;
          final code = ch.closeCode;
          if (code == 4001) {
            if (running) await signedOut('Signed out. Sign in again.');
            return;
          }
          if (code == 4003) {
            running = false;
            await updateNotif('Rejected by the server. Update the app.');
            return;
          }
          service.invoke('state', {'name': name(), 'enabled': enabled(), 'online': false});
          await updateNotif('Disconnected. Reconnecting…');
          scheduleReconnect(gen);
        },
        onError: (_) async {
          if (gen != generation) return;
          service.invoke('state', {'name': name(), 'enabled': enabled(), 'online': false});
          await updateNotif('Error. Reconnecting…');
          scheduleReconnect(gen);
        },
      );
    } catch (e) {
      if (gen != generation) return;
      service.invoke('state', {'name': name(), 'enabled': enabled(), 'online': false});
      await updateNotif('Connection failed. Retrying…');
      scheduleReconnect(gen);
    }
  }

  try {
    version = (await PackageInfo.fromPlatform()).version;
  } catch (_) {}
  model = await Account.phoneModel();
  connectRef = connect;

  // Listen for commands from UI
  service.on('stop').listen((_) {
    running = false;
    generation++;
    reconnectTimer?.cancel();
    heartbeatTimer?.cancel();
    balanceTimer?.cancel();
    channel?.sink.close();
    service.stopSelf();
  });

  service.on('reconnect').listen((_) async {
    running = true;
    generation++;
    reconnectTimer?.cancel();
    heartbeatTimer?.cancel();
    balanceTimer?.cancel();
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

  /// {name, enabled, online} whenever the server tells the phone something.
  static Stream<Map<String, dynamic>?> get stateStream => _service.on('state');

  /// The server signed this phone out (or the token stopped working).
  static Stream<Map<String, dynamic>?> get signedOutStream => _service.on('signed_out');

  /// Stream of SMS log entries from the service.
  static Stream<Map<String, dynamic>?> get smsSentStream =>
      _service.on('sms_sent');
}
