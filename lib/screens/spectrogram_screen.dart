import 'package:flutter/material.dart';
import 'package:speech_app/screens/title_assignment_screen.dart';
import 'package:speech_app/screens/wav_playback_screen.dart';
import 'package:speech_app/widgets/spectrogram_widget.dart';
import 'package:speech_app/theme/app_dimensions.dart';
import 'dart:async';
import 'dart:developer' as developer;
import '../components/app_button.dart';
import '../components/app_card.dart';
import '../components/app_label.dart';
import '../services/audio_processing_service.dart';
import '../services/audio_service.dart';
import '../services/loading_service.dart';
import '../theme/app_colors.dart';

class SpectrogramScreen extends StatefulWidget {
  const SpectrogramScreen({super.key});

  @override
  State<SpectrogramScreen> createState() => _SpectrogramScreenState();
}

class _SpectrogramScreenState extends State<SpectrogramScreen> with TickerProviderStateMixin {
  final AudioService _audioService = AudioService();

  StreamSubscription<AudioData>? _audioDataSubscription;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _recordingStateSubscription;

  bool _isRecording = false;
  bool _isInitialized = false;
  String _currentError = '';

  double _currentAmplitude = 0.0;
  Duration _recordingDuration = Duration.zero;
  List<List<double>> _spectrogramData = [];

  late AnimationController _pulseController;

  Timer? _uiUpdateTimer;
  int _liveUpdateCount = 0;

  bool _isProcessing = false;
  String _processingStatus = '';
  double _processingProgress = 0.0;
  bool _canCancelProcessing = true;
  List<AudioAnalysisResult> _analysisResults = [];

  @override
  void initState() {
    super.initState();
    developer.log('🎛️ SpectrogramScreen: Initializing...');
    _initializeAnimation();
    _startUIUpdateTimer();
    _initializeAudioService();
  }

  void _initializeAnimation() {
    developer.log('🎨 SpectrogramScreen: Setting up pulse animation');
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
  }

  Future<void> _initializeAudioService() async {
    try {
      developer.log('🎛️ SpectrogramScreen: Initializing audio service...');

      final success = await _audioService.initialize();

      if (success) {
        setState(() {
          _isInitialized = true;
        });

        _setupStreamListeners();
        developer.log('✅ SpectrogramScreen: Audio service initialized successfully');
        await _startRecording();
      } else {
        setState(() {
          _currentError = 'Failed to initialize audio service';
        });
        developer.log('❌ SpectrogramScreen: Audio service initialization failed');
      }
    } catch (e) {
      setState(() {
        _currentError = 'Audio service error: $e';
      });
      developer.log('❌ SpectrogramScreen: Audio service initialization error: $e');
    }
  }

  void _setupStreamListeners() {
    developer.log('🎛️ SpectrogramScreen: Setting up stream listeners...');
    _cancelStreamSubscriptions();
    int streamUpdateCounter = 0;
    const int addEveryNUpdates = 1;

    _audioDataSubscription = _audioService.audioDataStream.listen(
      (audioData) {
        _liveUpdateCount++;
        streamUpdateCounter++;

        if (mounted) {
          setState(() {
            _currentAmplitude = audioData.amplitude;
            _recordingDuration = audioData.duration;

            if (audioData.spectrogramColumn != null && streamUpdateCounter >= addEveryNUpdates) {
              _spectrogramData.add(List<double>.from(audioData.spectrogramColumn!));
              streamUpdateCounter = 0;
              developer.log('📊 SpectrogramScreen: Added spectrogram column, total: ${_spectrogramData.length}');
            }
          });

          if (_isRecording && audioData.amplitude > 0.0) {
            if (!_pulseController.isAnimating) {
              _pulseController.repeat(reverse: true);
            }
          } else if (_pulseController.isAnimating) {
            _pulseController.stop();
            _pulseController.reset();
          }
        }
      },
      onError: (error) {
        developer.log('❌ SpectrogramScreen: Audio data stream error: $error');
        if (mounted) {
          setState(() {
            _currentError = 'Audio stream error: $error';
          });
        }
      },
    );

    _recordingStateSubscription = _audioService.recordingStateStream.listen(
      (isRecording) {
        developer.log('🎛️ SpectrogramScreen: Recording state changed: $isRecording');
        if (mounted) {
          setState(() {
            _isRecording = isRecording;
          });

          if (!isRecording) {
            _pulseController.stop();
            _pulseController.reset();
          }
        }
      },
    );

    _errorSubscription = _audioService.errorStream.listen(
      (error) {
        developer.log('❌ SpectrogramScreen: Received error: $error');
        if (mounted) {
          setState(() {
            _currentError = error;
          });

          _showErrorSnackBar('Audio Error: $error');
        }
      },
    );

    developer.log('✅ SpectrogramScreen: Stream listeners set up successfully');
  }

  void _startUIUpdateTimer() {
    developer.log('⏰ SpectrogramScreen: Starting UI update timer');
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isRecording && mounted) {
        final currentAmplitude = _audioService.currentAmplitude;
        final currentDuration = _audioService.recordingDuration;
        final serviceSpectrogramData = _audioService.spectrogramData;

        if (serviceSpectrogramData.length > _spectrogramData.length) {
          developer.log('🔄 SpectrogramScreen: Syncing spectrogram data - Service: ${serviceSpectrogramData.length}, UI: ${_spectrogramData.length}');

          setState(() {
            _spectrogramData = List<List<double>>.from(
              serviceSpectrogramData.map((col) => List<double>.from(col))
            );
            _currentAmplitude = currentAmplitude;
            _recordingDuration = currentDuration;
          });
        }
      }
    });
  }

  void _cancelStreamSubscriptions() {
    developer.log('🗑️ SpectrogramScreen: Canceling stream subscriptions');
    _audioDataSubscription?.cancel();
    _errorSubscription?.cancel();
    _recordingStateSubscription?.cancel();
    _audioDataSubscription = null;
    _errorSubscription = null;
    _recordingStateSubscription = null;
  }

  Future<void> _startRecording() async {
    if (!_isInitialized) {
      developer.log('⚠️ SpectrogramScreen: Cannot start recording - service not initialized');
      _showWarningSnackBar('Audio service not initialized');
      return;
    }

    developer.log('🎛️ SpectrogramScreen: Starting recording...');
    _liveUpdateCount = 0;

    setState(() {
      _spectrogramData.clear();
      _currentAmplitude = 0.0;
      _recordingDuration = Duration.zero;
    });

    final success = await _audioService.startRecording();

    if (success) {
      developer.log('✅ SpectrogramScreen: Recording started successfully');

      if (_audioDataSubscription == null) {
        developer.log('⚠️ SpectrogramScreen: Stream subscription was null, re-setting up...');
        _setupStreamListeners();
      }
    } else {
      developer.log('❌ SpectrogramScreen: Failed to start recording');
      _showErrorSnackBar('Failed to start recording');
    }
  }

  Future<void> _stopRecording() async {
    print('='*70);
    print('🎛️ SpectrogramScreen: STOPPING RECORDING');
    print('='*70);

    try {
      await _audioService.stopRecording();

      print('✅ SpectrogramScreen: Recording stopped successfully. Total live updates received: $_liveUpdateCount');
      print('📁 Recording path: ${_audioService.lastRecordingPath}');

      print('🚀 SpectrogramScreen: About to call _startProcessingWorkflow()...');
      await _startProcessingWorkflow();
      print('✅ SpectrogramScreen: _startProcessingWorkflow() completed');
    } catch (e, stackTrace) {
      print('❌ SpectrogramScreen: Error in _stopRecording: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> _startProcessingWorkflow() async {
    print('='*70);
    print('🔄 SpectrogramScreen: _startProcessingWorkflow() CALLED');
    print('='*70);

    final recordingPath = _audioService.lastRecordingPath;
    print('📁 Recording path: $recordingPath');

    if (recordingPath == null || recordingPath.isEmpty) {
      print('❌ SpectrogramScreen: No recording path available');
      print('   This means _audioService.lastRecordingPath is null/empty');
      print('   The recording might not have been saved properly');
      _showErrorSnackBar('Recording file not found');
      return;
    }

    print('✅ Recording path found - proceeding with analysis');

    setState(() {
      _isProcessing = true;
      _processingStatus = 'Preparing audio for analysis...';
      _processingProgress = 0.0;
      _canCancelProcessing = true;
    });

    try {
      print('🔄 SpectrogramScreen: Starting audio processing workflow...');

      LoadingService.show(context);

      setState(() {
        _processingStatus = 'Running CNN analysis on audio segments...';
        _processingProgress = 0.3;
      });

      print('🎯 AudioProcessingService: Starting Python CNN processing for $recordingPath');

      final List<AudioAnalysisResult> results = await AudioProcessingService.processAudioFile(
        filePath: recordingPath
      );

      print('✅ AudioProcessingService: Got ${results.length} results');

      _analysisResults = results;

      setState(() {
        _processingStatus = 'Processing complete! Got ${results.length} results';
        _processingProgress = 1.0;
      });

      LoadingService.hide();

      developer.log('✅ SpectrogramScreen: Processing workflow completed successfully');
      developer.log('📊 SpectrogramScreen: Received ${results.length} analysis results from CNN');

      for (int i = 0; i < results.length; i++) {
        final result = results[i];
        developer.log('📋 SpectrogramScreen: Segment $i: ${result.success ? 'Success' : 'Failed'} - ${result.probableMatches.length} matches');
      }

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        _navigateToPlayback();
      }

    } catch (e) {
      developer.log('❌ SpectrogramScreen: Processing failed: $e');

      LoadingService.hide();

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingStatus = 'Processing failed: $e';
        });

        _showErrorSnackBar('Processing failed: $e');

        _navigateToPlayback();
      }
    }
  }

  void _cancelProcessing() {
    developer.log('🚫 SpectrogramScreen: Canceling processing');
    setState(() {
      _isProcessing = false;
      _canCancelProcessing = false;
    });

    _navigateToPlayback();
  }

  void _navigateToPlayback() {
    final recordingPath = _audioService.lastRecordingPath;

    if (recordingPath != null && recordingPath.isNotEmpty) {
      developer.log('🎵 SpectrogramScreen: Navigating to WAV playback with file: $recordingPath');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => WavPlaybackScreen(
            wavFilePath: recordingPath,
            spectrogramData: _spectrogramData,
            recordingDuration: _recordingDuration,
            analysisResults: _analysisResults,
          ),
        ),
      );
    } else {
      developer.log('❌ SpectrogramScreen: No recording path available for playback');
      _showErrorSnackBar('Recording file not found');
    }
  }

  void _cancelAndGoBack() {
    developer.log('🔙 SpectrogramScreen: Canceling and going back');
    _stopRecording();
    Navigator.of(context).pop();
  }

  String _getCurrentDate() {
    final now = DateTime.now();
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  void _showErrorSnackBar(String message) {
    developer.log('🚨 SpectrogramScreen: Showing error snackbar: $message');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: AppLabel.primary(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showWarningSnackBar(String message) {
    developer.log('⚠️ SpectrogramScreen: Showing warning snackbar: $message');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: AppLabel.primary(message),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_isInitialized) {
      return _buildLoadingState();
    }

    return Column(
      children: [

        _buildTopHeader(),

        _buildSpectrogramArea(),

        const SizedBox(height: AppDimensions.marginLarge),

        _buildControlBar(),

        if (_currentError.isNotEmpty) ...[
          const SizedBox(height: AppDimensions.marginMedium),
          _buildErrorCard(),
        ],

        const Spacer(),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: AppColors.accent,
            strokeWidth: 3,
          ),
          SizedBox(height: AppDimensions.marginLarge),
          AppLabel.secondary(
            'Initializing audio system...',
            size: LabelSize.large,
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeader() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingLarge),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AppLabel.primary(
              _getCurrentDate(),
              size: LabelSize.large,
              fontWeight: FontWeight.bold,
            ),
            AppButton.secondary(
              onPressed: _cancelAndGoBack,
              size: ButtonSize.small,
              child: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpectrogramArea() {
    return AppCard.basic(
      margin: const EdgeInsets.symmetric(horizontal: AppDimensions.marginLarge),
      padding: const EdgeInsets.all(AppDimensions.paddingLarge),
      child: SizedBox(
        height: 300,
        width: double.infinity,
        child: _spectrogramData.isEmpty 
          ? _buildEmptySpectrogramState()
          : SpectrogramWidget(
              spectrogramData: _spectrogramData,
              isRecording: _isRecording,
              recordingDuration: _recordingDuration,
            ),
      ),
    );
  }

  Widget _buildEmptySpectrogramState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.backgroundTertiary,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(
              Icons.graphic_eq_rounded,
              size: 48,
              color: AppColors.textTertiary,
            ),
          ),
          SizedBox(height: AppDimensions.marginLarge),
          AppLabel.primary(
            'Audio Spectrogram',
            size: LabelSize.large,
            fontWeight: FontWeight.bold,
          ),
          SizedBox(height: AppDimensions.marginSmall),
          AppLabel.secondary(
            'Start recording to see live audio visualization',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return AppCard.basic(
      margin: const EdgeInsets.symmetric(horizontal: AppDimensions.marginLarge),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingXLarge,
        vertical: AppDimensions.paddingLarge,
      ),
      child: Row(
        children: [

          AppButton.secondary(
            onPressed: _cancelAndGoBack,
            child: Text('Cancel'),
          ),

          const Spacer(),

          AppButton.primary(
            onPressed: () {
              print('🔴 BUTTON PRESSED: _isRecording = $_isRecording');
              if (_isRecording) {
                print('🛑 CALLING _stopRecording()');
                _stopRecording();
              } else {
                print('▶️ CALLING _startRecording()');
                _startRecording();
              }
            },
            size: ButtonSize.large,
            isLoading: !_isInitialized,
            child: Icon(
              _isRecording ? Icons.stop : Icons.fiber_manual_record,
              color: _isRecording ? AppColors.error : AppColors.textPrimary,
            ),
          ),

          const Spacer(),

          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingMedium,
              vertical: AppDimensions.paddingSmall,
            ),
            decoration: BoxDecoration(
              color: _isRecording ? AppColors.accent.withOpacity(0.1) : AppColors.backgroundTertiary,
              borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
              border: Border.all(color: AppColors.border),
            ),
            child: AppLabel.primary(
              '${_recordingDuration.inMinutes}:${(_recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}',
              size: LabelSize.medium,
              fontWeight: FontWeight.bold,
              color: _isRecording ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return AppCard.basic(
      margin: const EdgeInsets.symmetric(horizontal: AppDimensions.marginLarge),
      color: AppColors.error.withOpacity(0.1),
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: AppDimensions.iconMedium,
          ),
          SizedBox(width: AppDimensions.marginSmall),
          Expanded(
            child: AppLabel.primary(
              _currentError,
              color: AppColors.error,
            ),
          ),
          AppButton.secondary(
            onPressed: () {
              setState(() {
                _currentError = '';
              });
            },
            size: ButtonSize.small,
            child: Icon(
              Icons.close_rounded,
              size: AppDimensions.iconMedium,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    developer.log('🗑️ SpectrogramScreen: Disposing resources...');

    _uiUpdateTimer?.cancel();
    _pulseController.dispose();
    _cancelStreamSubscriptions();
    _audioService.dispose();

    super.dispose();
  }
}
