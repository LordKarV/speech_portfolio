import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class RecordingRepository {
  final _fs = FirebaseFirestore.instance;
  final _st = FirebaseStorage.instance;
  final _auth = FirebaseAuth.instance;

  String _datePath(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  Future<String> saveRecording({
    required File file,
    required String extension,
    required Duration duration,
    required int sampleRate,
    required List<Map<String, dynamic>> events,
    String title = 'Session',
    String codec = 'pcm16WAV',
    String modelVersion = 'v1',
    bool cnnAnalysisEnabled = true,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');

    final now = DateTime.now();
    final recId = _fs.collection('_').doc().id;
    final storagePath = 'recordings/$uid/${_datePath(now)}/$recId.$extension';

    final ref = _st.ref(storagePath);
    final meta = SettableMetadata(contentType: extension == 'wav' ? 'audio/wav' : 'audio/m4a');

    await ref.putFile(file, meta);

    final docRef = _fs.collection('users').doc(uid)
      .collection('recordings').doc(recId);

    final batch = _fs.batch();
    batch.set(docRef, {
      'title': title,
      'createdAt': FieldValue.serverTimestamp(),
      'durationMs': duration.inMilliseconds,
      'sampleRate': sampleRate,
      'codec': codec,
      'storagePath': storagePath,
      'modelVersion': modelVersion,
      'cnnAnalysisEnabled': cnnAnalysisEnabled,
      'summary': {
        'segmentCount': events.length,
        if (events.isNotEmpty) 'dominantType': _dominantType(events),
        if (events.isNotEmpty) 'confidence': _avgConf(events),
        'cnnEvents': events.length,
      },
      'hasEvents': events.isNotEmpty,
    });

    final evCol = docRef.collection('events');
    for (final e in events.take(1000)) {
      final evRef = evCol.doc();
      var confValue = e['conf'];
      if (confValue == null) {
        if (e['probability'] is int) {
          confValue = (e['probability'] as int) / 100.0;
        } else if (e['probability'] is double) {
          confValue = (e['probability'] as double) > 1.0 
              ? (e['probability'] as double) / 100.0 
              : (e['probability'] as double);
        } else {
          confValue = 0.0;
        }
      } else if (confValue is double && confValue > 1.0) {
        confValue = confValue / 100.0;
      }
      if (confValue is double) {
        confValue = confValue.clamp(0.0, 1.0);
      }

      batch.set(evRef, {
        't0': e['t0'] ?? (e['seconds'] as int? ?? 0) * 1000,
        't1': e['t1'] ?? ((e['seconds'] as int? ?? 0) * 1000 + 400),
        'type': e['type'] ?? 'Event',
        'conf': confValue,
        if (e['severity'] != null) 'severity': e['severity'],
      });
    }

    await batch.commit();
    return recId;
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> streamRecent({int limit = 20}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _fs.collection('users').doc(uid)
        .collection('recordings')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getRecentRecordings({int limit = 20}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];

    final snapshot = await _fs.collection('users').doc(uid)
        .collection('recordings')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs;
  }

  double _avgConf(List<Map<String, dynamic>> events) {
    if (events.isEmpty) return 0.0;
    final vals = events.map((e) {
      final p = e['probability'];
      final c = e['conf'];
      return p is int ? p / 100.0 : (c is num ? c.toDouble() : 0.0);
    }).toList();
    return vals.reduce((a, b) => a + b) / vals.length;
    }

  String _dominantType(List<Map<String, dynamic>> events) {
    final counts = <String, int>{};
    for (final e in events) {
      final t = (e['type'] ?? 'Event').toString();
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

}
