import 'package:flutter/material.dart';
import 'package:speech_app/services/recording_repository.dart';
import 'package:speech_app/components/app_button.dart';
import 'package:speech_app/components/app_card.dart';
import 'package:speech_app/components/app_label.dart';
import 'package:speech_app/theme/app_colors.dart';
import 'package:speech_app/theme/app_dimensions.dart';
import 'package:speech_app/theme/app_button_styles.dart';
import 'package:speech_app/screens/home_screen.dart';
import 'dart:developer' as developer;
import 'dart:io';

class TitleAssignmentScreen extends StatefulWidget {
  final String localFilePath;
  final Duration duration;
  final Map<String, dynamic>? classifications;
  final Map<String, dynamic>? spectrogramData;

  const TitleAssignmentScreen({
    super.key,
    required this.localFilePath,
    required this.duration,
    this.classifications,
    this.spectrogramData,
  });

  @override
  State<TitleAssignmentScreen> createState() => _TitleAssignmentScreenState();
}

class _TitleAssignmentScreenState extends State<TitleAssignmentScreen> {
  final _titleController = TextEditingController();
  final _recordingRepository = RecordingRepository();
  bool _isSaving = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _titleController.text = 'Recording ${now.month}/${now.day}/${now.year}';
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _saveRecording() async {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a title for your recording';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = '';
    });

    developer.log('💾 TitleAssignmentScreen: Saving recording with title: "$title"');

    try {
      final file = File(widget.localFilePath);

      if (!await file.exists()) {
        throw Exception('Recording file not found: ${widget.localFilePath}');
      }

      List<Map<String, dynamic>> events = [];
      if (widget.classifications != null) {
        final results = widget.classifications!['results'] as List<dynamic>?;
        if (results != null) {
          for (int i = 0; i < results.length; i++) {
            final result = results[i] as Map<String, dynamic>;

            final probableMatches = result['probableMatches'] as List<dynamic>? ?? [];
            String eventType = 'Speech';
            var confidence = result['confidence'] as double? ?? 0.0;
            if (confidence > 1.0) {
              confidence = confidence / 100.0;
            }
            confidence = confidence.clamp(0.0, 1.0);
            String severity = result['severity'] as String? ?? 'low';

            if (result['type'] != null && result['type'].toString().isNotEmpty) {
              eventType = result['type'].toString();
            } else if (probableMatches.isNotEmpty) {

              final match = probableMatches[0] as String;
              if (match.contains('blocks')) {
                eventType = 'blocks';
              } else if (match.contains('prolongations')) {
                eventType = 'prolongations';
              } else if (match.contains('repetitions')) {
                eventType = 'repetitions';
              } else if (match.contains('interjections')) {
                eventType = 'interjections';
              } else {

                final words = match.split(' ');
                if (words.isNotEmpty) {
                  eventType = words[0].toLowerCase();
                }
              }
            }

            events.add({
              't0': result['t0'] ?? (i * 5000),
              't1': result['t1'] ?? ((i + 1) * 5000),
              'type': eventType,
              'probability': (confidence * 100).round(),
              'conf': confidence,
              'severity': severity,
              'source': result['source'] ?? 'cnn_model',
              'modelVersion': result['modelVersion'] ?? 'v1',
            });
          }
        }
      }

      final recordingId = await _recordingRepository.saveRecording(
        file: file,
        extension: 'wav',
        duration: widget.duration,
        sampleRate: 16000,
        events: events,
        title: title,
        codec: 'pcm16WAV',
        modelVersion: 'v1',
      );

      developer.log('✅ TitleAssignmentScreen: Recording saved successfully: $recordingId');

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording "$title" saved successfully!'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
          ),
        );

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      developer.log('❌ TitleAssignmentScreen: Error saving recording: $e');

      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to save recording: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _discardRecording() async {
    developer.log('🗑️ TitleAssignmentScreen: Discarding recording');

    final bool? shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.backgroundSecondary,
          title: const AppLabel.primary(
            'Discard Recording',
            size: LabelSize.large,
            fontWeight: FontWeight.bold,
          ),
          content: const AppLabel.secondary(
            'Are you sure you want to discard this recording? This action cannot be undone.',
          ),
          actions: [
            AppButton.secondary(
              onPressed: () {
                developer.log('🗑️ TitleAssignmentScreen: Discard cancelled');
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            AppButton.danger(
              onPressed: () {
                developer.log('🗑️ TitleAssignmentScreen: Discard confirmed');
                Navigator.of(context).pop(true);
              },
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );

    if (shouldDiscard == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Save Recording'),
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingXLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withOpacity(0.3),
                            blurRadius: 30,
                            spreadRadius: 0,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.marginXLarge),
                    const AppLabel.primary(
                      'Recording Complete!',
                      size: LabelSize.xlarge,
                      fontWeight: FontWeight.bold,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppDimensions.marginMedium),
                    AppLabel.secondary(
                      'Duration: ${widget.duration.formattedDuration}',
                      size: LabelSize.medium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              Expanded(
                flex: 3,
                child: AppCard.elevated(
                  padding: const EdgeInsets.all(AppDimensions.paddingXXLarge),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppLabel.primary(
                        'Give your recording a title',
                        size: LabelSize.large,
                        fontWeight: FontWeight.bold,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppDimensions.marginLarge),

                      TextField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: 'Recording Title',
                          hintText: 'Enter a descriptive title...',
                          prefixIcon: const Icon(Icons.title_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
                            borderSide: const BorderSide(color: AppColors.accent, width: 2),
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _saveRecording(),
                      ),

                      const SizedBox(height: AppDimensions.marginLarge),

                      if (_errorMessage.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                            border: Border.all(
                              color: AppColors.error.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: AppColors.error,
                                size: 20,
                              ),
                              const SizedBox(width: AppDimensions.marginMedium),
                              Expanded(
                                child: AppLabel.secondary(
                                  _errorMessage,
                                  size: LabelSize.small,
                                  color: AppColors.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppDimensions.marginLarge),
                      ],

                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveRecording,
                        style: AppButtonStyles.primaryButton,
                        child: _isSaving
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: AppDimensions.marginMedium),
                                  Text('Saving...'),
                                ],
                              )
                            : const Text('Save Recording'),
                      ),

                      const SizedBox(height: AppDimensions.marginMedium),

                      TextButton(
                        onPressed: _isSaving ? null : _discardRecording,
                        style: AppButtonStyles.textButton,
                        child: const Text(
                          'Discard Recording',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension DurationFormatting on Duration {
  String get formattedDuration {
    final minutes = inMinutes;
    final seconds = inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
