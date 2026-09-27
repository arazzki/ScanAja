import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'signature_pad_screen.dart';

class SignDocumentScreen extends StatefulWidget {
  final String imagePath;

  const SignDocumentScreen({Key? key, required this.imagePath}) : super(key: key);

  @override
  _SignDocumentScreenState createState() => _SignDocumentScreenState();
}

class _SignDocumentScreenState extends State<SignDocumentScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  Uint8List? _signatureBytes;
  Offset _signatureOffset = const Offset(100, 200);
  double _signatureScale = 1.0;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Open signature pad automatically if no signature yet
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openSignaturePad();
    });
  }

  Future<void> _openSignaturePad() async {
    final result = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (context) => const SignaturePadScreen()),
    );
    if (result != null) {
      setState(() {
        _signatureBytes = result;
      });
    }
  }

  Future<void> _applyAndSave() async {
    if (_signatureBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan tanda tangan terlebih dahulu')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Capture the RepaintBoundary as an image
      RenderRepaintBoundary boundary =
          _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        Uint8List pngBytes = byteData.buffer.asUint8List();
        
        // Overwrite the existing image or write to a new file
        final originalFile = File(widget.imagePath);
        await originalFile.writeAsBytes(pngBytes);
        
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan tanda tangan: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Posisikan Tanda Tangan'),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Buat Tanda Tangan Baru',
            icon: const Icon(Icons.draw_rounded, color: Color(0xFF38BDF8)),
            onPressed: _openSignaturePad,
          ),
          IconButton(
            tooltip: 'Simpan',
            icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 28),
            onPressed: _isProcessing ? null : _applyAndSave,
          ),
        ],
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: const Color(0xFF1E293B),
                  child: const Row(
                    children: [
                      Icon(Icons.touch_app_rounded, size: 18, color: Color(0xFF94A3B8)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Geser stempel tanda tangan ke posisi yang diinginkan pada dokumen.',
                          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: RepaintBoundary(
                          key: _boundaryKey,
                          child: Stack(
                            alignment: Alignment.topLeft,
                            children: [
                              // Document image
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(widget.imagePath),
                                  fit: BoxFit.contain,
                                ),
                              ),
                              // Signature overlay
                              if (_signatureBytes != null)
                                Positioned(
                                  left: _signatureOffset.dx,
                                  top: _signatureOffset.dy,
                                  child: GestureDetector(
                                    onPanUpdate: (details) {
                                      setState(() {
                                        _signatureOffset = Offset(
                                          _signatureOffset.dx + details.delta.dx,
                                          _signatureOffset.dy + details.delta.dy,
                                        );
                                      });
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: const Color(0xFF2563EB).withOpacity(0.8),
                                          width: 1.5,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                        color: Colors.white.withOpacity(0.1),
                                      ),
                                      child: Transform.scale(
                                        scale: _signatureScale,
                                        child: Image.memory(
                                          _signatureBytes!,
                                          width: 130,
                                          height: 70,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Bottom control panel for resizing
                if (_signatureBytes != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    color: const Color(0xFF1E293B),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          const Icon(Icons.format_size_rounded, color: Color(0xFF94A3B8), size: 20),
                          const SizedBox(width: 12),
                          const Text('Ukuran: ', style: TextStyle(color: Colors.white)),
                          Expanded(
                            child: Slider(
                              value: _signatureScale,
                              min: 0.5,
                              max: 2.0,
                              activeColor: const Color(0xFF2563EB),
                              inactiveColor: const Color(0xFF475569),
                              onChanged: (val) {
                                setState(() => _signatureScale = val);
                              },
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _applyAndSave,
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Terapkan'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
