/// Gateway project model.
///
/// A project is a working directory exposed by the gateway host.
library;

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.directory,
    required this.updatedAtMs,
  });

  final String id;
  final String name;
  final String directory;
  final int updatedAtMs;

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      directory: json['directory'] as String? ?? '',
      updatedAtMs: _readInt(json['updatedAt']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'directory': directory,
      'updatedAt': updatedAtMs,
    };
  }

  static int? _readInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
