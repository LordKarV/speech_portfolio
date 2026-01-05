import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:speech_app/models/recording.dart';
import 'dart:developer' as developer;

class RecordingRepository {
  static const String _collectionName = 'recordings';
  static const String _storagePath = 'recordings';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _currentUserId => _auth.currentUser?.uid;

  Future<Recording> saveRecording({
    required String title,
    required String localFilePath,
    required Duration duration,
    Map<String, dynamic>? classifications,
    Map<String, dynamic>? spectrogramData,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    developer.log('💾 RecordingRepository: Saving recording "$title"');

    try {

      final audioUrl = await _uploadAudioFile(localFilePath);
      developer.log('☁️ RecordingRepository: Audio uploaded to: $audioUrl');

      final recording = Recording(
        id: '',
        userId: _currentUserId!,
        title: title,
        audioUrl: audioUrl,
        localFilePath: localFilePath,
        duration: duration,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        classifications: classifications,
        spectrogramData: spectrogramData,
        isUploaded: true,
      );

      final docRef = await _firestore
          .collection(_collectionName)
          .add(recording.toFirestore());

      final savedRecording = recording.copyWith(id: docRef.id);
      developer.log('✅ RecordingRepository: Recording saved with ID: ${docRef.id}');

      return savedRecording;
    } catch (e) {
      developer.log('❌ RecordingRepository: Error saving recording: $e');
      rethrow;
    }
  }

  Future<String> _uploadAudioFile(String localFilePath) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final file = File(localFilePath);
    if (!await file.exists()) {
      throw Exception('Audio file does not exist: $localFilePath');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${_currentUserId}_${timestamp}.wav';
    final storageRef = _storage.ref().child('$_storagePath/$fileName');

    developer.log('☁️ RecordingRepository: Uploading file: $fileName');

    try {
      final uploadTask = storageRef.putFile(file);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      developer.log('✅ RecordingRepository: File uploaded successfully');
      return downloadUrl;
    } catch (e) {
      developer.log('❌ RecordingRepository: Upload failed: $e');
      rethrow;
    }
  }

  Future<List<Recording>> getUserRecordings({int limit = 50}) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    developer.log('📋 RecordingRepository: Fetching recordings for user: $_currentUserId');

    try {
      final querySnapshot = await _firestore
          .collection(_collectionName)
          .where('userId', isEqualTo: _currentUserId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      final recordings = querySnapshot.docs
          .map((doc) => Recording.fromFirestore(doc))
          .toList();

      developer.log('✅ RecordingRepository: Found ${recordings.length} recordings');
      return recordings;
    } catch (e) {
      developer.log('❌ RecordingRepository: Error fetching recordings: $e');
      rethrow;
    }
  }

  Future<List<Recording>> getRecentRecordings({int limit = 6}) async {
    return getUserRecordings(limit: limit);
  }

  Future<Recording?> getRecording(String recordingId) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    developer.log('🔍 RecordingRepository: Fetching recording: $recordingId');

    try {
      final doc = await _firestore
          .collection(_collectionName)
          .doc(recordingId)
          .get();

      if (!doc.exists) {
        developer.log('⚠️ RecordingRepository: Recording not found: $recordingId');
        return null;
      }

      final recording = Recording.fromFirestore(doc);

      if (recording.userId != _currentUserId) {
        developer.log('❌ RecordingRepository: Access denied for recording: $recordingId');
        throw Exception('Access denied');
      }

      developer.log('✅ RecordingRepository: Recording found: ${recording.title}');
      return recording;
    } catch (e) {
      developer.log('❌ RecordingRepository: Error fetching recording: $e');
      rethrow;
    }
  }

  Future<void> updateRecordingTitle(String recordingId, String newTitle) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    developer.log('✏️ RecordingRepository: Updating title for recording: $recordingId');

    try {
      await _firestore
          .collection(_collectionName)
          .doc(recordingId)
          .update({
        'title': newTitle,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      developer.log('✅ RecordingRepository: Title updated successfully');
    } catch (e) {
      developer.log('❌ RecordingRepository: Error updating title: $e');
      rethrow;
    }
  }

  Future<void> deleteRecording(String recordingId) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    developer.log('🗑️ RecordingRepository: Deleting recording: $recordingId');

    try {

      final recording = await getRecording(recordingId);
      if (recording == null) {
        throw Exception('Recording not found');
      }

      await _firestore
          .collection(_collectionName)
          .doc(recordingId)
          .delete();

      if (recording.audioUrl.isNotEmpty) {
        try {
          final ref = _storage.refFromURL(recording.audioUrl);
          await ref.delete();
          developer.log('✅ RecordingRepository: Audio file deleted from storage');
        } catch (e) {
          developer.log('⚠️ RecordingRepository: Could not delete audio file: $e');

        }
      }

      developer.log('✅ RecordingRepository: Recording deleted successfully');
    } catch (e) {
      developer.log('❌ RecordingRepository: Error deleting recording: $e');
      rethrow;
    }
  }

  Stream<List<Recording>> getUserRecordingsStream({int limit = 50}) {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    return _firestore
        .collection(_collectionName)
        .where('userId', isEqualTo: _currentUserId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Recording.fromFirestore(doc))
            .toList());
  }
}
