import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'camera_screen.dart';

void main() {
  runApp(const PlaneIdentifierApp());
}

class PlaneIdentifierApp extends StatelessWidget {
  const PlaneIdentifierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Uçak Tanımlama',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const StartScreen(),
    );
  }
}

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  Future<void> _openCamera(BuildContext context) async {
    final cameraPermission = await Permission.camera.request();
    final locationPermission = await Permission.locationWhenInUse.request();

    if (!context.mounted) {
      return;
    }

    if (cameraPermission.isGranted && locationPermission.isGranted) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const CameraScreen(),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Kamera ve konum izinleri gerekli.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Uçak Tanımlama',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _openCamera(context),
              child: const Text('Fotoğraf Çek'),
            ),
          ],
        ),
      ),
    );
  }
}
