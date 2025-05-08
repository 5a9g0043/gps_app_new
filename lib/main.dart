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
              child:
                  _isLoggingIn
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
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final markers =
              snapshot.data!.docs
                  .map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final lat = data['latitude'];
                    final lng = data['longitude'];
                    final name = data['name'] ?? '未知';
                    final uid = data['uid'];
                    final group = data['group'] ?? ''; // 取得群組名稱
                    final online = data['online'] ?? false;

                    // 只有當群組名稱匹配時，才顯示這個用戶
                    if (group != _currentUserGroup) {
                      return null; // 如果群組名稱不匹配，返回 null
                    }

                    Color color;
                    if (uid == _uid) {
                      color = Colors.green;
                    } else if (online) {
                      color = Colors.red;
                    } else {
                      color = Colors.grey;
                    }

                    return Marker(
                      point: LatLng(lat, lng),
                      width: 80,
                      height: 80,
                      child: Column(
                        children: [
                          Icon(Icons.person_pin_circle, color: color, size: 40),
                          Text(name, style: const TextStyle(fontSize: 12)),
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
