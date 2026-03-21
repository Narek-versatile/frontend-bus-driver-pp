import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'screens/login_screen.dart';
import 'screens/qr_scanner_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ParaqarDriverApp());
}

class ParaqarDriverApp extends StatelessWidget {
  const ParaqarDriverApp({super.key});

  Future<bool> _checkAuth() async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'jwt_token');
    return token != null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paraqar Driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A4FBB)),
        useMaterial3: true,
      ),
      home: FutureBuilder<bool>(
        future: _checkAuth(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data == true ? const QRScannerScreen() : const LoginScreen();
        },
      ),
    );
  }
}
