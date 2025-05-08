import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'GPS App',
      debugShowCheckedModeBanner: false,
      home: LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _groupController = TextEditingController(); // 新增群組名稱輸入框
  bool _isLoggingIn = false;

  Future<void> _signInAnonymously() async {
    final prefs = await SharedPreferences.getInstance();
    final name = _nameController.text.trim();
    final groupName = _groupController.text.trim(); // 取得群組名稱

    if (name.isEmpty || groupName.isEmpty) {
      // 如果名稱或群組名稱為空
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請輸入名稱及群組名稱')));
      return;
    }

    setState(() {
      _isLoggingIn = true;
    });

    try {
      await FirebaseAuth.instance.signInAnonymously();
      await prefs.setString('user_display_name', name);
      await prefs.setString('user_group_name', groupName); // 儲存群組名稱
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MapScreen()),
      );
    } catch (e) {
      print('匿名登入失敗: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('登入失敗: $e')));
    } finally {
      setState(() {
        _isLoggingIn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('輸入名稱和群組')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '你的名稱'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _groupController, // 群組名稱輸入框
              decoration: const InputDecoration(labelText: '你的群組名稱'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoggingIn ? null : _signInAnonymously,
              child: _isLoggingIn
                  ? const CircularProgressIndicator()
                  : const Text('開始'),
            ),
          ],
        ),
      ),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng _userLocation = const LatLng(22.3193, 114.1694);
  String? _displayName;
  String? _uid;
  String _currentUserGroup = ''; // 初始化群組名稱
  bool _isEmergencyActive = false;
  DateTime? _lastEmergencyTime;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _getUserLocationAndSave();
    _getUserGroupName(); // 獲取群組名稱
  }

  Future<void> _getUserGroupName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserGroup =
          prefs.getString('user_group_name') ?? ''; // 確保讀取到的群組名稱
    });
  }

  Future<void> _getUserLocationAndSave() async {
    await Geolocator.requestPermission();
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // 等待 SharedPreferences 實例來讀取儲存的資料
    final prefs = await SharedPreferences.getInstance();
    _displayName = prefs.getString('user_display_name') ?? '匿名用戶';
    final groupName = prefs.getString('user_group_name') ?? '未設定';

    setState(() {
      _userLocation = LatLng(position.latitude, position.longitude);
    });

    if (_uid == null) return;

    // 儲存用戶資料
    final userData = {
      'uid': _uid,
      'name': _displayName,
      'group': groupName, // 儲存群組名稱
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': FieldValue.serverTimestamp(),
      'online': true,
    };

    // 更新 Firestore 中的用戶資料
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .set(userData, SetOptions(merge: true));
  }

  Future<void> _sendEmergencyAlert() async {
    if (_uid == null) {
      print('錯誤：用戶ID為空');
      return;
    }

    try {
      print('開始發送緊急通知...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 更新用戶文件中的緊急狀態
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'emergency_status': 'active',
        'emergency_timestamp': FieldValue.serverTimestamp(),
        'latitude': position.latitude,
        'longitude': position.longitude,
      });

      print('緊急通知已發送');

      setState(() {
        _isEmergencyActive = true;
        _lastEmergencyTime = DateTime.now();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('緊急通知已發送'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('發送緊急通知時發生錯誤: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('發送緊急通知失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cancelEmergencyAlert() async {
    if (_uid == null) {
      print('錯誤：用戶ID為空');
      return;
    }

    try {
      print('開始取消緊急狀態...');
      print('當前用戶ID: $_uid');

      // 更新用戶文件中的緊急狀態
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'emergency_status': 'cancelled',
        'emergency_cancelled_at': FieldValue.serverTimestamp(),
      });

      print('緊急狀態已取消');

      setState(() {
        _isEmergencyActive = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('緊急狀態已成功取消'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stackTrace) {
      print('取消緊急狀態時發生錯誤: $e');
      print('錯誤堆疊: $stackTrace');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('取消緊急狀態失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    if (_uid != null) {
      FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'online': false,
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('地圖'),
        actions: [
          // 修改緊急按鈕的顯示邏輯
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(_uid)
                .snapshots(),
            builder: (context, snapshot) {
              final isActive = snapshot.hasData &&
                  (snapshot.data?.data()
                          as Map<String, dynamic>?)?['emergency_status'] ==
                      'active';
              return IconButton(
                icon: Icon(
                  isActive ? Icons.warning_amber : Icons.warning,
                  color: isActive ? Colors.red : Colors.white,
                ),
                onPressed:
                    isActive ? _cancelEmergencyAlert : _sendEmergencyAlert,
                tooltip: isActive ? '取消緊急狀態' : '發送緊急通知',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('user_display_name');
              await prefs.remove('user_group_name');
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('group', isEqualTo: _currentUserGroup)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final markers = snapshot.data!.docs
              .map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final lat = data['latitude'];
                final lng = data['longitude'];
                final name = data['name'] ?? '未知';
                final uid = data['uid'];
                final group = data['group'] ?? '';
                final online = data['online'] ?? false;
                final emergencyStatus = data['emergency_status'] == 'active';

                if (group != _currentUserGroup) {
                  return null;
                }

                Color color;
                if (uid == _uid) {
                  color = Colors.green;
                } else if (emergencyStatus) {
                  color = Colors.red;
                } else if (online) {
                  color = Colors.blue;
                } else {
                  color = Colors.grey;
                }

                return Marker(
                  point: LatLng(lat, lng),
                  width: 80,
                  height: 80,
                  child: Column(
                    children: [
                      Icon(
                        emergencyStatus
                            ? Icons.warning
                            : Icons.person_pin_circle,
                        color: color,
                        size: 40,
                      ),
                      Text(
                        emergencyStatus ? '$name 需要協助' : name,
                        style: TextStyle(
                          fontSize: 12,
                          color: emergencyStatus ? Colors.red : null,
                          fontWeight: emergencyStatus ? FontWeight.bold : null,
                        ),
                      ),
                    ],
                  ),
                );
              })
              .where((marker) => marker != null)
              .cast<Marker>()
              .toList();

          return FlutterMap(
            options: MapOptions(center: _userLocation, zoom: 16),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.gps_app',
              ),
              MarkerLayer(markers: markers),
            ],
          );
        },
      ),
    );
  }
}
