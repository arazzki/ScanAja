import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/document_model.dart';
import '../models/folder_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('scanaja.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textNullType = 'TEXT';
    const intType = 'INTEGER NOT NULL';

    await db.execute('''
CREATE TABLE documents (
  id $idType,
  title $textType,
  folderName $textType,
  extractedText $textNullType,
  createdAt $textType
)
''');

    await db.execute('''
CREATE TABLE document_pages (
  id $idType,
  documentId $intType,
  imagePath $textType,
  pageIndex $intType,
  FOREIGN KEY (documentId) REFERENCES documents (id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE folders (
  id $idType,
  name $textType UNIQUE,
  colorHex $textNullType,
  createdAt $textType
)
''');

    // Default seed folder
    await db.insert('folders', {
      'name': 'Pribadi',
      'colorHex': '#3B82F6',
      'createdAt': DateTime.now().toIso8601String(),
    });
    await db.insert('folders', {
      'name': 'Kantor / Tugas',
      'colorHex': '#10B981',
      'createdAt': DateTime.now().toIso8601String(),
    });
    await db.insert('folders', {
      'name': 'Struk / Invoice',
      'colorHex': '#F59E0B',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE documents ADD COLUMN folderName TEXT DEFAULT "Uncategorized"');
      await db.execute('ALTER TABLE documents ADD COLUMN extractedText TEXT');
      await db.execute('''
        CREATE TABLE document_pages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          documentId INTEGER NOT NULL,
          imagePath TEXT NOT NULL,
          pageIndex INTEGER NOT NULL,
          FOREIGN KEY (documentId) REFERENCES documents (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS folders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          colorHex TEXT,
          createdAt TEXT NOT NULL
        )
      ''');
      // Insert default seed folders
      try {
        await db.insert('folders', {
          'name': 'Pribadi',
          'colorHex': '#3B82F6',
          'createdAt': DateTime.now().toIso8601String(),
        });
        await db.insert('folders', {
          'name': 'Kantor / Tugas',
          'colorHex': '#10B981',
          'createdAt': DateTime.now().toIso8601String(),
        });
        await db.insert('folders', {
          'name': 'Struk / Invoice',
          'colorHex': '#F59E0B',
          'createdAt': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    }
  }

  // --- Folders ---
  Future<List<FolderModel>> readAllFolders() async {
    final db = await instance.database;
    final result = await db.query('folders', orderBy: 'name ASC');
    return result.map((json) => FolderModel.fromMap(json)).toList();
  }

  Future<FolderModel> createFolder(String name, {String? colorHex}) async {
    final db = await instance.database;
    final folder = FolderModel(
      name: name,
      colorHex: colorHex ?? '#3B82F6',
      createdAt: DateTime.now(),
    );
    final id = await db.insert('folders', folder.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    folder.id = id;
    return folder;
  }

  Future<void> renameFolder(String oldName, String newName) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.update(
        'folders',
        {'name': newName},
        where: 'name = ?',
        whereArgs: [oldName],
      );
      // Update all documents in this folder
      await txn.update(
        'documents',
        {'folderName': newName},
        where: 'folderName = ?',
        whereArgs: [oldName],
      );
    });
  }

  Future<void> deleteFolder(String folderName) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'folders',
        where: 'name = ?',
        whereArgs: [folderName],
      );
      // Move documents to Uncategorized
      await txn.update(
        'documents',
        {'folderName': 'Uncategorized'},
        where: 'folderName = ?',
        whereArgs: [folderName],
      );
    });
  }

  // --- Documents ---
  Future<DocumentModel> createDocument(DocumentModel document) async {
    final db = await instance.database;
    final id = await db.insert('documents', document.toMap());
    document.id = id;
    return document;
  }

  Future<List<DocumentModel>> readAllDocuments({String? folderFilter}) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> result;
    if (folderFilter != null && folderFilter.isNotEmpty && folderFilter != 'Semua') {
      result = await db.query(
        'documents',
        where: 'folderName = ?',
        whereArgs: [folderFilter],
        orderBy: 'createdAt DESC',
      );
    } else {
      result = await db.query('documents', orderBy: 'createdAt DESC');
    }
    
    List<DocumentModel> docs = result.map((json) => DocumentModel.fromMap(json)).toList();
    for (var doc in docs) {
      doc.pages = await getPagesForDocument(doc.id!);
    }
    return docs;
  }

  Future<List<DocumentModel>> searchDocuments(String query, {String? folderFilter}) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> result;
    if (folderFilter != null && folderFilter.isNotEmpty && folderFilter != 'Semua') {
      result = await db.query(
        'documents',
        where: '(title LIKE ? OR extractedText LIKE ?) AND folderName = ?',
        whereArgs: ['%$query%', '%$query%', folderFilter],
        orderBy: 'createdAt DESC',
      );
    } else {
      result = await db.query(
        'documents',
        where: 'title LIKE ? OR extractedText LIKE ? OR folderName LIKE ?',
        whereArgs: ['%$query%', '%$query%', '%$query%'],
        orderBy: 'createdAt DESC',
      );
    }
    List<DocumentModel> docs = result.map((json) => DocumentModel.fromMap(json)).toList();
    for (var doc in docs) {
      doc.pages = await getPagesForDocument(doc.id!);
    }
    return docs;
  }

  Future<int> updateDocument(DocumentModel document) async {
    final db = await instance.database;
    return db.update(
      'documents',
      document.toMap(),
      where: 'id = ?',
      whereArgs: [document.id],
    );
  }

  Future<int> renameDocument(int id, String newTitle) async {
    final db = await instance.database;
    return db.update(
      'documents',
      {'title': newTitle},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteDocument(int id) async {
    final db = await instance.database;
    await db.delete('document_pages', where: 'documentId = ?', whereArgs: [id]);
    return await db.delete('documents', where: 'id = ?', whereArgs: [id]);
  }

  // --- Pages ---
  Future<DocumentPageModel> addPage(DocumentPageModel page) async {
    final db = await instance.database;
    final id = await db.insert('document_pages', page.toMap());
    page.id = id;
    return page;
  }

  Future<int> updatePageImagePath(int pageId, String newImagePath) async {
    final db = await instance.database;
    return db.update(
      'document_pages',
      {'imagePath': newImagePath},
      where: 'id = ?',
      whereArgs: [pageId],
    );
  }

  Future<int> deletePage(int pageId) async {
    final db = await instance.database;
    return db.delete('document_pages', where: 'id = ?', whereArgs: [pageId]);
  }

  Future<List<DocumentPageModel>> getPagesForDocument(int documentId) async {
    final db = await instance.database;
    final result = await db.query(
      'document_pages',
      where: 'documentId = ?',
      whereArgs: [documentId],
      orderBy: 'pageIndex ASC',
    );
    return result.map((json) => DocumentPageModel.fromMap(json)).toList();
  }

  Future<void> reorderPages(int docId, List<DocumentPageModel> newOrder) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      for (int i = 0; i < newOrder.length; i++) {
        await txn.update(
          'document_pages',
          {'pageIndex': i},
          where: 'id = ? AND documentId = ?',
          whereArgs: [newOrder[i].id, docId],
        );
      }
    });
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
