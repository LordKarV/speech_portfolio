import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:speech_app/widgets/spectogram_painter.dart';

import '../config/audio_config.dart';

abstract class WavPlaybackController {
  bool get isPlaying;
  Duration get currentPosition;
  Duration get totalDuration;
  int get currentColumnIndex;
  Future<void> play();
  Future<void> pause();
  Future<void> seekToColumn(int columnIndex);
  Future<void> seekToPosition(Duration position);
}

class SpectrogramWidget extends StatefulWidget {

  final List<List<double>> spectrogramData;

  final bool isRecording;

  final Duration recordingDuration;

  final bool isWavPlayback;

  final WavPlaybackController? wavController;

  final VoidCallback? onSeekStart;

  final VoidCallback? onSeekEnd;

  final Function(double progress)? onSeekUpdate;

  final Function(double progress)? onSeekComplete;

  final Duration playbackDelay;

  const SpectrogramWidget({
    super.key,
    required this.spectrogramData,
    this.isRecording = false,
    this.recordingDuration = Duration.zero,
    this.isWavPlayback = false,
    this.wavController,
    this.onSeekStart,
    this.onSeekEnd,
    this.onSeekUpdate,
    this.onSeekComplete,

    this.playbackDelay = const Duration(milliseconds: AudioConfig.delayPlayback),
  });

  @override
  State<SpectrogramWidget> createState() => _SpectrogramWidgetState();
}

class _SpectrogramWidgetState extends State<SpectrogramWidget> {

  bool _isDragging = false;

  double _dragProgress = 0.0;

  bool _wasPlayingBeforeDrag = false;

  @override
  Widget build(BuildContext context) {
    developer.log('SpectrogramWidget: Building widget with ${widget.spectrogramData.length} data points');

    if (widget.spectrogramData.isEmpty) {
      developer.log('SpectrogramWidget: No spectrogram data available, showing empty state');
      return _buildEmptyState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        developer.log('SpectrogramWidget: Layout constraints - width: ${constraints.maxWidth}, height: ${constraints.maxHeight}');

        return GestureDetector(

          onTapDown: widget.isWavPlayback ? _handleTapDown : null,
          onPanStart: widget.isWavPlayback ? _handlePanStart : null,
          onPanUpdate: widget.isWavPlayback ? _handlePanUpdate : null,
          onPanEnd: widget.isWavPlayback ? _handlePanEnd : null,
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: SpectrogramPainter(
              spectrogramData: widget.spectrogramData,
              isRecording: widget.isRecording,
              recordingDuration: widget.recordingDuration,
              isWavPlayback: widget.isWavPlayback,
              wavController: widget.wavController,
              isDragging: _isDragging,
              dragProgress: _dragProgress,
              playbackDelay: widget.playbackDelay,
            ),
          ),
        );
      },
    );
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.wavController == null || !widget.isWavPlayback) {
      developer.log('SpectrogramWidget: Tap ignored - no controller or not in playback mode');
      return;
    }

    developer.log('SpectrogramWidget: Tap detected at x: ${details.localPosition.dx}');

    _wasPlayingBeforeDrag = widget.wavController!.isPlaying;
    if (_wasPlayingBeforeDrag) {
      developer.log('SpectrogramWidget: Pausing playback for tap seek');
      widget.wavController!.pause();
    }

    widget.onSeekStart?.call();

    setState(() {
      _isDragging = true;
    });

    final progress = _calculateProgress(details.localPosition.dx);
    developer.log('SpectrogramWidget: Tap seek to progress: ${(progress * 100).toStringAsFixed(1)}%');

    _updateDragProgress(progress);
    _seekToPositionComplete(progress);
  }

  void _handlePanStart(DragStartDetails details) {
    if (widget.wavController == null || !widget.isWavPlayback) {
      developer.log('SpectrogramWidget: Drag start ignored - no controller or not in playback mode');
      return;
    }

    developer.log('SpectrogramWidget: Drag started at x: ${details.localPosition.dx}');

    _wasPlayingBeforeDrag = widget.wavController!.isPlaying;
    if (_wasPlayingBeforeDrag) {
      developer.log('SpectrogramWidget: Pausing playback for drag seek');
      widget.wavController!.pause();
    }

    widget.onSeekStart?.call();

    setState(() {
      _isDragging = true;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (widget.wavController == null || !widget.isWavPlayback || !_isDragging) {
      return;
    }

    final progress = _calculateProgress(details.localPosition.dx);

    setState(() {
      _dragProgress = progress;
    });

    widget.onSeekUpdate?.call(progress);
  }

  void _handlePanEnd(DragEndDetails details) {
    if (widget.wavController == null || !widget.isWavPlayback) {
      return;
    }

    developer.log('SpectrogramWidget: Drag ended at progress: ${(_dragProgress * 100).toStringAsFixed(1)}%');

    _seekToPositionComplete(_dragProgress);

    setState(() {
      _isDragging = false;
    });

    widget.onSeekEnd?.call();

    if (_wasPlayingBeforeDrag) {
      developer.log('SpectrogramWidget: Resuming playback after drag');
      Future.delayed(const Duration(milliseconds: 200), () {
        widget.wavController!.play();
      });
    }
  }

double _calculateProgress(double x) {
  final RenderBox renderBox = context.findRenderObject() as RenderBox;
  final width = renderBox.size.width;

  final progress = (1.0 - (x / width)).clamp(0.0, 1.0);
  developer.log('SpectrogramWidget: Progress: ${(progress * 100).toStringAsFixed(1)}% from x: $x (inverted)');

  return progress;
}

  void _updateDragProgress(double progress) {
    setState(() {
      _dragProgress = progress;
    });
    developer.log('SpectrogramWidget: Updated drag progress to: ${(progress * 100).toStringAsFixed(1)}%');
  }

  void _seekToPositionComplete(double progress) {

    final rawTargetPosition = Duration(
      milliseconds: (widget.wavController!.totalDuration.inMilliseconds * progress).round()
    );

    final compensatedPosition = Duration(
      milliseconds: math.max(0, rawTargetPosition.inMilliseconds - widget.playbackDelay.inMilliseconds)
    );

    developer.log('SpectrogramWidget: Seeking - Raw: ${rawTargetPosition.inSeconds}s, '
        'Compensated: ${compensatedPosition.inSeconds}s (delay: ${widget.playbackDelay.inMilliseconds}ms)');

    if (widget.onSeekComplete != null) {
      widget.onSeekComplete!(progress);
    } else {
      developer.log('SpectrogramWidget: Using direct seeking fallback');
      widget.wavController!.seekToPosition(compensatedPosition);
    }
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey.shade100,
      child: const Center(
        child: Text(
          'No audio data',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
