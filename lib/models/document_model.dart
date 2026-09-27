class DocumentPageModel {
  int? id;
  int documentId;
  String imagePath;
  int pageIndex;

  DocumentPageModel({
    this.id,
    required this.documentId,
    required this.imagePath,
    required this.pageIndex,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'documentId': documentId,
      'imagePath': imagePath,
      'pageIndex': pageIndex,
    };
  }

  factory DocumentPageModel.fromMap(Map<String, dynamic> map) {
    return DocumentPageModel(
      id: map['id'],
      documentId: map['documentId'],
      imagePath: map['imagePath'],
      pageIndex: map['pageIndex'],
    );
  }
}

class DocumentModel {
  int? id;
  String title;
  String folderName;
  String? extractedText;
  DateTime createdAt;
  List<DocumentPageModel>? pages; // Helper property, not stored directly in this table

  DocumentModel({
    this.id,
    required this.title,
    this.folderName = 'Uncategorized',
    this.extractedText,
    required this.createdAt,
    this.pages,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'folderName': folderName,
      'extractedText': extractedText,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory DocumentModel.fromMap(Map<String, dynamic> map) {
    return DocumentModel(
      id: map['id'],
      title: map['title'],
      folderName: map['folderName'] ?? 'Uncategorized',
      extractedText: map['extractedText'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}
