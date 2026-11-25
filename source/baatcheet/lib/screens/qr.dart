import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/db.dart';
import '../widgets.dart';
import 'contacts.dart';

const _prefix = 'baatcheet:';

class MyQrScreen extends StatelessWidget {
  const MyQrScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final me = Db.me ?? {};
    return Scaffold(
      appBar: AppBar(title: const Text('My QR Code')),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Avatar(data: me['avatar'], name: me['name'] ?? '', size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(me['name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  Text('ID: ${me['chatId'] ?? ''}', style: const TextStyle(color: Colors.black54)),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            QrImageView(data: '$_prefix${Db.uid}', size: 240, backgroundColor: Colors.white),
            const SizedBox(height: 14),
            const Text('Scan this QR code to add me on BaatCheet', style: TextStyle(color: Colors.black45, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue ?? '';
      if (v.startsWith(_prefix)) {
        _handled = true;
        final uid = v.substring(_prefix.length);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: uid)));
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(children: [
        MobileScanner(onDetect: _onDetect),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(border: Border.all(color: kGreen, width: 3), borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 60,
          child: Text("Point at a friend's BaatCheet QR code", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
        ),
      ]),
    );
  }
}
