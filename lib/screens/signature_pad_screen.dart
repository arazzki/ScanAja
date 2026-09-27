import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({Key? key}) : super(key: key);

  @override
  _SignaturePadScreenState createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  late SignatureController _controller;
  Color _selectedColor = Colors.black;
  double _strokeWidth = 3.0;

  final List<Color> _availableColors = [
    Colors.black,
    const Color(0xFF1E3A8A), // Dark Blue
    const Color(0xFF2563EB), // Primary Blue
    const Color(0xFFDC2626), // Red
  ];

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    _controller = SignatureController(
      penStrokeWidth: _strokeWidth,
      penColor: _selectedColor,
      exportBackgroundColor: Colors.transparent,
    );
  }

  void _updatePenColor(Color color) {
    setState(() {
      _selectedColor = color;
      final points = _controller.points;
      _controller = SignatureController(
        penStrokeWidth: _strokeWidth,
        penColor: _selectedColor,
        exportBackgroundColor: Colors.transparent,
        points: points,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveSignature() async {
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Silakan buat tanda tangan terlebih dahulu'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final Uint8List? signatureBytes = await _controller.toPngBytes();
    if (signatureBytes != null && mounted) {
      Navigator.pop(context, signatureBytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Tanda Tangan Digital',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
        actions: [
          IconButton(
            tooltip: 'Hapus / Ulangi',
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFEF4444)),
            onPressed: () => _controller.clear(),
          ),
          IconButton(
            tooltip: 'Gunakan Tanda Tangan',
            icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB), size: 28),
            onPressed: _saveSignature,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  const Text(
                    'Pilihan Tinta: ',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                  ),
                  const SizedBox(width: 8),
                  ..._availableColors.map((color) {
                    final isSelected = _selectedColor == color;
                    return GestureDetector(
                      onTap: () => _updatePenColor(color),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? const Color(0xFF38BDF8) : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: color.withOpacity(0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                    );
                  }),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      // Guidelines watermark in background
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.draw_rounded, size: 48, color: Colors.grey.withOpacity(0.2)),
                            const SizedBox(height: 8),
                            Text(
                              'Goreskan tanda tangan Anda di area ini',
                              style: TextStyle(
                                color: Colors.grey.withOpacity(0.5),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Signature(
                        controller: _controller,
                        backgroundColor: Colors.transparent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _controller.clear(),
                      icon: const Icon(Icons.clear_all_rounded, color: Color(0xFF64748B)),
                      label: const Text('Bersihkan', style: TextStyle(color: Color(0xFF64748B))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _saveSignature,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Gunakan Tanda Tangan', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
