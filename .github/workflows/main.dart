import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:piratetok_live/piratetok_live.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// ============================================================
// FOREGROUND SERVICE — giữ app chạy nền
// ============================================================
@pragma('vm:entry-point')
void startCallback() => FlutterForegroundTask.setTaskHandler(MyTaskHandler());

class MyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}
  @override
  Future<void> onDestroy(DateTime timestamp) async {}
  @override
  void onNotificationButtonPressed(String id) {}
  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
  @override
  void onNotificationDismissed() {}
}

// ============================================================
// MAIN
// ============================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'tiklive',
      channelName: 'TikLive đang chạy',
      channelDescription: 'Nhận sự kiện TikTok LIVE',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true, playSound: false),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(10000),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  runApp(const App());
}

// ============================================================
// APP
// ============================================================
class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TikLive',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0F0F17),
          primaryColor: const Color(0xFFFF2D55),
          colorScheme: const ColorScheme.dark(
              primary: Color(0xFFFF2D55), secondary: Color(0xFF8B5CF6)),
          appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF16161F),
              elevation: 0,
              centerTitle: true),
        ),
        home: const HomeScreen(),
      );
}

// ============================================================
// TTS SERVICE
// ============================================================
class Tts {
  static final _tts = FlutterTts();
  static final List<String> _q = [];
  static bool _busy = false;

  static Future<void> init() async {
    await _tts.setLanguage('vi-VN');
    await _tts.setSpeechRate(1.1);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    try {
      final v = await _tts.getVoices;
      if (v is List) {
        for (final x in v) {
          final n = x['name']?.toString() ?? '';
          final l = x['locale']?.toString() ?? '';
          if (l.contains('vi') && n.toLowerCase().contains('google')) {
            await _tts.setVoice({'name': n, 'locale': l});
            break;
          }
        }
      }
    } catch (_) {}
  }

  static void speak(String t) {
    if (t.trim().isEmpty) return;
    _q.add(t);
    if (!_busy) _drain();
  }

  static Future<void> _drain() async {
    if (_q.isEmpty) {
      _busy = false;
      return;
    }
    _busy = true;
    try {
      await _tts.speak(_q.removeAt(0));
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 100));
    _drain();
  }

  static Future<void> stop() async {
    _q.clear();
    _busy = false;
    await _tts.stop();
  }
}

// ============================================================
// AUDIO SERVICE
// ============================================================
class Audio {
  static final _sfx = AudioPlayer();

  static Future<void> playGift() async {
    try {
      await _sfx.stop();
      await _sfx.play(AssetSource('gift.mp3'));
    } catch (_) {}
  }

  static Future<void> playFollow() async {
    try {
      await _sfx.stop();
      await _sfx.play(AssetSource('gift.mp3'));
    } catch (_) {}
  }
}

// ============================================================
// MODELS
// ============================================================
class Gift {
  final String user, name;
  final int count, diamonds;
  final DateTime time;
  Gift(this.user, this.name, this.count, this.diamonds)
      : time = DateTime.now();
  int get total => count * diamonds;
  String get emoji {
    const m = {
      'Rose': '🌹', 'TikTok': '🎵', 'Finger Heart': '🫰', 'GG': '🎮',
      'Ice Cream': '🍦', 'Corgi': '🐕', 'Doughnut': '🍩', 'Heart': '❤️',
      'Music': '🎶', 'Galaxy': '🌌', 'Lion': '🦁', 'Rocket': '🚀',
      'Star': '⭐', 'Diamond': '💎', 'Crown': '👑', 'Castle': '🏰',
      'Universe': '🪐', 'Hand Hearts': '💖', 'Sunglasses': '😎'
    };
    return m[name] ?? '🎁';
  }
}

class ChatMsg {
  final String user, text;
  ChatMsg(this.user, this.text);
}

// ============================================================
// TIKTOK SERVICE
// ============================================================
class TikTok {
  TikTokLiveClient? _c;
  final _status = StreamController<String>.broadcast();
  final _gift = StreamController<Gift>.broadcast();
  final _chat = StreamController<ChatMsg>.broadcast();
  final _follow = StreamController<String>.broadcast();
  final _like = StreamController<int>.broadcast();

  Stream<String> get status => _status.stream;
  Stream<Gift> get gifts => _gift.stream;
  Stream<ChatMsg> get chats => _chat.stream;
  Stream<String> get follows => _follow.stream;
  Stream<int> get likes => _like.stream;

  int totalDiamonds = 0, totalLikes = 0, totalGifts = 0, totalFollows = 0;

  Future<void> connect(String user) async {
    await disconnect();
    _status.add('Đang kết nối...');
    try {
      _c = TikTokLiveClient(user.replaceAll('@', ''));

      _c!.on(EventType.gift, (e) {
        final d = e.data;
        if (d == null) return;
        if (d['giftType'] == 1 && d['repeatEnd'] == false) return;
        final u = d['user']?['nickname']?.toString() ??
            d['user']?['uniqueId']?.toString() ??
            'Ai đó';
        final n = d['giftName']?.toString() ??
            d['gift']?['name']?.toString() ??
            'Quà';
        final cnt = (d['repeatCount'] as num?)?.toInt() ?? 1;
        final dia = (d['diamondCount'] as num?)?.toInt() ?? 0;
        final g = Gift(u, n, cnt, dia);
        totalGifts++;
        totalDiamonds += g.total;
        _gift.add(g);
        Audio.playGift();
        Tts.speak('Cảm ơn $u đã tặng ${cnt > 1 ? "$cnt " : ""}$n');
      });

      _c!.on(EventType.chat, (e) {
        final d = e.data;
        if (d == null) return;
        final u = d['user']?['nickname']?.toString() ??
            d['user']?['uniqueId']?.toString() ??
            'Ai đó';
        final t = d['content']?.toString() ?? '';
        if (t.isEmpty) return;
        _chat.add(ChatMsg(u, t));
      });

      _c!.on(EventType.follow, (e) {
        final d = e.data;
        final u = d?['user']?['nickname']?.toString() ??
            d?['user']?['uniqueId']?.toString() ??
            'Ai đó';
        totalFollows++;
        _follow.add(u);
        Audio.playFollow();
        Tts.speak('Chào mừng $u');
      });

      _c!.on(EventType.like, (e) {
        final d = e.data;
        final c = (d?['count'] as num?)?.toInt() ??
            (d?['likeCount'] as num?)?.toInt() ??
            1;
        totalLikes += c;
        _like.add(totalLikes);
      });

      await _c!.connect();
      _status.add('Đang LIVE: @$user');
    } catch (e) {
      _status.add('Lỗi: $e');
    }
  }

  Future<void> disconnect() async {
    try {
      await _c?.close();
    } catch (_) {}
    _c = null;
  }

  void dispose() {
    _status.close();
    _gift.close();
    _chat.close();
    _follow.close();
    _like.close();
  }
}

// ============================================================
// HOME SCREEN
// ============================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Tts.init();
    SharedPreferences.getInstance()
        .then((p) => _ctrl.text = p.getString('user') ?? '');
  }

  Future<void> _start() async {
    final u = _ctrl.text.trim().replaceAll('@', '');
    if (u.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nhập username trước')));
      return;
    }
    await Permission.notification.request();

    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        notificationTitle: 'TikLive đang chạy',
        notificationText: 'Đang nhận sự kiện TikTok LIVE',
        callback: startCallback,
      );
    }

    (await SharedPreferences.getInstance()).setString('user', u);
    if (!mounted) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => LiveScreen(username: u)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFF2D55), Color(0xFF8B5CF6)]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Center(
                    child: Text('T',
                        style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('TikLive Mobile',
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('TikTok Gift Alert + TTS + Nhạc',
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 40),
                TextField(
                  controller: _ctrl,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: '@username TikTok',
                    prefixIcon: const Icon(Icons.person_outline),
                    filled: true,
                    fillColor: const Color(0xFF1E1E2A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _start,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF2D55),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('🔴  Bắt đầu LIVE',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ============================================================
// LIVE SCREEN
// ============================================================
class LiveScreen extends StatefulWidget {
  final String username;
  const LiveScreen({super.key, required this.username});
  @override
  State<LiveScreen> createState() => _LiveState();
}

class _LiveState extends State<LiveScreen> {
  final _tk = TikTok();
  final _gifts = <Gift>[];
  final _chats = <ChatMsg>[];
  Gift? _alert;
  Timer? _alertTimer;
  String _status = 'Chờ kết nối';

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    _tk.status.listen((s) {
      if (mounted) setState(() => _status = s);
    });

    _tk.gifts.listen((g) {
      if (!mounted) return;
      setState(() {
        _gifts.insert(0, g);
        if (_gifts.length > 30) _gifts.removeLast();
        _alert = g;
      });
      _alertTimer?.cancel();
      _alertTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _alert = null);
      });
    });

    _tk.chats.listen((c) {
      if (!mounted) return;
      setState(() {
        _chats.insert(0, c);
        if (_chats.length > 30) _chats.removeLast();
      });
    });

    _tk.likes.listen((_) {
      if (mounted) setState(() {});
    });

    _tk.follows.listen((_) {
      if (mounted) setState(() {});
    });

    _tk.connect(widget.username);
  }

  @override
  void dispose() {
    _alertTimer?.cancel();
    _tk.dispose();
    _tk.disconnect();
    Tts.stop();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Column(
            children: [
              Text('@${widget.username}',
                  style: const TextStyle(fontSize: 15)),
              Text(_status,
                  style: TextStyle(
                      fontSize: 11,
                      color: _status.contains('LIVE')
                          ? Colors.green
                          : Colors.grey)),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _tk.disconnect();
              Navigator.pop(context);
            },
          ),
        ),
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _stat('💎', '${_tk.totalDiamonds}', 'Xu'),
                  _stat('❤️', '${_tk.totalLikes}', 'Like'),
                  _stat('🎁', '${_tk.totalGifts}', 'Quà'),
                  _stat('➕', '${_tk.totalFollows}', 'Follow'),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF1A1A24), Color(0xFF0D0D14)]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF23232F)),
                ),
                child: Stack(
                  children: [
                    if (_alert != null) Center(child: _buildAlert(_alert!)),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: _chats
                            .take(4)
                            .map((c) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.55),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: RichText(
                                      text: TextSpan(
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.white),
                                        children: [
                                          TextSpan(
                                              text: '${c.user}: ',
                                              style: const TextStyle(
                                                  color: Color(0xFFFF5C7A),
                                                  fontWeight:
                                                      FontWeight.bold)),
                                          TextSpan(text: c.text),
                                        ],
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              height: 200,
              margin: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF13131C),
                border: Border(top: BorderSide(color: Color(0xFF23232F))),
              ),
              child: _gifts.isEmpty
                  ? const Center(
                      child: Text('Chưa có quà nào',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _gifts.length,
                      itemBuilder: (_, i) {
                        final g = _gifts[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A24),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text(g.emoji,
                                  style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(g.user,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                    Text(
                                        '${g.name} x${g.count} • 💎${g.total}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );

  Widget _stat(String i, String v, String l) => Expanded(
        child: Column(
          children: [
            Text(i, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 2),
            Text(v,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      );

  Widget _buildAlert(Gift g) => TweenAnimationBuilder<double>(
        key: ValueKey(g.time),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 400),
        curve: Curves.elasticOut,
        builder: (_, v, c) => Transform.scale(scale: v, child: c),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(g.emoji, style: const TextStyle(fontSize: 70)),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF2D55), Color(0xFF8B5CF6)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${g.name}${g.count > 1 ? " x${g.count}" : ""}',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            Text(g.user,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFF5C7A))),
          ],
        ),
      );
}
