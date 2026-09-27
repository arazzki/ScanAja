import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../models/document_model.dart';
import '../models/folder_model.dart';
import '../services/database_helper.dart';
import '../services/conversion_service.dart';
import '../services/scanner_service.dart';

class ConvertScreen extends StatefulWidget {
  const ConvertScreen({Key? key}) : super(key: key);

  @override
  _ConvertScreenState createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ImagePicker _picker = ImagePicker();

  // Image to PDF State
  List<XFile> _selectedImages = [];
  final TextEditingController _imgToPdfTitleController = TextEditingController();
  String _imgToPdfFolder = 'Uncategorized';

  // PDF to Image State
  File? _selectedPdfFile;
  final TextEditingController _pdfToImgTitleController = TextEditingController();
  String _pdfToImgFolder = 'Uncategorized';

  List<FolderModel> _folders = [];
  bool _isLoading = false;
  String _loadingMessage = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _imgToPdfTitleController.text = 'Doc_Images_${DateTime.now().millisecondsSinceEpoch}';
    _pdfToImgTitleController.text = 'Doc_Extracted_${DateTime.now().millisecondsSinceEpoch}';
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final list = await DatabaseHelper.instance.readAllFolders();
    setState(() {
      _folders = list;
    });
  }

  // --- Image to PDF Methods ---
  Future<void> _pickImagesFromGallery() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images);
        });
      }
    } catch (e) {
      _showSnackbar('Gagal memilih gambar: $e', isError: true);
    }
  }

  Future<void> _convertImagesToPdf({bool shareDirectly = false}) async {
    if (_selectedImages.isEmpty) {
      _showSnackbar('Pilih minimal 1 gambar untuk dikonversi', isError: true);
      return;
    }

    final title = _imgToPdfTitleController.text.trim().isEmpty
        ? 'Doc_Images_${DateTime.now().millisecondsSinceEpoch}'
        : _imgToPdfTitleController.text.trim();

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Mengonversi gambar ke PDF...';
    });

    try {
      final imagePaths = _selectedImages.map((e) => e.path).toList();
      final pdfFile = await ConversionService.imagesToPdf(
        imagePaths: imagePaths,
        outputFileName: title,
      );

      // Save as document in ScanAja database
      DocumentModel doc = DocumentModel(
        title: title,
        folderName: _imgToPdfFolder,
        createdAt: DateTime.now(),
      );
      doc = await DatabaseHelper.instance.createDocument(doc);

      for (int i = 0; i < imagePaths.length; i++) {
        await DatabaseHelper.instance.addPage(
          DocumentPageModel(
            documentId: doc.id!,
            imagePath: imagePaths[i],
            pageIndex: i,
          ),
        );
      }

      if (shareDirectly) {
        await Share.shareXFiles([XFile(pdfFile.path)], text: 'Hasil Konversi PDF: $title');
      }

      _showSnackbar('Berhasil mengonversi dan menyimpan PDF!');
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showSnackbar('Gagal konversi: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- PDF to Images Methods ---
  Future<void> _pickPdfFile() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (files.isNotEmpty && files.first.path != null) {
        final file = File(files.first.path!);
        setState(() {
          _selectedPdfFile = file;
          _pdfToImgTitleController.text =
              files.first.name.replaceAll('.pdf', '');
        });
      }
    } catch (e) {
      _showSnackbar('Gagal memilih file PDF: $e', isError: true);
    }
  }

  Future<void> _convertPdfToImages() async {
    if (_selectedPdfFile == null) {
      _showSnackbar('Pilih file PDF terlebih dahulu', isError: true);
      return;
    }

    final title = _pdfToImgTitleController.text.trim().isEmpty
        ? 'Doc_Extracted_${DateTime.now().millisecondsSinceEpoch}'
        : _pdfToImgTitleController.text.trim();

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Mengekstrak halaman PDF menjadi gambar...';
    });

    try {
      final imagePaths = await ConversionService.pdfToImages(
        pdfPath: _selectedPdfFile!.path,
        outputPrefix: title,
      );

      if (imagePaths.isEmpty) {
        _showSnackbar('Tidak ada halaman yang dapat diekstrak dari PDF', isError: true);
        return;
      }

      // Perform OCR and save as a document in ScanAja
      DocumentModel doc = DocumentModel(
        title: title,
        folderName: _pdfToImgFolder,
        createdAt: DateTime.now(),
      );
      doc = await DatabaseHelper.instance.createDocument(doc);

      String combinedOcr = '';
      for (int i = 0; i < imagePaths.length; i++) {
        final text = await ScannerService.extractText(imagePaths[i]);
        if (text.isNotEmpty) combinedOcr += '$text\n\n';

        await DatabaseHelper.instance.addPage(
          DocumentPageModel(
            documentId: doc.id!,
            imagePath: imagePaths[i],
            pageIndex: i,
          ),
        );
      }

      doc.extractedText = combinedOcr;
      await DatabaseHelper.instance.updateDocument(doc);

      _showSnackbar('Berhasil mengekstrak ${imagePaths.length} halaman menjadi gambar!');
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showSnackbar('Gagal mengekstrak PDF: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Convert Hub', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF2563EB),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFF2563EB),
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.picture_as_pdf_rounded), text: 'Gambar ➜ PDF'),
            Tab(icon: Icon(Icons.image_rounded), text: 'PDF ➜ Gambar'),
          ],
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF2563EB)),
                  const SizedBox(height: 16),
                  Text(
                    _loadingMessage,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildImageToPdfTab(),
                _buildPdfToImageTab(),
              ],
            ),
    );
  }

  Widget _buildImageToPdfTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Action card to select images
        InkWell(
          onTap: _pickImagesFromGallery,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_photo_alternate_rounded, size: 36, color: Color(0xFF2563EB)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pilih Gambar dari Galeri',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Bisa pilih 1 atau banyak foto sekaligus',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Metadata form
        if (_selectedImages.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nama Dokumen PDF',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _imgToPdfTitleController,
                  decoration: InputDecoration(
                    hintText: 'Masukkan nama file PDF',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Pilih Folder / Kategori',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _imgToPdfFolder,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'Uncategorized', child: Text('Tanpa Kategori')),
                    ..._folders.map((f) => DropdownMenuItem(value: f.name, child: Text(f.name))),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _imgToPdfFolder = val);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Selected images list
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Gambar Terpilih (${_selectedImages.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _selectedImages.clear()),
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                label: const Text('Hapus Semua', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),

          const SizedBox(height: 8),

          SizedBox(
            height: 130,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      width: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        image: DecorationImage(
                          image: FileImage(File(_selectedImages[index].path)),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 16,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedImages.removeAt(index);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF2563EB)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _convertImagesToPdf(shareDirectly: true),
                  icon: const Icon(Icons.share_rounded, color: Color(0xFF2563EB)),
                  label: const Text('Convert & Share', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _convertImagesToPdf(shareDirectly: false),
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Simpan ke App', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPdfToImageTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Select PDF card
        InkWell(
          onTap: _pickPdfFile,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF2F2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.picture_as_pdf_rounded, size: 36, color: Color(0xFFEF4444)),
                ),
                const SizedBox(height: 12),
                Text(
                  _selectedPdfFile != null
                      ? 'PDF Terpilih: ${_selectedPdfFile!.path.split(Platform.pathSeparator).last}'
                      : 'Pilih Dokumen PDF',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedPdfFile != null
                      ? 'Ketuk untuk mengganti file PDF'
                      : 'Ekstrak tiap halaman menjadi foto gambar JPG',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        if (_selectedPdfFile != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nama Dokumen Hasil Ekstraksi',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pdfToImgTitleController,
                  decoration: InputDecoration(
                    hintText: 'Nama dokumen',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Pilih Folder / Kategori',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _pdfToImgFolder,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'Uncategorized', child: Text('Tanpa Kategori')),
                    ..._folders.map((f) => DropdownMenuItem(value: f.name, child: Text(f.name))),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _pdfToImgFolder = val);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _convertPdfToImages,
            icon: const Icon(Icons.photo_library_rounded),
            label: const Text(
              'Ekstrak Halaman & Simpan ke ScanAja',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ],
    );
  }
}
