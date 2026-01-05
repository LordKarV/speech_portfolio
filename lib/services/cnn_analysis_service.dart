import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class CNNAnalysisService {
  static const MethodChannel _coreMLChannel = MethodChannel('coreml_stuttering_classifier');

  static Future<Map<String, dynamic>> analyzeAudioFile({
    required String audioFilePath,
    String? modelPath,
  }) async {
    print('🤖 CNNAnalysisService: Starting CNN analysis for: $audioFilePath');

    try {

      if (Platform.isIOS) {
        print('🍎 CNNAnalysisService: Using Core ML (iOS)');
        return await _runCoreMLAnalysis(audioFilePath);
      } else {
        print('🐍 CNNAnalysisService: Using Python backend');
        return await _runPythonAnalysis(audioFilePath, modelPath);
      }

    } catch (e) {
      print('❌ CNNAnalysisService: Error during CNN analysis: $e');

      return {
        'events': <Map<String, dynamic>>[],
        'summary': {
          'segmentCount': 0,
          'hasEvents': false,
          'error': e.toString(),
        },
        'processing_info': {
          'error': e.toString(),
          'model_path': modelPath,
          'input_file': audioFilePath,
          'is_real': true,
          'no_simulation': true,
        },
      };
    }
  }

  static Future<Map<String, dynamic>> _runCoreMLAnalysis(String audioFilePath) async {
    try {
      print('🍎 CoreML: Calling native iOS method...');

      final result = await _coreMLChannel.invokeMethod('analyzeAudioFile', {
        'audioFilePath': audioFilePath,
      });

      if (result == null) {
        throw Exception('Core ML analysis returned null');
      }

      print('✅ CoreML: Analysis complete');
      return Map<String, dynamic>.from(result);

    } catch (e) {
      print('❌ CoreML: Analysis failed: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> _runPythonAnalysis(String audioFilePath, String? modelPath) async {
    try {

      if (Platform.isIOS) {
        print('❌ iOS detected: Process.run() is not supported on iOS');
        print('   iOS security restrictions prevent spawning external processes.');
        print('   Solutions:');
        print('   1. Convert PyTorch model to Core ML for iOS');
        print('   2. Use TensorFlow Lite with Flutter plugin');
        print('   3. Use a server-based API approach');
        print('   4. Test on Android or desktop instead');
        throw Exception(
          'CNN analysis is not available on iOS. iOS does not allow spawning external processes. '
          'Please use Android, desktop, or implement a Core ML/TensorFlow Lite solution for iOS.'
        );
      }

      final pythonServicePath = await _getPythonServicePath();
      final pythonServicesDir = await _getPythonServicesDirectory();
      final pythonExecutable = '$pythonServicesDir/venv/bin/python3';

      print('='*70);
      print('🐍 CALLING PYTHON SERVICE');
      print('='*70);
      print('📁 Python executable: $pythonExecutable');
      print('📁 Service script: $pythonServicePath');
      print('📁 Audio file: $audioFilePath');
      print('📁 Working directory: $pythonServicesDir');

      final pythonFile = File(pythonExecutable);
      final serviceFile = File(pythonServicePath);
      final audioFile = File(audioFilePath);

      developer.log('🔍 File checks:');
      developer.log('   Python exists: ${await pythonFile.exists()}');
      developer.log('   Service exists: ${await serviceFile.exists()}');
      developer.log('   Audio exists: ${await audioFile.exists()}');

      if (!await pythonFile.exists()) {
        throw Exception('Python executable not found: $pythonExecutable');
      }
      if (!await serviceFile.exists()) {
        throw Exception('Service script not found: $pythonServicePath');
      }
      if (!await audioFile.exists()) {
        throw Exception('Audio file not found: $audioFilePath');
      }

      print('✅ All files exist - calling Python service...');
      print('   This will:');
      print('   1. Load audio file');
      print('   2. Segment into 3-second windows (1-second hop)');
      print('   3. Extract features (Log-Mel spectrograms)');
      print('   4. Pass each window through the model');
      print('   5. Post-process and return events');

      final stopwatch = Stopwatch()..start();

      final result = await Process.run(
        pythonExecutable,
        [pythonServicePath, audioFilePath],
        workingDirectory: pythonServicesDir,
      );

      stopwatch.stop();

      print('⏱️  Python process completed in ${stopwatch.elapsedMilliseconds}ms');
      print('📊 Exit code: ${result.exitCode}');

      if (result.exitCode != 0) {
        print('❌ Python script failed with exit code: ${result.exitCode}');
        print('❌ Error output: ${result.stderr}');
        print('📄 Stdout (first 500 chars): ${result.stdout.substring(0, result.stdout.length > 500 ? 500 : result.stdout.length)}');
        throw Exception('Python CNN analysis failed: ${result.stderr}');
      }

      print('✅ Python script executed successfully');
      print('📄 Output length: ${result.stdout.length} characters');

      Map<String, dynamic> jsonResult;
      try {
        jsonResult = jsonDecode(result.stdout) as Map<String, dynamic>;
      } catch (e) {
        developer.log('❌ Failed to parse JSON output');
        developer.log('📄 First 1000 chars of output: ${result.stdout.substring(0, result.stdout.length > 1000 ? 1000 : result.stdout.length)}');
        rethrow;
      }

      final eventsCount = jsonResult['events']?.length ?? 0;
      final hasEvents = jsonResult['summary']?['hasEvents'] ?? false;

      print('='*70);
      print('📊 PYTHON SERVICE RESULTS');
      print('='*70);
      print('   Events: $eventsCount');
      print('   hasEvents: $hasEvents');
      print('   segmentCount: ${jsonResult['summary']?['segmentCount'] ?? 0}');
      print('='*70);

      if (eventsCount > 0) {
        print('   First event: ${jsonResult['events'][0]}');
      } else {
        print('   ⚠️  No events detected by Python service');
        print('   Raw JSON summary: ${jsonResult['summary']}');
      }

      return jsonResult;

    } catch (e, stackTrace) {
      developer.log('='*70);
      developer.log('❌ PYTHON SERVICE CALL FAILED');
      developer.log('='*70);
      developer.log('Error: $e');
      developer.log('Stack trace: $stackTrace');
      developer.log('='*70);
      throw Exception('Python CNN analysis failed: $e');
    }
  }

  static Future<String> _getPythonServicePath() async {
    final pythonServicesDir = await _getPythonServicesDirectory();
    return '$pythonServicesDir/flutter_cnn_service.py';
  }

  static Future<String> _getPythonServicesDirectory() async {

    final projectRoot = '/Users/karthikvattem/speech_app';
    final pythonServicesDir = '$projectRoot/python_services';

    print('📁 Python services directory: $pythonServicesDir');

    final dir = Directory(pythonServicesDir);
    if (!await dir.exists()) {
      print('❌ Python services directory does not exist: $pythonServicesDir');
      throw Exception('Python services directory not found: $pythonServicesDir');
    }

    return pythonServicesDir;
  }

  static Future<bool> isAvailable() async {
    try {
      print('🔍 CNNAnalysisService.isAvailable() called');

      if (Platform.isIOS) {
        print('🍎 iOS detected: Checking Core ML model availability...');
        try {
          final loaded = await _coreMLChannel.invokeMethod('loadModel');
          final isLoaded = loaded as bool? ?? false;
          print('🍎 Core ML model loaded: $isLoaded');
          if (!isLoaded) {
            print('⚠️ Core ML model failed to load. Check Xcode console for Swift error messages.');
            print('   Swift print() statements appear in Xcode console, not Flutter logs!');
          }
          return isLoaded;
        } on PlatformException catch (e) {
          print('❌ Core ML PlatformException: ${e.code} - ${e.message}');
          print('   Details: ${e.details}');
          return false;
        } catch (e) {
          print('❌ Core ML model not available: $e');
          return false;
        }
      }

      final pythonServicePath = await _getPythonServicePath();
      final pythonServicesDir = await _getPythonServicesDirectory();

      print('📁 Python service path: $pythonServicePath');
      print('📁 Python services dir: $pythonServicesDir');

      final serviceFile = File(pythonServicePath);
      if (!await serviceFile.exists()) {
        print('❌ Python CNN service not found at: $pythonServicePath');
        return false;
      }
      print('✅ Python service file exists');

      final modelsDir = Directory('$pythonServicesDir/models');
      if (!await modelsDir.exists()) {
        print('❌ Models directory not found: ${modelsDir.path}');
        return false;
      }
      print('✅ Models directory exists');

      final modelName = 'best_repetitions_fluent_logmel_cnn.pt';
      final modelPath = '${modelsDir.path}/$modelName';
      final modelFile = File(modelPath);

      if (!await modelFile.exists()) {
        print('❌ Required model not found: $modelName');
        print('   Expected path: $modelPath');
        return false;
      }

      print('✅ Found required model: $modelName');

      print('✅ CNN analysis is available - returning true');
      return true;

    } catch (e) {
      developer.log('❌ Error checking CNN availability: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getModelInfo() async {
    try {
      final pythonServicesDir = await _getPythonServicesDirectory();
      final modelPath = '$pythonServicesDir/models/best_repetitions_fluent_logmel_cnn.pt';
      final modelFile = File(modelPath);

      if (await modelFile.exists()) {
        final stat = await modelFile.stat();
        return {
          'available': true,
          'model_path': modelPath,
          'model_size': stat.size,
          'model_type': 'PyTorch',
          'model_name': 'best_repetitions_fluent_logmel_cnn.pt',
          'accuracy': '71.3%',
          'last_modified': stat.modified.toIso8601String(),
        };
      } else {
        return {
          'available': false,
          'error': 'Required PyTorch model (71% accuracy) not found: best_repetitions_fluent_logmel_cnn.pt',
        };
      }

    } catch (e) {
      return {
        'available': false,
        'error': e.toString(),
      };
    }
  }

  static Map<String, dynamic> _convertToMapStringDynamic(dynamic input) {
    if (input is Map) {
      final Map<String, dynamic> result = {};
      input.forEach((key, value) {
        final stringKey = key is String ? key : key.toString();

        if (value is Map) {
          result[stringKey] = _convertToMapStringDynamic(value);
        } else if (value is List) {
          result[stringKey] = _convertList(value);
        } else {
          result[stringKey] = value;
        }
      });
      return result;
    }
    return {};
  }

  static List<dynamic> _convertList(dynamic input) {
    if (input is List) {
      return input.map((item) {
        if (item is Map) {
          return _convertToMapStringDynamic(item);
        } else if (item is List) {
          return _convertList(item);
        } else {
          return item;
        }
      }).toList();
    }
    return [];
  }
}

extension CNNAnalysisResultsExtension on Map<String, dynamic> {

  List<Map<String, dynamic>> toAudioAnalysisResults() {
    final events = this['events'];
    if (events is! List) return [];

    return events.map((event) {
      if (event is! Map) return <String, dynamic>{};

      final eventMap = CNNAnalysisService._convertToMapStringDynamic(event);
      return {
        'type': eventMap['type'] ?? 'Event',
        'confidence': () {
          var conf = eventMap['confidence'] as double? ?? 0.0;
          if (conf > 1.0) {
            conf = conf / 100.0;
          }
          return conf.clamp(0.0, 1.0);
        }(),
        'probability': () {
          var prob = eventMap['probability'] as int? ?? 0;
          if (prob > 100) {
            var conf = prob / 100.0;
            if (conf > 1.0) {
              conf = conf / 100.0;
            }
            prob = (conf.clamp(0.0, 1.0) * 100).round();
          }
          return prob.clamp(0, 100);
        }(),
        'seconds': eventMap['seconds'] ?? 0,
        't0': eventMap['t0'] ?? 0,
        't1': eventMap['t1'] ?? 0,
        'source': eventMap['source'] ?? 'cnn_model',
        'model_version': eventMap['model_version'] ?? 'v1',
      };
    }).toList();
  }

  Map<String, dynamic> getSummary() {
    final summary = this['summary'];
    if (summary is Map) {
      return CNNAnalysisService._convertToMapStringDynamic(summary);
    }
    return {};
  }

  bool get isSuccessful {
    final summary = getSummary();
    return summary['hasEvents'] == true && summary['error'] == null;
  }

  String? get errorMessage {
    final summary = getSummary();
    return summary['error'] as String?;
  }
}