class Folder {
  final String id;
  final String name;
  final String? parentId;
  final int position;
  final DateTime createdAt;

  const Folder({
    required this.id,
    required this.name,
    this.parentId,
    this.position = 0,
    required this.createdAt,
  });

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'] as String,
      name: map['name'] as String,
      parentId: map['parent_id'] as String?,
      position: (map['position'] as int?) ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {'name': name, if (parentId != null) 'parent_id': parentId};
  }
}
