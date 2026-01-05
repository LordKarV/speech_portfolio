import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:speech_app/widgets/spectrogram_widget.dart';
import 'package:speech_app/services/audio_service.dart';
import 'package:speech_app/services/audio_processing_service.dart';
import 'package:speech_app/services/recording_repository.dart';
import 'package:speech_app/screens/title_assignment_screen.dart';
import 'package:speech_app/screens/home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'dart:async';
import 'dart:io';

import '../components/app_button.dart';
import '../components/app_card.dart';
import '../components/app_label.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class WavPlaybackScreen extends StatefulWidget {
  final String wavFilePath;
  final List<List<double>>? spectrogramData;
  final Duration? recordingDuration;
  final String? recordingId;
  final List<AudioAnalysisResult>? analysisResults;

  const WavPlaybackScreen({
    super.key,
    required this.wavFilePath,
    this.spectrogramData,
    this.recordingDuration,
    this.recordingId,
    this.analysisResults,
  });

  @override
  State<WavPlaybackScreen> createState() => _WavPlaybackScreenState();
}

class _WavPlaybackScreenState extends State<WavPlaybackScreen> 
    implements WavPlaybackController {

  FlutterSoundPlayer? _player;

  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  StreamSubscription? _positionSubscription;
  bool _hasFinishedPlaying = false;
  bool _saved = false;

  List<Map<String, dynamic>> _mapEventsForSave() {

    return _analysisResults.map((e) => {
      'type': e['type'],
      'probability': e['probability'],
      't0': (e['seconds'] as int) * 1000,
      't1': (e['seconds'] as int) * 1000 + 400,
    }).toList();
  }

  Future<void> _autoSaveIfNeeded() async {
    if (_saved) return;
    try {
      final file = File(widget.wavFilePath);
      if (!await file.exists()) return;

      final repo = RecordingRepository();
      await repo.saveRecording(
        file: file,
        extension: 'wav',
        duration: _totalDuration,
        sampleRate: 44100,
        events: _mapEventsForSave(),
        title: 'Session ${_formatDate(DateTime.now().toLocal())}',
        codec: 'pcm16WAV',
        modelVersion: 'v1',
      );
      _saved = true;
      _showMessage('Saved to your account', Colors.green);
    } catch (e) {
      developer.log('❌ Save failed: $e');
      _showError('Save failed: $e');
    }
  }

  List<List<double>> _spectrogramData = [];
  bool _isLoading = true;
  String _loadingStatus = 'Initializing...';

  bool _isSeeking = false;
  bool _isDragging = false;

  bool _isValidAudioFile = false;
  String? _audioFileError;

  final List<Map<String, dynamic>> _analysisResults = [];

  @override
  void initState() {
    super.initState();
    developer.log('🎵 WavPlaybackScreen initState - File: ${widget.wavFilePath}');
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      developer.log('🎵 Starting player initialization...');
      setState(() => _loadingStatus = 'Validating audio file...');

      await _validateAudioFile();

      if (!_isValidAudioFile) {
        developer.log('❌ Audio file validation failed: $_audioFileError');
        setState(() => _isLoading = false);
        _showError(_audioFileError ?? 'Invalid audio file');
        return;
      }

      setState(() => _loadingStatus = 'Initializing audio player...');

      _player = FlutterSoundPlayer();
      await _player!.openPlayer();

      developer.log('✅ Player opened successfully. Platform: ${Platform.isIOS ? "iOS" : Platform.isAndroid ? "Android" : "Other"}');

      if (widget.spectrogramData != null && widget.recordingDuration != null) {
        developer.log('🎵 Using pre-generated spectrogram data');
        _spectrogramData = widget.spectrogramData!;
        _totalDuration = widget.recordingDuration!;

        _loadAnalysisResults();

        setState(() => _isLoading = false);
      } else {
        developer.log('🎵 Generating spectrogram from file...');
        await _loadSpectrogramUsingAudioService();
      }

      developer.log('✅ WAV Playback initialized - ${_spectrogramData.length} columns, ${_totalDuration.inSeconds}s duration');

    } catch (e, stackTrace) {
      developer.log('❌ Error initializing player: $e');
      developer.log('❌ Stack trace: $stackTrace');
      _showError('Failed to initialize audio player: $e');
      setState(() => _isLoading = false);
    }
  }

  void _loadAnalysisResults() async {
    _analysisResults.clear();

    List<AudioAnalysisResult>? results;

    if (widget.analysisResults != null) {

      developer.log('📊 Using directly passed analysis results: ${widget.analysisResults!.length} results');
      results = widget.analysisResults;
    } else if (widget.recordingId != null) {

      developer.log('📊 Loading analysis results from Firestore for recording: ${widget.recordingId}');
      results = await _loadAnalysisResultsFromFirestore(widget.recordingId!);
    } else {

      developer.log('📊 Loading analysis results from local storage for file: ${widget.wavFilePath}');
      results = AudioProcessingService.getResultsForFile(widget.wavFilePath);
    }

    if (results == null || results.isEmpty) {
      developer.log('⚠️ No analysis results available');
      return;
    }

    final totalSeconds = _totalDuration.inSeconds;

    for (final result in results) {
      if (result.success && result.probableMatches.isNotEmpty) {

        int timeInSeconds;
        if (result.t0 != null && result.t1 != null) {

          timeInSeconds = result.t0! ~/ 1000;
        } else {

          final segmentDuration = totalSeconds / results.length;
          timeInSeconds = (result.fileIndex * segmentDuration + segmentDuration / 2).round();
        }

        for (int i = 0; i < result.probableMatches.length; i++) {
          final match = result.probableMatches[i];

          int probability;
          String symptomName;

          if (result.confidence != null && result.probability != null) {

            probability = result.probability!;
            symptomName = result.type ?? match;
          } else {

            final parts = match.split(', probability ');
            symptomName = parts.isNotEmpty ? parts[0] : 'Unknown symptom';
            final probabilityStr = parts.length > 1 ? parts[1] : '0';
            probability = int.tryParse(probabilityStr) ?? 0;
          }

          if (probability == 0 && symptomName.toLowerCase() != 'none' && 
              symptomName.toLowerCase() != 'normal' && 
              symptomName.toLowerCase() != 'no_event' &&
              symptomName.toLowerCase() != 'event') {
            probability = 75;
          }

          if (symptomName.toLowerCase() == 'none' || 
              symptomName.toLowerCase() == 'normal' ||
              symptomName.toLowerCase() == 'no_event' ||
              symptomName.toLowerCase() == 'event') {
            continue;
          }

          final finalTime = timeInSeconds.clamp(0, totalSeconds - 1);

          final minutes = finalTime ~/ 60;
          final seconds = finalTime % 60;
          final timeString = '$minutes:${seconds.toString().padLeft(2, '0')}';

          String displayType;
          if (result.type != null && result.type!.isNotEmpty) {
            displayType = _formatSymptomName(result.type!);
          } else {
            displayType = _formatSymptomName(symptomName);
          }

          final color = _getColorFromEvent(displayType);

          _analysisResults.add({
            'type': displayType,
            'time': timeString,
            'seconds': finalTime,
            'color': color,
            'description': _getSymptomDescription(displayType),
            'probability': probability,
            'fileIndex': result.fileIndex,
            't0': result.t0,
            't1': result.t1,
          });
        }
      }
    }

    _analysisResults.sort((a, b) => a['seconds'].compareTo(b['seconds']));

    developer.log('🎯 Loaded ${_analysisResults.length} analysis results from iOS AudioProcessingService');

    if (mounted) {
      setState(() {});
    }
  }

  Future<List<AudioAnalysisResult>?> _loadAnalysisResultsFromFirestore(String recordingId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        developer.log('❌ User not authenticated');
        return null;
      }

      developer.log('📊 Loading events from Firestore for recording: $recordingId');

      final eventsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('recordings')
          .doc(recordingId)
          .collection('events')
          .orderBy('t0')
          .get();

      if (eventsSnapshot.docs.isEmpty) {
        developer.log('⚠️ No events found in Firestore for recording: $recordingId');
        return null;
      }

      final results = <AudioAnalysisResult>[];
      for (final doc in eventsSnapshot.docs) {
        final data = doc.data();
        final t0 = data['t0'] as int? ?? 0;
        final t1 = data['t1'] as int? ?? 0;
        final type = data['type'] as String? ?? 'Event';
        var conf = data['conf'] as double? ?? 0.0;

        if (conf > 1.0) {
          conf = conf / 100.0;
        }
        conf = conf.clamp(0.0, 1.0);

        if (type.toLowerCase() == 'none' || 
            type.toLowerCase() == 'normal' ||
            type.toLowerCase() == 'no_event' ||
            type.toLowerCase() == 'event') {
          continue;
        }

        results.add(AudioAnalysisResult.fromMap({
          'fileIndex': (t0 / 1000).round(),
          'success': true,
          'probableMatches': ['$type, probability ${(conf * 100).round()}'],
          'confidence': conf,
          'probability': (conf * 100).round(),
          'source': 'firestore',
          'modelVersion': 'v1',
          't0': t0,
          't1': t1,
          'type': type,
        }));
      }

      developer.log('✅ Loaded ${results.length} analysis results from Firestore');
      return results;

    } catch (e) {
      developer.log('❌ Error loading analysis results from Firestore: $e');
      return null;
    }
  }

  Color _getColorFromEvent(String eventType) {
    switch (eventType.toLowerCase()) {
      case 'repetitions': return Colors.blue;
      case 'blocks': return Colors.red;
      case 'prolongations': return Colors.orange;
      default: return Colors.grey;
    }
  }

  String _formatSymptomName(String symptomName) {

    final lowerName = symptomName.toLowerCase();

    if (lowerName.contains('blocks')) {
      return 'Blocks';
    } else if (lowerName.contains('prolongations')) {
      return 'Prolongations';
    } else if (lowerName.contains('repetitions')) {
      return 'Repetitions';
    } else if (lowerName.contains('interjection')) {
      return 'Interjections';
    }

    if (lowerName.contains('stutter symptom')) {
      final number = symptomName.replaceAll(RegExp(r'[^0-9]'), '');
      final types = ['Block', 'Repetition', 'Prolongation', 'Interjection'];
      final typeIndex = (int.tryParse(number) ?? 1) % types.length;
      return '${types[typeIndex]} $number';
    }

    if (symptomName.isNotEmpty) {
      return '${symptomName[0].toUpperCase()}${symptomName.substring(1)}';
    }

    return 'Speech Event';
  }

  String _getSymptomDescription(String symptomName) {
    if (symptomName.toLowerCase().contains('block')) return 'Speech blockage detected';
    if (symptomName.toLowerCase().contains('repetition')) return 'Sound repetition detected';
    if (symptomName.toLowerCase().contains('prolongation')) return 'Sound prolongation detected';
    if (symptomName.toLowerCase().contains('interjection')) return 'Filler word detected';
    return 'Speech disfluency detected';
  }

  @override
  Future<void> play() async {
    if (_player == null || _isLoading) {
      developer.log('⚠️ Cannot play - player not ready. Player: ${_player == null ? "null" : "initialized"}, Loading: $_isLoading');
      return;
    }

    try {
      developer.log('🎵 Play attempt initiated. Current state - Playing: $_isPlaying, Finished: $_hasFinishedPlaying, Position: ${_currentPosition.inSeconds}s, Total Duration: ${_totalDuration.inSeconds}s');

      if (_hasFinishedPlaying && _currentPosition.inMilliseconds >= _totalDuration.inMilliseconds - 1000) {
        developer.log('🔄 Resetting to beginning - was at end and finished');
        _currentPosition = Duration.zero;
        _hasFinishedPlaying = false;
        setState(() {
          developer.log('🔄 UI updated with reset position: ${_currentPosition.inSeconds}s');
        });
      } else if (_hasFinishedPlaying) {
        developer.log('🔄 Clearing finished flag but keeping current position: ${_currentPosition.inSeconds}s');
        _hasFinishedPlaying = false;
      }

      developer.log('🎵 Starting playback from position: ${_currentPosition.inSeconds}s');

      final file = File(widget.wavFilePath);
      if (!await file.exists()) {
        developer.log('❌ File no longer exists at: ${widget.wavFilePath}');
        throw Exception('File no longer exists');
      }

      final fileSize = await file.length();
      developer.log('📁 Playing file: ${widget.wavFilePath}, Size: $fileSize bytes');

      try {
        developer.log('🛑 Stopping any existing playback...');
        await _player!.stopPlayer();
        await Future.delayed(const Duration(milliseconds: 150));
        developer.log('🛑 Existing playback stopped successfully');
      } catch (e) {
        developer.log('⚠️ No existing playback to stop or error stopping: $e');
      }

      setState(() {
        _isPlaying = true;
        developer.log('▶️ UI updated to playing state, _isPlaying: $_isPlaying');
      });

      developer.log('📊 Starting position tracking subscription...');
      await _player!.setSubscriptionDuration(const Duration(milliseconds: 50));
      developer.log('📊 Subscription duration set to 50ms for progress updates');
      _startPositionTracking();

      final playbackStartTime = DateTime.now().millisecondsSinceEpoch;
      developer.log('⏱️ Playback start time recorded: $playbackStartTime ms');

      developer.log('🎵 Initiating startPlayer with codec: pcm16WAV, URI: ${widget.wavFilePath}');
      await _player!.startPlayer(
        fromURI: widget.wavFilePath,
        codec: Codec.pcm16WAV,
        whenFinished: () {
          final playbackEndTime = DateTime.now().millisecondsSinceEpoch;
          final playbackDuration = playbackEndTime - playbackStartTime;
          developer.log('🎵 Playback finished naturally after $playbackDuration ms');

          if (playbackDuration < 200) {
            developer.log('⚠️ Playback finished too quickly ($playbackDuration ms). Possible file format or corruption issue.');
            _showError('Playback ended immediately. File might be corrupted or incompatible.');
          }

          if (mounted) {
            setState(() {
              _isPlaying = false;
              _hasFinishedPlaying = true;
              _currentPosition = _totalDuration;
              developer.log('🛑 UI updated to stopped state. Position set to end: ${_currentPosition.inSeconds}s, _isPlaying: $_isPlaying, _hasFinishedPlaying: $_hasFinishedPlaying');
            });
          }
        },
      );
      developer.log('✅ startPlayer call completed successfully');

      if (_currentPosition.inMilliseconds > 0) {
        developer.log('🎵 Seeking to current position: ${_currentPosition.inSeconds}s after playback start');
        await _player!.seekToPlayer(_currentPosition);
        developer.log('🎵 Seeked to: ${_currentPosition.inSeconds}s after start');
      } else {
        developer.log('🎵 No seek needed, starting from beginning');
      }

      developer.log('✅ Playback started successfully from ${_currentPosition.inSeconds}s');

    } catch (e, stackTrace) {
      developer.log('❌ Error starting playback: $e');
      developer.log('❌ Stack trace: $stackTrace');
      setState(() {
        _isPlaying = false;
        developer.log('❌ UI updated to stopped state due to error, _isPlaying: $_isPlaying');
      });
      _showError('Playback failed: $e. Check audio permissions and file validity.');
    }
  }

  void _startPositionTracking() {
    _positionSubscription?.cancel();
    developer.log('📊 Position tracking subscription cancelled if existed, setting up new subscription');
    _positionSubscription = _player!.onProgress?.listen((event) {
      final newPosition = event.position;

      if (!_isDragging && !_isSeeking && mounted && _isPlaying && 
          newPosition.inMilliseconds <= _totalDuration.inMilliseconds + 1000) {

        setState(() {
          _currentPosition = newPosition;

          if (_currentPosition.inMilliseconds >= _totalDuration.inMilliseconds - 200) {
            _isPlaying = false;
            _hasFinishedPlaying = true;
            _currentPosition = _totalDuration;
          }
        });
      }
    });
    developer.log('📊 Position tracking subscription set up complete');
  }

  @override
  Future<void> pause() async {
    if (_player == null) {
      developer.log('⚠️ Cannot pause - player not initialized');
      return;
    }

    try {
      developer.log('🎵 Pausing at ${_currentPosition.inSeconds}s');
      await _player!.pausePlayer();
      setState(() {
        _isPlaying = false;
        developer.log('⏸️ UI updated to paused state, _isPlaying: $_isPlaying');
      });
      _positionSubscription?.cancel();
      developer.log('⏸️ Playback paused and position tracking cancelled');
    } catch (e) {
      developer.log('❌ Error pausing: $e');
    }
  }

  Future<void> _validateAudioFile() async {
    try {
      developer.log('🔍 Validating file: ${widget.wavFilePath}');

      final file = File(widget.wavFilePath);

      if (!await file.exists()) {
        _audioFileError = 'File does not exist: ${widget.wavFilePath}';
        developer.log('❌ File does not exist at specified path');
        return;
      }

      final fileSize = await file.length();
      developer.log('📁 File size: $fileSize bytes');
      if (fileSize < 44) {
        _audioFileError = 'File too small to be a valid WAV file ($fileSize bytes)';
        developer.log('❌ File too small for valid WAV');
        return;
      }

      try {
        final stat = await file.stat();
        developer.log('📁 File stats - Created: ${stat.changed}, Modified: ${stat.modified}, Accessed: ${stat.accessed}');
      } catch (e) {
        developer.log('⚠️ Could not retrieve file stats: $e');
      }

      _isValidAudioFile = true;
      developer.log('✅ Audio file validation passed');

    } catch (e) {
      _audioFileError = 'File validation error: $e';
      developer.log('❌ $_audioFileError');
    }
  }

  Future<void> _loadSpectrogramUsingAudioService() async {
    try {
      developer.log('🎵 Loading spectrogram using AudioService...');

      final result = await AudioService.generateSpectrogram(
        filePath: widget.wavFilePath,
        onProgress: (status) {
          if (mounted) {
            setState(() => _loadingStatus = status);
          }
        },
      );

      _spectrogramData = result.data;
      _totalDuration = result.duration;

      _loadAnalysisResults();

      setState(() => _isLoading = false);
      developer.log('✅ Spectrogram loaded - ${_spectrogramData.length} columns, ${_totalDuration.inSeconds}s');

    } catch (e) {
      setState(() => _isLoading = false);
      developer.log('❌ Error loading spectrogram: $e');
      _showError('Failed to load audio file: $e');
    }
  }

  @override
  bool get isPlaying => _isPlaying;

  @override
  Duration get currentPosition => _currentPosition;

  @override
  Duration get totalDuration => _totalDuration;

  @override
  int get currentColumnIndex {
    if (_totalDuration.inMilliseconds == 0 || _spectrogramData.isEmpty) return 0;
    final progress = _currentPosition.inMilliseconds / _totalDuration.inMilliseconds;
    return (progress * _spectrogramData.length).round().clamp(0, _spectrogramData.length - 1);
  }

  @override
  Future<void> seekToColumn(int columnIndex) async {
    if (_spectrogramData.isEmpty) return;

    final progress = columnIndex / _spectrogramData.length;
    final targetPosition = Duration(
      milliseconds: (_totalDuration.inMilliseconds * progress).round()
    );

    await seekToPosition(targetPosition);
  }

  @override
  Future<void> seekToPosition(Duration position) async {
    if (_player == null) {
      developer.log('⚠️ Cannot seek - player not initialized');
      return;
    }

    try {
      final seekStartTime = DateTime.now().millisecondsSinceEpoch;
      developer.log('🎵 Seeking to: ${position.inSeconds}s at $seekStartTime ms, Current State - Playing: $_isPlaying, Seeking: $_isSeeking, Dragging: $_isDragging');
      _isSeeking = true;
      _hasFinishedPlaying = false;

      setState(() {
        _currentPosition = position;
        developer.log('🎵 UI updated with seek position: ${_currentPosition.inSeconds}s');
      });

      if (_isPlaying) {
        await _player!.seekToPlayer(position);
        final seekEndTime = DateTime.now().millisecondsSinceEpoch;
        final seekDuration = seekEndTime - seekStartTime;
        developer.log('🎵 Seek operation completed to: ${position.inSeconds}s, Took: $seekDuration ms');
      } else {
        developer.log('🎵 Seek operation not performed on player as playback is paused/stopped');
      }

      _isSeeking = false;
      developer.log('🎵 Seeking state reset, _isSeeking: $_isSeeking');
    } catch (e) {
      _isSeeking = false;
      developer.log('❌ Seek error: $e, Resetting _isSeeking: $_isSeeking');
    }
  }

  Future<void> _jumpToStutter(Map<String, dynamic> result) async {
    final targetSeconds = result['seconds'] as int;
    final targetPosition = Duration(seconds: targetSeconds);

    developer.log('🎯 Jumping to analysis result at ${targetSeconds}s: ${result['type']}');

    await seekToPosition(targetPosition);

    if (!_isPlaying) {
      await Future.delayed(const Duration(milliseconds: 300));
      await play();
    }
  }

void _handleSeekUpdate(double progress) {
  if (_totalDuration.inMilliseconds > 0) {
    final targetPosition = Duration(
      milliseconds: (_totalDuration.inMilliseconds * progress).round()
    );

    setState(() {
      _currentPosition = targetPosition;
    });
  }
}

void _handleSeekComplete(double progress) {
  if (_totalDuration.inMilliseconds > 0) {
    final targetPosition = Duration(
      milliseconds: (_totalDuration.inMilliseconds * progress).round()
    );

    developer.log('🎯 Final audio seek to: ${targetPosition.inSeconds}s');

    setState(() {
      _hasFinishedPlaying = false;
      _currentPosition = targetPosition;
    });

    seekToPosition(targetPosition);
  }
}

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Speech Analysis'),
        backgroundColor: AppColors.backgroundPrimary,
        actions: [
          AppButton.secondary(
            onPressed: _showDeleteConfirmation,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline, size: 18),
                SizedBox(width: 4),
                Text('Delete'),
              ],
            ),
          ),
          if (widget.recordingId == null) ...[
            SizedBox(width: AppDimensions.marginSmall),
            AppButton.secondary(
              onPressed: _navigateToSaveScreen,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.save_rounded, size: 18),
                  SizedBox(width: 4),
                  Text('Save'),
                ],
              ),
            ),
          ],
          SizedBox(width: AppDimensions.marginMedium),
        ],
      ),
      backgroundColor: AppColors.backgroundPrimary,
      body: _isLoading ? _buildLoadingState() : _buildPlaybackInterface(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: AppCard.elevated(
        padding: const EdgeInsets.all(AppDimensions.paddingXLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: AppColors.accent,
              strokeWidth: 3,
            ),
            SizedBox(height: AppDimensions.marginLarge),
            AppLabel.primary(
              _loadingStatus,
              size: LabelSize.large,
              textAlign: TextAlign.center,
              fontWeight: FontWeight.w500,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaybackInterface() {
    return Column(
      children: [

        Container(
          height: 280,
          margin: const EdgeInsets.symmetric(
            horizontal: AppDimensions.marginLarge,
            vertical: AppDimensions.marginMedium,
          ),
          child: SpectrogramWidget(
            spectrogramData: _spectrogramData,
            isRecording: false,
            recordingDuration: _totalDuration,
            isWavPlayback: true,
            wavController: this,
            onSeekUpdate: _handleSeekUpdate,
            onSeekComplete: _handleSeekComplete,
            onSeekStart: () {
              developer.log('🖱️ SpectrogramWidget seek started');
              setState(() {
                _isDragging = true;
                _isSeeking = true;
              });
            },
            onSeekEnd: () {
              developer.log('🖱️ SpectrogramWidget seek ended');
              setState(() {
                _isDragging = false;
                _isSeeking = false;
              });
            },
          ),
        ),

        _buildTinyControls(),

        Expanded(
          child: _buildActionableStutterList(),
        ),
      ],
    );
  }

  Widget _buildTinyControls() {
    return AppCard.basic(
      height: 100,
      margin: const EdgeInsets.symmetric(
        horizontal: AppDimensions.marginLarge,
        vertical: AppDimensions.marginMedium,
      ),
      padding: const EdgeInsets.all(AppDimensions.paddingLarge),
      child: Row(
        children: [
          AppButton.primary(
            onPressed: _isPlaying ? pause : play,
            size: ButtonSize.large,
            child: Icon(
              _hasFinishedPlaying 
                  ? Icons.replay 
                  : (_isPlaying ? Icons.pause : Icons.play_arrow), 
              size: AppDimensions.iconLarge,
              color: Colors.white,
            ),
          ),

          SizedBox(width: AppDimensions.marginLarge),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AppLabel.primary(
                      _formatDuration(_currentPosition),
                      size: LabelSize.medium,
                      fontWeight: FontWeight.w600,
                    ),
                    AppLabel.primary(
                      _formatDuration(_totalDuration),
                      size: LabelSize.medium,
                      fontWeight: FontWeight.w600,
                    ),
                  ],
                ),

                SizedBox(height: AppDimensions.marginMedium),

                SizedBox(
                  height: 24,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.accent,
                      inactiveTrackColor: AppColors.border,
                      thumbColor: AppColors.accent,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _totalDuration.inMilliseconds > 0 
                          ? (_currentPosition.inMilliseconds / _totalDuration.inMilliseconds).clamp(0.0, 1.0)
                          : 0.0,
                      onChangeStart: (value) {
                        developer.log('🖱️ Slider drag started, setting _isDragging: true');
                        setState(() {
                          _isDragging = true;
                          _isSeeking = true;
                        });
                      },
                      onChanged: (value) {
                        final targetPosition = Duration(
                          milliseconds: (_totalDuration.inMilliseconds * value).round()
                        );
                        setState(() => _currentPosition = targetPosition);
                      },
                      onChangeEnd: (value) {
                        final targetPosition = Duration(
                          milliseconds: (_totalDuration.inMilliseconds * value).round()
                        );
                        developer.log('🖱️ Slider drag ended, seeking to ${targetPosition.inSeconds}s');

                        setState(() {
                          _hasFinishedPlaying = false;
                          _currentPosition = targetPosition;
                          _isDragging = false;
                          _isSeeking = false;
                        });

                        seekToPosition(targetPosition);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionableStutterList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.marginLarge,
            AppDimensions.marginLarge,
            AppDimensions.marginLarge,
            AppDimensions.marginMedium,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppLabel.primary(
                'Speech Analysis Results',
                fontWeight: FontWeight.bold,
                size: LabelSize.large,
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.paddingMedium,
                  vertical: AppDimensions.paddingSmall,
                ),
                decoration: BoxDecoration(
                  color: AppColors.backgroundTertiary,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                ),
                child: AppLabel.primary(
                  '${_analysisResults.length}',
                  fontWeight: FontWeight.w600,
                  size: LabelSize.medium,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _analysisResults.isEmpty 
            ? _buildNoResultsState()
            : ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.marginLarge,
                  vertical: AppDimensions.marginSmall,
                ),
                itemCount: _analysisResults.length,
                separatorBuilder: (context, index) => const SizedBox(
                  height: AppDimensions.marginMedium,
                ),
                itemBuilder: (context, index) {
                  final result = _analysisResults[index];
                  return AppCard.basic(
                    onTap: () => _jumpToStutter(result),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: AppDimensions.paddingMedium,
                        horizontal: AppDimensions.paddingLarge,
                      ),
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: (result['color'] as Color).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                        ),
                        child: Icon(
                          _getIconForType(result['type']),
                          color: result['color'],
                          size: 24,
                        ),
                      ),
                      title: AppLabel.primary(
                        result['type'],
                        fontWeight: FontWeight.w600,
                        size: LabelSize.medium,
                      ),
                      trailing: AppLabel.secondary(
                        result['time'],
                        fontWeight: FontWeight.w600,
                        size: LabelSize.medium,
                      ),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  IconData _getIconForType(String type) {
    if (type.toLowerCase().contains('block')) return Icons.block;
    if (type.toLowerCase().contains('repetition')) return Icons.repeat;
    if (type.toLowerCase().contains('prolongation')) return Icons.timeline;
    if (type.toLowerCase().contains('interjection')) return Icons.chat_bubble_outline;
    return Icons.analytics;
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 48,
            color: AppColors.textSecondary,
          ),
          SizedBox(height: AppDimensions.marginMedium),
          AppLabel.secondary(
            'No speech events detected',
            size: LabelSize.medium,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: AppDimensions.marginSmall),
          AppLabel.tertiary(
            'The analysis didn\'t find any significant\nspeech disfluencies in this recording.',
            size: LabelSize.small,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppLabel.primary(message, color: Colors.white),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showMessage(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppLabel.primary(message, color: Colors.white),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _navigateToSaveScreen() {
    developer.log('💾 WavPlaybackScreen: Navigating to save screen');

    Map<String, dynamic>? classifications;
    if (_analysisResults.isNotEmpty) {
      classifications = {
        'totalSegments': _analysisResults.length,
        'successfulSegments': _analysisResults.where((r) => r['success'] == true).length,
        'totalMatches': _analysisResults.fold(0, (sum, r) => sum + (r['matches'] as int? ?? 0)),
        'results': _analysisResults.map((r) {
          final prob = r['probability'] as int?;
          var conf = 0.0;
          if (prob != null) {
            conf = prob / 100.0;
            conf = conf.clamp(0.0, 1.0);
          }
          return {
            'success': r['success'] ?? false,
            'matches': r['matches'] ?? 0,
            'confidence': conf,
            'probableMatches': [r['type'] ?? 'Speech'],
            't0': r['t0'] ?? 0,
            't1': r['t1'] ?? 5000,
            'source': r['source'] ?? 'cnn_model',
            'modelVersion': r['modelVersion'] ?? 'v1',
          };
        }).toList(),
      };
    }

    Map<String, dynamic>? spectrogramData;
    if (_spectrogramData.isNotEmpty) {
      spectrogramData = {
        'data': _spectrogramData,
        'sampleRate': 16000,
        'windowSize': 1024,
      };
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TitleAssignmentScreen(
          localFilePath: widget.wavFilePath,
          duration: _totalDuration,
          classifications: classifications,
          spectrogramData: spectrogramData,
        ),
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.backgroundPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
          ),
          title: AppLabel.primary(
            'Delete Recording',
            fontWeight: FontWeight.bold,
            size: LabelSize.large,
          ),
          content: AppLabel.secondary(
            'Are you sure you want to delete this recording? This action cannot be undone.',
            size: LabelSize.medium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: AppLabel.primary(
                'Cancel',
                color: AppColors.textSecondary,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteRecording();
              },
              child: AppLabel.primary(
                'Delete',
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteRecording() async {
    try {
      developer.log('🗑️ Deleting recording file: ${widget.wavFilePath}');

      if (widget.recordingId != null) {
        developer.log('🗑️ Deleting recording from Firestore: ${widget.recordingId}');

        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {

          final recordingRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('recordings')
              .doc(widget.recordingId);

          final eventsSnapshot = await recordingRef.collection('events').get();
          final batch = FirebaseFirestore.instance.batch();

          for (final doc in eventsSnapshot.docs) {
            batch.delete(doc.reference);
          }

          batch.delete(recordingRef);

          await batch.commit();
          developer.log('✅ Recording deleted from Firestore successfully');
        }
      }

      final file = File(widget.wavFilePath);
      if (await file.exists()) {
        await file.delete();
        developer.log('✅ Recording file deleted successfully');
      } else {
        developer.log('⚠️ Recording file does not exist locally');
      }

      _analysisResults.clear();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );

        Future.delayed(const Duration(milliseconds: 100), () {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: AppLabel.primary('Recording deleted successfully', color: Colors.white),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        });
      }
    } catch (e) {
      developer.log('❌ Error deleting recording: $e');
      _showError('Failed to delete recording: $e');
    }
  }

  void _showResultDetails(Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.backgroundPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
          ),
          title: AppLabel.primary(
            'Analysis Result Details',
            fontWeight: FontWeight.bold,
            size: LabelSize.large,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Type', result['type']),
              _buildDetailRow('Time', result['time']),
              _buildDetailRow('Description', result['description']),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: AppLabel.primary('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.marginSmall),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: AppLabel.secondary(
              '$label:',
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: AppLabel.primary(value),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  void dispose() {
    developer.log('🎵 Disposing...');
    _positionSubscription?.cancel();
    _player?.closePlayer();
    super.dispose();
  }
}
