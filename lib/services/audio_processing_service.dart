import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'cnn_analysis_service.dart';

class AudioProcessingService {

  static final Map<String, List<AudioAnalysisResult>> _analysisResults = {};
  static final List<AudioAnalysisResult> _latestResults = [];

  static List<AudioAnalysisResult>? getResultsForFile(String filePath) {
    return _analysisResults[filePath];
  }

  static List<AudioAnalysisResult> getLatestResults() {
    return List.from(_latestResults);
  }

  static Map<String, List<AudioAnalysisResult>> getAllResults() {
    developer.log('📊 getAllResults called - ${_analysisResults.length} files with results');
    return Map.from(_analysisResults);
  }

  static void clearResultsForFile(String filePath) {
    developer.log('🗑️ Clearing results for file: $filePath');
    _analysisResults.remove(filePath);
  }

  static void clearAllResults() {
    developer.log('🗑️ Clearing all results...');
    _analysisResults.clear();
    _latestResults.clear();
    developer.log('🗑️ Cleared all results');
  }

  static Future<List<AudioAnalysisResult>> processAudioFile({
    required String filePath,
  }) async {
    developer.log('='*70);
    developer.log('🎯 AudioProcessingService: Starting Python CNN processing');
    developer.log('📁 File: $filePath');
    developer.log('='*70);

    try {

      print('🔍 Checking if CNN analysis is available...');
      final isAvailable = await CNNAnalysisService.isAvailable();
      print('📊 isAvailable result: $isAvailable');

      if (!isAvailable) {
        print('❌ CNN analysis not available, returning empty results');
        print('   This means isAvailable() returned false');
        print('   Check logs above for why (missing service file or model)');
        return [];
      }

      print('✅ CNN analysis is available - proceeding...');

      print('🤖 AudioProcessingService: Calling CNNAnalysisService.analyzeAudioFile()...');
      print('   This will call the Python service to segment and analyze audio');

      final stopwatch = Stopwatch()..start();
      final cnnAnalysis = await CNNAnalysisService.analyzeAudioFile(
        audioFilePath: filePath,
      );
      stopwatch.stop();

      print('⏱️  Python service call completed in ${stopwatch.elapsedMilliseconds}ms');

      print('📊 Checking if analysis was successful...');
      print('   isSuccessful: ${cnnAnalysis.isSuccessful}');
      print('   hasEvents: ${cnnAnalysis.getSummary()['hasEvents']}');
      print('   eventCount: ${cnnAnalysis.getSummary()['segmentCount']}');

      if (!cnnAnalysis.isSuccessful) {
        final errorMsg = cnnAnalysis.errorMessage ?? 'Unknown error';
        print('❌ Python CNN analysis failed: $errorMsg');
        print('   Summary: ${cnnAnalysis.getSummary()}');
        throw Exception('Python CNN analysis failed: $errorMsg');
      }

      print('✅ Analysis was successful - converting results...');

      final cnnResults = cnnAnalysis.toAudioAnalysisResults();
      print('📋 Converted ${cnnResults.length} raw events to AudioAnalysisResult format');

      final audioResults = cnnResults.map((cnnResult) {
        var confidence = cnnResult['confidence'] as double? ?? 0.0;
        if (confidence > 1.0) {
          confidence = confidence / 100.0;
        }
        confidence = confidence.clamp(0.0, 1.0);

        var probability = cnnResult['probability'] as int?;
        if (probability == null || probability > 100) {
          probability = (confidence * 100).round();
        }

        return AudioAnalysisResult.fromMap({
          'fileIndex': cnnResult['seconds'] ?? 0,
          'success': true,
          'probableMatches': [cnnResult['type'] ?? 'Event'],
          'confidence': confidence,
          'probability': probability,
          'source': cnnResult['source'] ?? 'cnn_model',
          'modelVersion': cnnResult['model_version'] ?? 'v1',
          't0': cnnResult['t0'] ?? 0,
          't1': cnnResult['t1'] ?? 0,
          'type': cnnResult['type'] ?? 'Event',
        });
      }).toList();

      developer.log('📊 Final audio results: ${audioResults.length} events');
      for (int i = 0; i < audioResults.length && i < 3; i++) {
        final result = audioResults[i];
        developer.log('   Event $i: ${result.type} at ${result.t0}ms-${result.t1}ms (prob: ${result.probability}%)');
      }
      if (audioResults.length > 3) {
        developer.log('   ... and ${audioResults.length - 3} more events');
      }

      _storeResults(filePath, audioResults);

      developer.log('='*70);
      developer.log('✅ Python CNN analysis completed: ${audioResults.length} events found');
      developer.log('='*70);
      return audioResults;

    } catch (e) {
      developer.log('❌ AudioProcessingService error: $e');
      rethrow;
    }
  }

  static void _storeResults(String filePath, List<AudioAnalysisResult> results) {
    developer.log('💾 _storeResults called with ${results.length} results for: $filePath');

    _analysisResults[filePath] = results;
    _latestResults.clear();
    _latestResults.addAll(results);

    developer.log('💾 Stored ${results.length} results for file: $filePath');
    developer.log('📊 Total files with results: ${_analysisResults.length}');
    developer.log('📊 Latest results count: ${_latestResults.length}');

    developer.log('🔍 Verification - stored results for $filePath:');
    final storedResults = _analysisResults[filePath];
    if (storedResults != null) {
      for (int i = 0; i < storedResults.length; i++) {
        developer.log('📋 Stored result $i: ${storedResults[i]}');
      }
    }
  }

}

class AudioAnalysisResult {
  final int fileIndex;
  final bool success;
  final List<String> probableMatches;
  final double? confidence;
  final int? probability;
  final String? severity;
  final String? source;
  final String? modelVersion;
  final int? t0;
  final int? t1;
  final String? type;

  AudioAnalysisResult({
    required this.fileIndex,
    required this.success,
    required this.probableMatches,
    this.confidence,
    this.probability,
    this.severity,
    this.source,
    this.modelVersion,
    this.t0,
    this.t1,
    this.type,
  });

  factory AudioAnalysisResult.fromMap(Map<String, dynamic> map) {
    return AudioAnalysisResult(
      fileIndex: map['fileIndex'] ?? 0,
      success: map['success'] ?? false,
      probableMatches: List<String>.from(map['probableMatches'] ?? []),
      confidence: map['confidence']?.toDouble(),
      probability: map['probability']?.toInt(),
      severity: map['severity'] as String?,
      source: map['source'] as String?,
      modelVersion: map['modelVersion'] as String?,
      t0: map['t0']?.toInt(),
      t1: map['t1']?.toInt(),
      type: map['type'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fileIndex': fileIndex,
      'success': success,
      'probableMatches': probableMatches,
      if (confidence != null) 'confidence': confidence,
      if (probability != null) 'probability': probability,
      if (severity != null) 'severity': severity,
      if (source != null) 'source': source,
      if (modelVersion != null) 'modelVersion': modelVersion,
      if (t0 != null) 't0': t0,
      if (t1 != null) 't1': t1,
      if (type != null) 'type': type,
    };
  }

  @override
  String toString() {
    return 'AudioAnalysisResult(fileIndex: $fileIndex, success: $success, matches: ${probableMatches.length}, probableMatches: $probableMatches, confidence: $confidence, source: $source)';
  }
}
