import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import '../utils/api_client.dart';

// ── Required entry point for flutter_overlay_window ──────────────────────────
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: KioskOverlayWidget(),
  ));
}

// ── The minimal floating overlay UI ──────────────────────────────────────────
class KioskOverlayWidget extends StatefulWidget {
  const KioskOverlayWidget({super.key});
  @override
  State<KioskOverlayWidget> createState() => _KioskOverlayWidgetState();
}

class _KioskOverlayWidgetState extends State<KioskOverlayWidget>
    with TickerProviderStateMixin {
  final MobileScannerController _cam = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final AudioPlayer _audio = AudioPlayer();
  bool _scanning = true;
  bool _isProcessing = false;
  _ScanResult? _result;
  late AnimationController _flashAnim;
  late Animation<double> _flashOpacity;

  @override
  void initState() {
    super.initState();
    _flashAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _flashOpacity = CurvedAnimation(parent: _flashAnim, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _cam.dispose();
    _audio.dispose();
    _flashAnim.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_scanning || _isProcessing) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;

    setState(() { _isProcessing = true; });
    HapticFeedback.selectionClick();

    final res = await ApiClient.post('/qr/validate', {'token': raw});
    final bool ok = res['statusCode'] == 200 && res['body']['success'] == true;
    final String label = ok
        ? 'BOARDED ✓\n${res['body']['student'] ?? ''}'
        : 'DENIED ✗\n${res['body']['error'] ?? 'Invalid QR'}';

    // Play sound + haptic
    if (ok) {
      _audio.play(AssetSource('sounds/success.mp3')).catchError((_) {});
      HapticFeedback.lightImpact();
    } else {
      _audio.play(AssetSource('sounds/error.mp3')).catchError((_) {});
      HapticFeedback.heavyImpact();
    }

    setState(() { _result = _ScanResult(ok, label); });
    _flashAnim.forward(from: 0.0);

    // Pause scan for 2.5s then auto-resume
    await Future.delayed(const Duration(milliseconds: 2500));
    if (mounted) setState(() { _isProcessing = false; _result = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Stack(
            children: [
              // ── Camera ──
              MobileScanner(controller: _cam, onDetect: _onDetect),

              // ── Viewfinder frame ──
              Center(child: Container(
                width: 180, height: 180,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _result == null ? Colors.white : (_result!.valid ? Colors.green : Colors.red),
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
              )),

              // ── Status flash overlay ──
              if (_result != null)
                FadeTransition(
                  opacity: _flashOpacity,
                  child: Container(
                    color: _result!.valid ? Colors.green.withOpacity(0.82) : Colors.red.withOpacity(0.82),
                    child: Center(
                      child: Text(
                        _result!.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Top bar: label + close ──
              Positioned(top: 0, left: 0, right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.black.withOpacity(.7), Colors.transparent]),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_scanner, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('Paraqar Scanner', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                      InkWell(
                        onTap: () => FlutterOverlayWindow.closeOverlay(),
                        child: const Icon(Icons.close, color: Colors.white70, size: 20),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Bottom hint ──
              Positioned(bottom: 6, left: 0, right: 0,
                child: Text('Align QR within frame', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(.7), fontSize: 11)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanResult {
  final bool valid;
  final String label;
  const _ScanResult(this.valid, this.label);
}
