import 'dart:io';
import 'package:flutter/material.dart';
import '../models/document_model.dart';
import '../services/database_helper.dart';

class ReorderPagesScreen extends StatefulWidget {
  final DocumentModel document;
  final List<DocumentPageModel> pages;

  const ReorderPagesScreen({
    Key? key,
    required this.document,
    required this.pages,
  }) : super(key: key);

  @override
  _ReorderPagesScreenState createState() => _ReorderPagesScreenState();
}

class _ReorderPagesScreenState extends State<ReorderPagesScreen> {
  late List<DocumentPageModel> _currentPages;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentPages = List.from(widget.pages);
  }

  Future<void> _saveOrder() async {
    setState(() => _isSaving = true);
    try {
      await DatabaseHelper.instance.reorderPages(widget.document.id!, _currentPages);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan urutan: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atur Urutan Halaman'),
        actions: [
          _isSaving
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.check, color: Color(0xFF10B981)),
                  tooltip: 'Simpan',
                  onPressed: _saveOrder,
                ),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: _currentPages.length,
        onReorder: (int oldIndex, int newIndex) {
          setState(() {
            if (newIndex > oldIndex) {
              newIndex -= 1;
            }
            final item = _currentPages.removeAt(oldIndex);
            _currentPages.insert(newIndex, item);
          });
        },
        itemBuilder: (context, index) {
          final page = _currentPages[index];
          return Card(
            key: ValueKey(page.id),
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            child: ListTile(
              leading: Image.file(
                File(page.imagePath),
                width: 50,
                height: 70,
                fit: BoxFit.cover,
              ),
              title: Text('Halaman ${index + 1}'),
              subtitle: Text(page.imagePath.split('/').last),
              trailing: const Icon(Icons.drag_handle),
            ),
          );
        },
      ),
    );
  }
}
