class FolderModel {
  int? id;
  String name;
  String? colorHex;
  DateTime createdAt;

  FolderModel({
    this.id,
    required this.name,
    this.colorHex,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'colorHex': colorHex,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory FolderModel.fromMap(Map<String, dynamic> map) {
    return FolderModel(
      id: map['id'],
      name: map['name'],
      colorHex: map['colorHex'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}
