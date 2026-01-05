import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wav/wav.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:developer' as developer;
import 'dart:typed_data';
import '../config/audio_config.dart';
import 'fft_service.dart';

class AudioData {
  final double amplitude;
  final Duration duration;
  final List<double>? spectrogramColumn;
  final double? rawDb;
  final String? filePath;

  AudioData({
    required this.amplitude, 
    required this.duration,
    this.spectrogramColumn,
    this.rawDb,
    this.filePath,
  });

  @override
  String toString() => 'AudioData(amplitude: ${amplitude.toStringAsFixed(3)}, duration: ${duration.inMilliseconds}ms, rawDb: $rawDb)';
}

class AudioService {

  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  StreamSubscription? _recorderSubscription;
  StreamSubscription? _playerSubscription;

  final StreamController<AudioData> _audioDataController = StreamController<AudioData>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();
  final StreamController<bool> _recordingStateController = StreamController<bool>.broadcast();

  Stream<AudioData> get audioDataStream => _audioDataController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<bool> get recordingStateStream => _recordingStateController.stream;

  final List<List<double>> _spectrogramData = [];
  List<List<double>> get spectrogramData => List.from(_spectrogramData);

  final List<DateTime> _columnTimestamps = [];
  DateTime? _recordingStartTime;
  Duration _processingDelay = Duration.zero;
  Duration _averageProcessingTime = Duration.zero;
  final List<Duration> _recentProcessingTimes = [];

  final List<double> _audioBuffer = [];
  static int get _bufferSize => AudioConfig.bufferSize;
  static int get _hopSize => AudioConfig.hopSize;

  double _currentAmplitude = 0.0;
  Duration _recordingDuration = Duration.zero;
  String? _currentFilePath;
  String? _lastRecordingPath;

  int _processedWindows = 0;

  bool _isRecording = false;
  bool _isInitialized = false;

  StreamController<Uint8List>? _audioStreamController;
  StreamSink<Uint8List>? _audioStreamSink;

  final List<double> _recordedSamples = [];

  static const Duration _maxProcessingDelay = Duration(milliseconds: 200);
  static const int _timingHistorySize = 50;

  FlutterSoundRecorder? get recorder => _recorder;
  FlutterSoundPlayer? get player => _player;
  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;
  double get currentAmplitude => _currentAmplitude;
  Duration get recordingDuration => _recordingDuration;
  String? get currentFilePath => _currentFilePath;
  String? get lastRecordingPath => _lastRecordingPath;

  Duration get processingDelay => _processingDelay;
  Duration get averageProcessingTime => _averageProcessingTime;
  double get timePerColumn => AudioConfig.timePerColumn;

  Duration getCompensatedColumnTime(int columnIndex) {
    developer.log('AudioService: Getting compensated time for column $columnIndex');

    if (columnIndex < 0 || columnIndex >= _columnTimestamps.length || _recordingStartTime == null) {

      return Duration(milliseconds: (columnIndex * timePerColumn * 1000).round());
    }

    final actualTime = _columnTimestamps[columnIndex].difference(_recordingStartTime!);

    final compensatedTime = actualTime - _processingDelay;

    return Duration(milliseconds: math.max(0, compensatedTime.inMilliseconds));
  }

  int getColumnIndexForTime(Duration targetTime) {
    developer.log('AudioService: Finding column index for time ${targetTime.inMilliseconds}ms');

    if (_columnTimestamps.isEmpty || _recordingStartTime == null) {

      return (targetTime.inMilliseconds / 1000.0 / timePerColumn).round()
          .clamp(0, _spectrogramData.length - 1);
    }

    int bestIndex = 0;
    Duration bestDifference = Duration(days: 1);

    for (int i = 0; i < _columnTimestamps.length; i++) {
      final compensatedTime = getCompensatedColumnTime(i);
      final difference = (compensatedTime - targetTime).abs();

      if (difference < bestDifference) {
        bestDifference = difference;
        bestIndex = i;
      }
    }

    return bestIndex.clamp(0, _spectrogramData.length - 1);
  }

  static Future<SpectrogramResult> generateSpectrogram({
    String? filePath,              
    List<double>? audioSamples,    
    Function(String)? onProgress,  
  }) async {
    developer.log('AudioService: Delegating spectrogram generation to FFTService');
    return await FFTService.generateSpectrogram(
      filePath: filePath,
      audioSamples: audioSamples,
      onProgress: onProgress,
    );
  }

  Future<bool> initialize() async {
    developer.log('AudioService: Starting initialization');

    try {

      developer.log('AudioService: Requesting microphone permission');
      final status = await Permission.microphone.request();
      developer.log('AudioService: Permission status: $status');

      if (status != PermissionStatus.granted) {
        developer.log('AudioService: Microphone permission denied');
        _safeAddError('Microphone permission denied');
        return false;
      }

      developer.log('AudioService: Microphone permission granted');

      _recorder = FlutterSoundRecorder();
      _player = FlutterSoundPlayer();

      await _recorder!.openRecorder();
      await _player!.openPlayer();

      _isInitialized = true;
      developer.log('AudioService: Initialization complete');
      developer.log('AudioService: FFT Quality Settings: ${FFTService.getQualitySettings()}');
      return true;

    } catch (e) {
      developer.log('AudioService: Initialization error: $e');
      _safeAddError('Audio initialization failed: $e');
      return false;
    }
  }

  void _safeAddError(String error) {
    developer.log('AudioService: Error occurred: $error');
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
  }

  void _safeAddAudioData(AudioData data) {
    if (!_audioDataController.isClosed) {
      _audioDataController.add(data);
    }
  }

  void _safeAddRecordingState(bool state) {
    developer.log('AudioService: Recording state changed to: $state');
    if (!_recordingStateController.isClosed) {
      _recordingStateController.add(state);
    }
  }

  Future<String> getRecordingPath() async {
    developer.log('AudioService: Generating recording file path');

    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'speech_recording_$timestamp.wav';
    final fullPath = '${directory.path}/$fileName';

    developer.log('AudioService: Recording path: $fullPath');

    final dir = Directory(directory.path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      developer.log('AudioService: Created documents directory');
    }

    return fullPath;
  }

  Future<bool> startRecording() async {
    developer.log('AudioService: Starting recording');

    if (!_isInitialized || _recorder == null) {
      developer.log('AudioService: Recorder not initialized');
      _safeAddError('Recorder not initialized');
      return false;
    }

    if (_isRecording) {
      developer.log('AudioService: Already recording');
      return true;
    }

    try {

      _spectrogramData.clear();
      _columnTimestamps.clear();
      _audioBuffer.clear();
      _recordedSamples.clear();
      _resetTimingCompensation();

      FFTService.resetTracking();

      _recordingStartTime = DateTime.now();

      _currentFilePath = await getRecordingPath();
      developer.log('AudioService: Recording to file: $_currentFilePath');

      _setupAudioStream();

      await _recorder!.startRecorder(
        toStream: _audioStreamSink!,
        codec: Codec.pcm16,
        numChannels: AudioConfig.channels, 
        sampleRate: AudioConfig.sampleRate, 
      );

      _isRecording = true;
      _safeAddRecordingState(true);

      await _setupDbMonitoring();

      developer.log('AudioService: Recording started successfully');
      return true;

    } catch (e, stackTrace) {
      developer.log('AudioService: Recording start error: $e');
      developer.log('AudioService: Stack trace: $stackTrace');
      _safeAddError('Recording start failed: $e');
      _isRecording = false;
      _safeAddRecordingState(false);
      return false;
    }
  }

  void _setupAudioStream() {
    developer.log('AudioService: Setting up audio stream');

    _audioStreamController = StreamController<Uint8List>();
    _audioStreamSink = _audioStreamController!.sink;

    _audioStreamController!.stream.listen(
      (audioBytes) {
        _processRawAudioData(audioBytes);
      },
      onError: (error) {
        developer.log('AudioService: Audio stream error: $error');
        _safeAddError('Audio stream error: $error');
      },
      onDone: () {
        developer.log('AudioService: Audio stream completed');
      },
    );
  }

void _processRawAudioData(Uint8List audioBytes) {
  try {

    final samples = <double>[];
    for (int i = 0; i < audioBytes.length; i += 2) {
      if (i + 1 < audioBytes.length) {
        final sample = (audioBytes[i] | (audioBytes[i + 1] << 8)).toSigned(16);
        final normalizedSample = sample / 32768.0;
        samples.add(normalizedSample);
        _recordedSamples.add(normalizedSample);
      }
    }

    if (samples.isEmpty) return;

    _audioBuffer.addAll(samples);

    while (_audioBuffer.length >= _bufferSize) {
      final windowStartTime = DateTime.now();

      final windowSamples = _audioBuffer.sublist(0, _bufferSize);
      _audioBuffer.removeRange(0, _hopSize);

      final rms = math.sqrt(
        windowSamples.map((s) => s * s).reduce((a, b) => a + b) / windowSamples.length
      );
      _currentAmplitude = rms;

      final spectrogramColumn = FFTService.processRealtimeAudio(windowSamples);

      _processedWindows++;

      final columnGeneratedTime = DateTime.now();
      _addSpectrogramColumnWithTiming(spectrogramColumn, columnGeneratedTime);

      final windowProcessingTime = columnGeneratedTime.difference(windowStartTime);
      _updateProcessingDelay(windowProcessingTime);
    }

  } catch (e) {
    developer.log('AudioService: Raw audio processing error: $e');
  }
}

  void _addSpectrogramColumnWithTiming(List<double> frequencyData, DateTime generatedTime) {
    _spectrogramData.add(List<double>.from(frequencyData));
    _columnTimestamps.add(generatedTime);

    if (_spectrogramData.length > 10320) {
      _spectrogramData.removeAt(0);
      _columnTimestamps.removeAt(0);
    }

    if (_recordingStartTime != null) {
      _recordingDuration = DateTime.now().difference(_recordingStartTime!);
    }

    if (_spectrogramData.length % 100 == 0) {
      final maxValue = frequencyData.reduce(math.max);
      final avgValue = frequencyData.reduce((a, b) => a + b) / frequencyData.length;
      final activePixels = frequencyData.where((v) => v > 0.3).length;
      final qualitySettings = FFTService.getQualitySettings();
      final compensatedTime = getCompensatedColumnTime(_spectrogramData.length - 1);

      developer.log('AudioService: Spectrogram column ${_spectrogramData.length} - Max: ${maxValue.toStringAsFixed(3)}, Avg: ${avgValue.toStringAsFixed(3)}, Active: $activePixels/${qualitySettings['numBands']}, Time: ${compensatedTime.inMilliseconds}ms, Delay: ${_processingDelay.inMilliseconds}ms');
    }

    _safeAddAudioData(AudioData(
      amplitude: _currentAmplitude,
      duration: _recordingDuration,
      spectrogramColumn: frequencyData,
      rawDb: null,
      filePath: _currentFilePath,
    ));
  }

  void _updateProcessingDelay(Duration processingTime) {

    _recentProcessingTimes.add(processingTime);

    if (_recentProcessingTimes.length > _timingHistorySize) {
      _recentProcessingTimes.removeAt(0);
    }

    if (_recentProcessingTimes.isNotEmpty) {
      final totalMs = _recentProcessingTimes
          .map((d) => d.inMilliseconds)
          .reduce((a, b) => a + b);

      _averageProcessingTime = Duration(
        milliseconds: (totalMs / _recentProcessingTimes.length).round()
      );

      _processingDelay = Duration(
        milliseconds: (_averageProcessingTime.inMilliseconds * 1.2).round()
            .clamp(0, _maxProcessingDelay.inMilliseconds)
      );
    }

    if (_recentProcessingTimes.length % 20 == 0) {
      developer.log('AudioService: Processing delay updated - Delay: ${_processingDelay.inMilliseconds}ms, Average: ${_averageProcessingTime.inMilliseconds}ms');
    }
  }

  void _resetTimingCompensation() {
    developer.log('AudioService: Resetting timing compensation');
    _processingDelay = Duration.zero;
    _averageProcessingTime = Duration.zero;
    _recentProcessingTimes.clear();
    _columnTimestamps.clear();
  }

Future<void> _createWavFile() async {
  if (_currentFilePath == null || _recordedSamples.isEmpty) return;

  try {
    developer.log('AudioService: Creating WAV file: $_currentFilePath');

    final List<Float64List> audioChannels = [Float64List.fromList(_recordedSamples)];

    final wav = Wav(audioChannels, AudioConfig.sampleRate);

    final file = File(_currentFilePath!);
    await file.writeAsBytes(wav.write());

    developer.log('AudioService: WAV file created successfully - ${_recordedSamples.length} samples, ${AudioConfig.sampleRate}Hz');

  } catch (e) {
    developer.log('AudioService: Error creating WAV file: $e');
    rethrow;
  }
}

List<int> _intToBytes(int value, int length) {
  final buffer = BytesBuilder();
  for (int i = 0; i < length; i++) {
    buffer.addByte((value >> (i * 8)) & 0xFF);
  }
  return buffer.toBytes();
}

Future<void> _setupDbMonitoring() async {
  developer.log('AudioService: Setting up dB monitoring');

  try {
    await _recorder!.setSubscriptionDuration(const Duration(milliseconds: 50));

    _recorderSubscription = _recorder!.onProgress?.listen(
      (data) {
        if (!_isRecording) return;

        final realDbLevel = data.decibels;
        if (realDbLevel != null && realDbLevel.isFinite && !realDbLevel.isNaN) {

          final dbAmplitude = _convertDbToAmplitude(realDbLevel);
          if (dbAmplitude > _currentAmplitude) {
            _currentAmplitude = dbAmplitude;
          }

          if (_processedWindows % 100 == 0 && _processedWindows > 0) {
            developer.log('AudioService: dB Level: ${realDbLevel.toStringAsFixed(1)} dB, Amplitude: ${dbAmplitude.toStringAsFixed(3)}, Windows: $_processedWindows');
          }
        }
      },
      onError: (error) {
        developer.log('AudioService: dB monitoring error: $error');
      },
    );

  } catch (e) {
    developer.log('AudioService: Failed to setup dB monitoring: $e');
  }
}

  Future<bool> stopRecording() async {
    if (!_isRecording || _recorder == null) return false;

    try {
      developer.log('AudioService: Stopping recording');

      await _recorderSubscription?.cancel();
      _recorderSubscription = null;

      await _recorder!.stopRecorder();

      await _audioStreamController?.close();
      _audioStreamController = null;
      _audioStreamSink = null;

      _isRecording = false;
      _safeAddRecordingState(false);

      await _createWavFile();

      _lastRecordingPath = _currentFilePath;

      if (_currentFilePath != null) {
        final exportPath = _currentFilePath!.replaceFirst('.wav', '_spectrogram.csv');
        await exportSpectrogramData(exportPath);
      }

      final qualitySettings = FFTService.getQualitySettings();
      print('='*70);
      print('✅ AudioService: Recording stopped successfully');
      print('📁 AudioService: WAV file saved to: $_currentFilePath');
      print('📊 AudioService: Spectrogram: ${_spectrogramData.length} columns x ${qualitySettings['numBands']} bands');
      print('⏱️ AudioService: Timing delay: ${_processingDelay.inMilliseconds}ms');
      print('='*70);
      developer.log('AudioService: Recording stopped successfully');
      developer.log('AudioService: Spectrogram: ${_spectrogramData.length} columns x ${qualitySettings['numBands']} bands');
      developer.log('AudioService: WAV file: $_currentFilePath');
      developer.log('AudioService: Timing delay: ${_processingDelay.inMilliseconds}ms');

      return true;
    } catch (e) {
      developer.log('AudioService: Stop recording error: $e');
      _safeAddError('Stop recording failed: $e');
      return false;
    }
  }

  Future<void> exportSpectrogramData(String filePath) async {
    developer.log('AudioService: Exporting spectrogram data to: $filePath');

    try {
      final StringBuffer buffer = StringBuffer();
      final qualitySettings = FFTService.getQualitySettings();
      final numBands = qualitySettings['numBands'] as int;
      final hopSize = qualitySettings['hopSize'] as int;

      buffer.write('Time(s),CompensatedTime(s)');
      for (int i = 0; i < numBands; i++) {
        buffer.write(',FreqBand$i');
      }
      buffer.writeln();

      final double timeStep = hopSize / AudioConfig.sampleRate.toDouble();

      for (int t = 0; t < _spectrogramData.length; t++) {
        final time = (t * timeStep).toStringAsFixed(4);
        final compensatedTime = (getCompensatedColumnTime(t).inMilliseconds / 1000.0).toStringAsFixed(4);
        buffer.write('$time,$compensatedTime');

        for (int f = 0; f < _spectrogramData[t].length; f++) {
          final grayscaleValue = _spectrogramData[t][f].toStringAsFixed(6);
          buffer.write(',$grayscaleValue');
        }
        buffer.writeln();
      }

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      developer.log('AudioService: Spectrogram data exported successfully');

    } catch (e) {
      developer.log('AudioService: Error exporting spectrogram data: $e');
    }
  }

  double _convertDbToAmplitude(double dbLevel) {
    if (dbLevel <= -80.0) return 0.0;
    if (dbLevel >= -10.0) return 1.0;

    final amplitude = (dbLevel + 80.0) / 70.0;
    return amplitude.clamp(0.0, 1.0);
  }

  void resetAdaptiveMapping() {
    developer.log('AudioService: Resetting adaptive mapping');
    _resetTimingCompensation();
    _audioBuffer.clear();
    _recordedSamples.clear();

    FFTService.resetTracking();
  }

  Future<void> dispose() async {
    developer.log('AudioService: Starting disposal');

    _isRecording = false;

    await _recorderSubscription?.cancel();
    await _playerSubscription?.cancel();
    await _audioStreamController?.close();

    await _recorder?.closeRecorder();
    await _player?.closePlayer();

    await _audioDataController.close();
    await _errorController.close();
    await _recordingStateController.close();

    _recorder = null;
    _player = null;
    _isInitialized = false;

    _columnTimestamps.clear();
    _recentProcessingTimes.clear();

    developer.log('AudioService: Disposal complete');
  }
}
