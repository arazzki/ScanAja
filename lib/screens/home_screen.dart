import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/document_model.dart';
import '../models/folder_model.dart';
import '../services/database_helper.dart';
import '../services/scanner_service.dart';
import '../services/pdf_service.dart';
import 'document_detail_screen.dart';
import 'convert_screen.dart';
import 'sign_document_screen.dart';
import '../main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<DocumentModel> _documents = [];
  List<FolderModel> _folders = [];
  String _selectedFolder = 'Semua';
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    final docs = await DatabaseHelper.instance.readAllDocuments(
      folderFilter: _selectedFolder == 'Semua' ? null : _selectedFolder,
    );
    final folders = await DatabaseHelper.instance.readAllFolders();
    setState(() {
      _documents = docs;
      _folders = folders;
      _isLoading = false;
    });
  }

  Future<void> _searchDocuments(String query) async {
    setState(() => _isLoading = true);
    final docs = await DatabaseHelper.instance.searchDocuments(
      query,
      folderFilter: _selectedFolder == 'Semua' ? null : _selectedFolder,
    );
    setState(() {
      _documents = docs;
      _isLoading = false;
    });
  }

  // --- Scanning & Post-Scan Naming Dialog ---
  Future<void> _startScan() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Membuka kamera pemindai...'),
          duration: Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final imagePaths = await ScannerService.startScan();

      if (imagePaths != null && imagePaths.isNotEmpty) {
        // Show post-scan save/rename dialog
        final formattedDefaultName =
            'Scan_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}';
        
        if (!mounted) return;

        final saveResult = await _showPostScanDialog(
          defaultName: formattedDefaultName,
          pageCount: imagePaths.length,
        );

        if (saveResult != null) {
          setState(() => _isLoading = true);
          final appDir = await getApplicationDocumentsDirectory();
          String allExtractedText = '';

          // Create document
          DocumentModel newDoc = DocumentModel(
            title: saveResult['title'] ?? formattedDefaultName,
            folderName: saveResult['folder'] ?? 'Uncategorized',
            createdAt: DateTime.now(),
          );
          newDoc = await DatabaseHelper.instance.createDocument(newDoc);

          for (int i = 0; i < imagePaths.length; i++) {
            final tempPath = imagePaths[i];
            final tempFile = File(tempPath);
            final savedImage =
                await tempFile.copy('${appDir.path}/${newDoc.title}_page_$i.jpg');

            // OCR Extraction
            final text = await ScannerService.extractText(savedImage.path);
            if (text.isNotEmpty) allExtractedText += '$text\n\n';

            await DatabaseHelper.instance.addPage(
              DocumentPageModel(
                documentId: newDoc.id!,
                imagePath: savedImage.path,
                pageIndex: i,
              ),
            );
          }

          newDoc.extractedText = allExtractedText;
          await DatabaseHelper.instance.updateDocument(newDoc);
          await _refreshData();

          if (saveResult['signNow'] == true && mounted) {
            final fullDoc = (await DatabaseHelper.instance.readAllDocuments())
                .firstWhere((d) => d.id == newDoc.id);
            if (fullDoc.pages != null && fullDoc.pages!.isNotEmpty) {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      SignDocumentScreen(imagePath: fullDoc.pages!.first.imagePath),
                ),
              );
              await _refreshData();
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal scan: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>?> _showPostScanDialog({
    required String defaultName,
    required int pageCount,
  }) async {
    final titleController = TextEditingController(text: defaultName);
    String selectedFolder = _selectedFolder == 'Semua' ? 'Uncategorized' : _selectedFolder;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E3A5F) : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.check_circle_outline, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Simpan Dokumen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      Text('$pageCount halaman berhasil dipindai', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nama Dokumen', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      hintText: 'Nama file dokumen',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: theme.dividerColor)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Pilih Folder', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface, fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedFolder,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: theme.dividerColor)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: [
                      const DropdownMenuItem(value: 'Uncategorized', child: Text('Tanpa Kategori')),
                      ..._folders.map((f) => DropdownMenuItem(value: f.name, child: Text(f.name))),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedFolder = val);
                    },
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Batal', style: TextStyle(color: colorScheme.onSurfaceVariant)),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2563EB)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(context, {
                    'title': titleController.text.trim().isEmpty ? defaultName : titleController.text.trim(),
                    'folder': selectedFolder,
                    'signNow': true,
                  });
                },
                icon: const Icon(Icons.draw_rounded, size: 16, color: Color(0xFF2563EB)),
                label: const Text('Tanda Tangan', style: TextStyle(color: Color(0xFF2563EB), fontSize: 12)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(context, {
                    'title': titleController.text.trim().isEmpty ? defaultName : titleController.text.trim(),
                    'folder': selectedFolder,
                    'signNow': false,
                  });
                },
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Folder Management ---
  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Buat Folder Baru', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Nama Folder (misal: Tagihan)',
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: theme.dividerColor)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Batal', style: TextStyle(color: colorScheme.onSurfaceVariant))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Tambah'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await DatabaseHelper.instance.createFolder(name);
      setState(() => _selectedFolder = name);
      _refreshData();
    }
  }

  Future<void> _showFolderOptions(FolderModel folder) async {
    final theme = Theme.of(context);
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Folder: ${folder.name}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: theme.colorScheme.onSurface),
              ),
              const Divider(height: 24),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Color(0xFF2563EB)),
                title: const Text('Ubah Nama Folder (Rename)'),
                onTap: () {
                  Navigator.pop(context);
                  _renameFolderDialog(folder);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text('Hapus Folder', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteFolderDialog(folder);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameFolderDialog(FolderModel folder) async {
    final controller = TextEditingController(text: folder.name);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ubah Nama Folder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Nama baru folder',
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: theme.dividerColor)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Batal', style: TextStyle(color: colorScheme.onSurfaceVariant))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != folder.name) {
      await DatabaseHelper.instance.renameFolder(folder.name, newName);
      if (_selectedFolder == folder.name) {
        _selectedFolder = newName;
      }
      _refreshData();
      _showToast('Folder berhasil diubah');
    }
  }

  Future<void> _deleteFolderDialog(FolderModel folder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Hapus Folder "${folder.name}"?'),
        content: const Text('Dokumen di dalam folder ini tidak akan terhapus, melainkan dipindahkan ke "Uncategorized".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteFolder(folder.name);
      if (_selectedFolder == folder.name) {
        _selectedFolder = 'Semua';
      }
      _refreshData();
      _showToast('Folder dihapus');
    }
  }

  // --- Document Item Actions ---
  Future<void> _renameDocument(DocumentModel doc) async {
    final controller = TextEditingController(text: doc.title);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
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
            fillColor: colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: theme.dividerColor)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Batal', style: TextStyle(color: colorScheme.onSurfaceVariant))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty && newTitle != doc.title) {
      await DatabaseHelper.instance.renameDocument(doc.id!, newTitle);
      _refreshData();
      _showToast('Dokumen berhasil diubah namanya');
    }
  }

  Future<void> _deleteDocument(DocumentModel doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Dokumen?'),
        content: Text('Dokumen "${doc.title}" beserta seluruh halamannya akan dihapus permanen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (doc.pages != null) {
        for (var page in doc.pages!) {
          final file = File(page.imagePath);
          if (await file.exists()) await file.delete();
        }
      }
      await DatabaseHelper.instance.deleteDocument(doc.id!);
      _refreshData();
      _showToast('Dokumen dihapus');
    }
  }

  Future<void> _sharePdf(DocumentModel doc) async {
    setState(() => _isLoading = true);
    try {
      final pdfFile = await PdfService.generatePdf(doc);
      await Share.shareXFiles([XFile(pdfFile.path)], text: 'Dokumen ScanAja: ${doc.title}');
    } catch (e) {
      _showToast('Gagal membagikan PDF: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.document_scanner_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ScanAja',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: colorScheme.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Smart Scanner & Convert',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<ThemeMode>(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark 
                    ? const Color(0xFF334155) 
                    : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.brightness_6_rounded, 
                color: isDark 
                    ? const Color(0xFF38BDF8) 
                    : const Color(0xFF2563EB), 
                size: 20
              ),
            ),
            tooltip: 'Pilih Tema',
            onSelected: (ThemeMode mode) {
              themeNotifier.value = mode;
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<ThemeMode>>[
              const PopupMenuItem<ThemeMode>(
                value: ThemeMode.system,
                child: Text('Otomatis'),
              ),
              const PopupMenuItem<ThemeMode>(
                value: ThemeMode.light,
                child: Text('Terang'),
              ),
              const PopupMenuItem<ThemeMode>(
                value: ThemeMode.dark,
                child: Text('Gelap'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Convert Hub',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark 
                    ? const Color(0xFF334155) 
                    : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.transform_rounded, 
                color: isDark 
                    ? const Color(0xFF38BDF8) 
                    : const Color(0xFF2563EB), 
                size: 20
              ),
            ),
            onPressed: () async {
              final res = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ConvertScreen()),
              );
              if (res == true) _refreshData();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        color: const Color(0xFF2563EB),
        child: Column(
          children: [
            // Search Bar
            Container(
              color: colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _searchController,
                onChanged: _searchDocuments,
                decoration: InputDecoration(
                  hintText: 'Cari judul, teks OCR, atau folder...',
                  hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  prefixIcon: Icon(Icons.search_rounded, color: colorScheme.onSurfaceVariant, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _refreshData();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),

            // Folders Horizontal Filter Bar
            Container(
              height: 48,
              color: colorScheme.surface,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildFolderChip('Semua', isSpecial: true),
                  ..._folders.map((f) => _buildFolderChip(f.name, folderModel: f)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: ActionChip(
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      side: BorderSide.none,
                      avatar: const Icon(Icons.add, size: 16, color: Color(0xFF2563EB)),
                      label: const Text('+ Folder', style: TextStyle(color: Color(0xFF2563EB), fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: _showCreateFolderDialog,
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: theme.dividerColor),

            // Documents Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
                  : _documents.isEmpty
                      ? _buildEmptyState()
                      : _buildDocumentGrid(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: _startScan,
        icon: const Icon(Icons.document_scanner_rounded),
        label: const Text('Smart Scan', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.2)),
      ),
    );
  }

  Widget _buildFolderChip(String name, {bool isSpecial = false, FolderModel? folderModel}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = _selectedFolder == name;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: GestureDetector(
        onLongPress: folderModel != null ? () => _showFolderOptions(folderModel) : null,
        child: ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
                color: isSelected ? Colors.white : colorScheme.onSurfaceVariant,
              )),
              if (folderModel != null && isSelected) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _showFolderOptions(folderModel),
                  child: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
                ),
              ],
            ],
          ),
          selected: isSelected,
          selectedColor: const Color(0xFF2563EB),
          backgroundColor: colorScheme.surfaceContainerHighest,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onSelected: (selected) {
            if (selected) {
              setState(() => _selectedFolder = name);
              _refreshData();
            }
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E3A5F) : const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_open_rounded,
                size: 64,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Belum ada dokumen',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Tekan tombol Smart Scan untuk memindai berkas atau gunakan fitur Convert Hub.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentGrid() {
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');
    final theme = Theme.of(context);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: _documents.length,
      itemBuilder: (context, index) {
        final doc = _documents[index];
        final thumbnailPath = (doc.pages != null && doc.pages!.isNotEmpty)
            ? doc.pages!.first.imagePath
            : null;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => DocumentDetailScreen(document: doc)),
            ).then((_) => _refreshData());
          },
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Thumbnail Image with Overlay Badges
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      thumbnailPath != null
                          ? Image.file(
                              File(thumbnailPath),
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.image_not_supported_rounded, color: Colors.grey),
                            ),
                      
                      // Page count badge
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${doc.pages?.length ?? 1} Hlm',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),

                      // More options menu
                      Positioned(
                        top: 4,
                        right: 4,
                        child: PopupMenuButton<String>(
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface.withOpacity(0.9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.more_vert, size: 16, color: theme.colorScheme.onSurface),
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onSelected: (value) {
                            if (value == 'rename') _renameDocument(doc);
                            if (value == 'share') _sharePdf(doc);
                            if (value == 'delete') _deleteDocument(doc);
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'rename',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 18, color: Color(0xFF2563EB)),
                                  SizedBox(width: 8),
                                  Text('Ubah Nama'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'share',
                              child: Row(
                                children: [
                                  Icon(Icons.share_rounded, size: 18, color: Color(0xFF10B981)),
                                  SizedBox(width: 8),
                                  Text('Bagikan PDF'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Hapus', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Card Footer
                Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.folder_outlined, size: 12, color: Color(0xFF2563EB)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              doc.folderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateFormat.format(doc.createdAt),
                        style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
