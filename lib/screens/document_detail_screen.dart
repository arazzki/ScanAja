import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/document_model.dart';
import '../models/folder_model.dart';
import '../services/database_helper.dart';
import '../services/pdf_service.dart';
import 'sign_document_screen.dart';

class DocumentDetailScreen extends StatefulWidget {
  final DocumentModel document;

  const DocumentDetailScreen({Key? key, required this.document}) : super(key: key);

  @override
  _DocumentDetailScreenState createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  late DocumentModel _doc;
  int _selectedPageIndex = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
    _refreshDoc();
  }

  Future<void> _refreshDoc() async {
    final pages = await DatabaseHelper.instance.getPagesForDocument(_doc.id!);
    setState(() {
      _doc.pages = pages;
    });
  }

  Future<void> _renameDoc() async {
    final controller = TextEditingController(text: _doc.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ubah Nama Dokumen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Nama baru dokumen',
            filled: true,
            fillColor: const Color(0xFFF1F5F9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty && newTitle != _doc.title) {
      await DatabaseHelper.instance.renameDocument(_doc.id!, newTitle);
      setState(() {
        _doc.title = newTitle;
      });
      _showToast('Nama dokumen diperbarui');
    }
  }

  Future<void> _changeFolder() async {
    final folders = await DatabaseHelper.instance.readAllFolders();
    String currentFolder = _doc.folderName;

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Pindahkan ke Folder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  RadioListTile<String>(
                    title: const Text('Tanpa Kategori (Uncategorized)'),
                    value: 'Uncategorized',
                    groupValue: currentFolder,
                    onChanged: (val) {
                      setDialogState(() => currentFolder = val!);
                    },
                  ),
                  ...folders.map((f) => RadioListTile<String>(
                        title: Text(f.name),
                        value: f.name,
                        groupValue: currentFolder,
                        onChanged: (val) {
                          setDialogState(() => currentFolder = val!);
                        },
                      )),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context, currentFolder),
                child: const Text('Terapkan'),
              ),
            ],
          );
        },
      ),
    );

    if (selected != null && selected != _doc.folderName) {
      _doc.folderName = selected;
      await DatabaseHelper.instance.updateDocument(_doc);
      setState(() {});
      _showToast('Folder dokumen diperbarui');
    }
  }

  Future<void> _signCurrentPage() async {
    if (_doc.pages == null || _doc.pages!.isEmpty) return;
    final page = _doc.pages![_selectedPageIndex];

    final signed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => SignDocumentScreen(imagePath: page.imagePath),
      ),
    );

    if (signed == true) {
      // Refresh to reload newly painted image file
      await FileImage(File(page.imagePath)).evict();
      await _refreshDoc();
      _showToast('Tanda tangan berhasil diterapkan pada Halaman ${_selectedPageIndex + 1}');
    }
  }

  Future<void> _shareAsPdf() async {
    setState(() => _isLoading = true);
    try {
      final pdfFile = await PdfService.generatePdf(_doc);
      await Share.shareXFiles([XFile(pdfFile.path)], text: 'Dokumen ScanAja: ${_doc.title}');
    } catch (e) {
      _showToast('Gagal membagikan PDF: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _copyOcrText() {
    if (_doc.extractedText == null || _doc.extractedText!.trim().isEmpty) {
      _showToast('Tidak ada teks yang dapat disalin', isError: true);
      return;
    }
    Clipboard.setData(ClipboardData(text: _doc.extractedText!));
    _showToast('Teks berhasil disalin ke clipboard!');
  }

  void _showToast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0,
          title: Text(
            _doc.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Ubah Nama',
              icon: const Icon(Icons.edit_outlined, color: Color(0xFF475569)),
              onPressed: _renameDoc,
            ),
            IconButton(
              tooltip: 'Pindahkan Folder',
              icon: const Icon(Icons.folder_outlined, color: Color(0xFF475569)),
              onPressed: _changeFolder,
            ),
            IconButton(
              tooltip: 'Bagikan PDF',
              icon: const Icon(Icons.share_rounded, color: Color(0xFF2563EB)),
              onPressed: _isLoading ? null : _shareAsPdf,
            ),
          ],
          bottom: TabBar(
            labelColor: const Color(0xFF2563EB),
            unselectedLabelColor: const Color(0xFF64748B),
            indicatorColor: const Color(0xFF2563EB),
            indicatorWeight: 3,
            tabs: [
              Tab(
                icon: const Icon(Icons.photo_library_outlined),
                text: 'Halaman (${_doc.pages?.length ?? 0})',
              ),
              const Tab(
                icon: Icon(Icons.text_snippet_outlined),
                text: 'Teks OCR',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildPagesView(dateFormat),
            _buildOcrView(),
          ],
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _signCurrentPage,
                    icon: const Icon(Icons.draw_rounded, color: Color(0xFF38BDF8)),
                    label: const Text(
                      'Tanda Tangani Halaman Ini',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: _shareAsPdf,
                  child: const Icon(Icons.picture_as_pdf_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPagesView(DateFormat dateFormat) {
    if (_doc.pages == null || _doc.pages!.isEmpty) {
      return const Center(child: Text('Tidak ada halaman dalam dokumen ini'));
    }

    return Column(
      children: [
        // Meta info bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFFF1F5F9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_open_rounded, size: 16, color: Color(0xFF2563EB)),
                  const SizedBox(width: 6),
                  Text(
                    _doc.folderName,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B), fontSize: 13),
                  ),
                ],
              ),
              Text(
                dateFormat.format(_doc.createdAt),
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
        ),

        // Page preview area
        Expanded(
          child: PageView.builder(
            itemCount: _doc.pages!.length,
            onPageChanged: (index) {
              setState(() => _selectedPageIndex = index);
            },
            itemBuilder: (context, index) {
              final page = _doc.pages![index];
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Image.file(
                        File(page.imagePath),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Page indicator dots / pills
        Container(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Halaman ${_selectedPageIndex + 1} dari ${_doc.pages!.length}',
            style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildOcrView() {
    final hasText = _doc.extractedText != null && _doc.extractedText!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Teks Hasil Ekstraksi (OCR)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
              ),
              if (hasText)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEFF6FF),
                    foregroundColor: const Color(0xFF2563EB),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _copyOcrText,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Salin Semua'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  hasText
                      ? _doc.extractedText!
                      : 'Tidak ada teks yang berhasil terdeteksi dari hasil pemindaian.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: hasText ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
