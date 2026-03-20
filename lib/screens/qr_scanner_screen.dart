import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../utils/api_client.dart';
import 'login_screen.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});
  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> with SingleTickerProviderStateMixin {
  final MobileScannerController _cam = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final AudioPlayer _audio = AudioPlayer();
  bool _isProcessing = false;
  bool _overlayActive = false;
  _ScanResult? _result;
  late AnimationController _flashAnim;
  late Animation<double> _flashOpacity;

  @override
  void initState() {
    super.initState();
    _flashAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _flashOpacity = CurvedAnimation(parent: _flashAnim, curve: Curves.easeOut);
    _checkOverlayPermission();
  }

  Future<void> _checkOverlayPermission() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (mounted) setState(() => _overlayActive = granted ?? false);
  }

  @override
  void dispose() {
    _cam.dispose();
    _audio.dispose();
    _flashAnim.dispose();
    super.dispose();
  }

  // ── Core scan handler ─────────────────────────────────────────────────────
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;

    setState(() => _isProcessing = true);
    HapticFeedback.selectionClick();

    final res = await ApiClient.post('/qr/validate', {'token': raw});
    final bool ok = res['statusCode'] == 200 && res['body']['success'] == true;
    final String studentName = res['body']['student'] ?? '';
    final String errorMsg = res['body']['error'] ?? 'Invalid QR Code';
    final String label = ok ? 'BOARDED ✓\n$studentName' : 'DENIED ✗\n$errorMsg';

    // Sound + haptic feedback
    if (ok) {
      _audio.play(AssetSource('sounds/success.mp3')).catchError((_) {});
      HapticFeedback.lightImpact();
    } else {
      _audio.play(AssetSource('sounds/error.mp3')).catchError((_) {});
      HapticFeedback.heavyImpact();
    }

    setState(() => _result = _ScanResult(ok, label));
    _flashAnim.forward(from: 0.0);

    // Auto-reset after 2.5s
    await Future.delayed(const Duration(milliseconds: 2500));
    if (mounted) setState(() { _isProcessing = false; _result = null; });
  }

  // ── Kiosk overlay launcher ────────────────────────────────────────────────
  Future<void> _startKioskMode() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!(granted ?? false)) {
      await FlutterOverlayWindow.requestPermission();
      return;
    }
    await FlutterOverlayWindow.showOverlay(
      enableDrag: true,
      overlayTitle: 'Paraqar Scanner',
      overlayContent: 'QR Scanner Active',
      flag: OverlayFlag.defaultFlag,
      visibility: NotificationVisibility.visibilityPublic,
      positionGravity: PositionGravity.auto,
      height: 340,
      width: 300,
    );
    if (mounted) setState(() => _overlayActive = true);
  }

  Future<void> _stopKioskMode() async {
    await FlutterOverlayWindow.closeOverlay();
    if (mounted) setState(() => _overlayActive = false);
  }

  Future<void> _logout() async {
    await ApiClient.clearAuth();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Paraqar Driver Scanner'),
        backgroundColor: const Color(0xFF0D1B3E),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), onPressed: () => _cam.toggleTorch()),
          IconButton(icon: const Icon(Icons.flip_camera_ios), onPressed: () => _cam.switchCamera()),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Stack(
        children: [
          // ── Camera preview ──────────────────────────────────────────────
          MobileScanner(controller: _cam, onDetect: _onDetect),

          // ── Viewfinder frame ────────────────────────────────────────────
          Center(child: Container(
            width: 260, height: 260,
            decoration: BoxDecoration(
              border: Border.all(
                color: _result == null ? Colors.amber : (_result!.valid ? Colors.green : Colors.red),
                width: 4,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
          )),

          // ── Result flash overlay ────────────────────────────────────────
          if (_result != null)
            FadeTransition(
              opacity: _flashOpacity,
              child: Container(
                color: _result!.valid ? Colors.green.withOpacity(0.85) : Colors.red.withOpacity(0.85),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      _result!.valid ? Icons.check_circle_outline : Icons.cancel_outlined,
                      color: Colors.white, size: 80,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _result!.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 10, color: Colors.black54)]),
                    ),
                  ]),
                ),
              ),
            ),

          // ── Bottom controls ──────────────────────────────────────────────
          Positioned(bottom: 0, left: 0, right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(.85), Colors.transparent]),
              ),
              padding: const EdgeInsets.fromLTRB(20, 30, 20, 36),
              child: Column(children: [
                Text('Align student\'s QR code within the frame',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(.8), fontSize: 15)),
                const SizedBox(height: 20),
                // Kiosk mode toggle
                SizedBox(width: double.infinity,
                  child: _overlayActive
                    ? OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white30),
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: const Icon(Icons.picture_in_picture_alt),
                        label: const Text('Stop Kiosk Mode'),
                        onPressed: _stopKioskMode,
                      )
                    : ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A4FBB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: const Icon(Icons.picture_in_picture),
                        label: const Text('Start Kiosk Mode', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        onPressed: _startKioskMode,
                      ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanResult {
  final bool valid;
  final String label;
  const _ScanResult(this.valid, this.label);
}
