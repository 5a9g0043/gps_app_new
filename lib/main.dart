import 'dart:async'; // ← 加這行
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions); // ← 初始化
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng _userLocation = const LatLng(22.3193, 114.1694); // 預設：香港
  Timer? _locationUpdateTimer;

  @override
  void initState() {
    super.initState();
    _getUserLocation();

    // 每 10 秒更新一次位置
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _getUserLocation();
    });
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel(); // 清理資源
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    await Geolocator.requestPermission();
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _userLocation = LatLng(position.latitude, position.longitude);
      print("目前位置：${_userLocation.latitude}, ${_userLocation.longitude}");
    });

    FirebaseFirestore.instance.collection('users').doc('user1').set({
      'latitude': position.latitude,
      'longitude': position.longitude,
      'name': 'shadowz',
      'timestamp': FieldValue.serverTimestamp(),
    });
    print("已更新位置到 Firestore！");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("OpenStreetMap 定位")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userDocs = snapshot.data!.docs;

          final markers = userDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final lat = data['latitude'];
            final lng = data['longitude'];
            final name = data['name'] ?? '未知';

            return Marker(
              point: LatLng(lat, lng),
              width: 80,
              height: 80,
              child: Column(
                children: [
                  const Icon(Icons.person_pin_circle,
                      color: Colors.blue, size: 40),
                  Text(name,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black)),
                ],
              ),
            );
          }).toList();

          return FlutterMap(
            options: MapOptions(
              center: _userLocation,
              zoom: 16,
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
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
