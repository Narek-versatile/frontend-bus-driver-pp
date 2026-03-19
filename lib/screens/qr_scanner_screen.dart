import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/api_client.dart';
import 'login_screen.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({Key? key}) : super(key: key);

  @override
  _QRScannerScreenState createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _isProcessing = false;

  Future<void> _processBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    
    final String? rawValue = barcodes.first.rawValue;
    if (rawValue == null) return;

    setState(() => _isProcessing = true);

    try {
      final response = await ApiClient.post('/qr/validate', {
        'token': rawValue,
      });

      if (!mounted) return;

      if (response['statusCode'] == 200 && response['body']['success'] == true) {
        final studentName = response['body']['student'] ?? 'Unknown';
        _showResultDialog(true, 'Access Granted\nStudent: $studentName');
      } else {
        final reason = response['body']['reason'] ?? 'Invalid Boarding Pass';
        _showResultDialog(false, 'Access Denied\n$reason');
      }
    } catch (e) {
      if (!mounted) return;
      _showResultDialog(false, 'Invalid QR Format');
    }
  }

  void _showResultDialog(bool isValid, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(
          isValid ? Icons.check_circle : Icons.error,
          color: isValid ? Colors.green : Colors.red,
          size: 60,
        ),
        title: Text(isValid ? 'VALID' : 'INVALID', textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() => _isProcessing = false);
              },
              child: const Text('Scan Next Ticket'),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await ApiClient.clearAuth();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen())
    );
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paraqar Driver Scanner'),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => cameraController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => cameraController.switchCamera(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: cameraController,
            onDetect: _processBarcode,
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          // Viewfinder Overlay
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.amber, width: 4),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              'Align QR code within the frame',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)]
              ),
            ),
          )
        ],
      ),
    );
  }
}
