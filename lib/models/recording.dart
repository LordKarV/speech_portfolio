import 'package:cloud_firestore/cloud_firestore.dart';

class Recording {
  final String id;
  final String userId;
  final String title;
  final String audioUrl;
  final String localFilePath;
  final Duration duration;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? classifications;
  final Map<String, dynamic>? spectrogramData;
  final bool isUploaded;

  const Recording({
    required this.id,
    required this.userId,
    required this.title,
    required this.audioUrl,
    required this.localFilePath,
    required this.duration,
    required this.createdAt,
    required this.updatedAt,
    this.classifications,
    this.spectrogramData,
    this.isUploaded = false,
  });

  factory Recording.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Recording(
      id: doc.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? 'Untitled Recording',
      audioUrl: data['audioUrl'] ?? '',
      localFilePath: data['localFilePath'] ?? '',
      duration: Duration(milliseconds: data['durationMs'] ?? 0),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      classifications: data['classifications'],
      spectrogramData: data['spectrogramData'],
      isUploaded: data['isUploaded'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'title': title,
      'audioUrl': audioUrl,
      'localFilePath': localFilePath,
      'durationMs': duration.inMilliseconds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'classifications': classifications,
      'spectrogramData': spectrogramData,
      'isUploaded': isUploaded,
    };
  }

  Recording copyWith({
    String? id,
    String? userId,
    String? title,
    String? audioUrl,
    String? localFilePath,
    Duration? duration,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? classifications,
    Map<String, dynamic>? spectrogramData,
    bool? isUploaded,
  }) {
    return Recording(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      audioUrl: audioUrl ?? this.audioUrl,
      localFilePath: localFilePath ?? this.localFilePath,
      duration: duration ?? this.duration,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      classifications: classifications ?? this.classifications,
      spectrogramData: spectrogramData ?? this.spectrogramData,
      isUploaded: isUploaded ?? this.isUploaded,
    );
  }

  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      final months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return '${months[createdAt.month - 1]} ${createdAt.day}, ${createdAt.year}';
    }
  }

  @override
  String toString() {
    return 'Recording(id: $id, title: $title, duration: $formattedDuration, createdAt: $formattedDate)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Recording && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
