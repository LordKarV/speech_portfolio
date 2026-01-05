import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:speech_app/widgets/spectrogram_widget.dart';

class SpectrogramPainter extends CustomPainter {

  final List<List<double>> spectrogramData;

  final bool isRecording;

  final Duration recordingDuration;

  final bool isWavPlayback;

  final WavPlaybackController? wavController;

  final bool isDragging;

  final double dragProgress;

  final Duration playbackDelay;

  SpectrogramPainter({
    required this.spectrogramData,
    required this.isRecording,
    required this.recordingDuration,
    required this.isWavPlayback,
    this.wavController,
    required this.isDragging,
    this.dragProgress = 0.0,
    this.playbackDelay = const Duration(milliseconds: 0),
  });

  @override
  void paint(Canvas canvas, Size size) {
    developer.log('SpectrogramPainter: Starting paint with size: ${size.width}x${size.height}');

    if (spectrogramData.isEmpty) {
      developer.log('SpectrogramPainter: No spectrogram data available');
      return;
    }

    final maxFreqBins = spectrogramData.isNotEmpty ? spectrogramData.first.length : 0;
    if (maxFreqBins == 0) {
      developer.log('SpectrogramPainter: No frequency bins in data');
      return;
    }

    final binHeight = size.height / maxFreqBins;
    final totalColumns = spectrogramData.length;

    developer.log('SpectrogramPainter: Rendering ${totalColumns} columns with ${maxFreqBins} frequency bins each');

    if (isRecording) {
      developer.log('SpectrogramPainter: Painting in recording mode');
      _paintRecordingMode(canvas, size, binHeight, totalColumns);
    } else {

      developer.log('SpectrogramPainter: Painting in playback mode');
      _paintPlaybackMode(canvas, size, binHeight, totalColumns);
    }
  }

  void _paintRecordingMode(Canvas canvas, Size size, double binHeight, int totalColumns) {
    developer.log('SpectrogramPainter: Recording mode - ${totalColumns} columns, duration: ${recordingDuration.inSeconds}s');

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    const double columnWidth = 1.0;

    final maxVisibleColumns = (size.width / columnWidth).ceil();
    developer.log('SpectrogramPainter: Max visible columns: ${maxVisibleColumns}');

    double startX;
    int startColumn = 0;

    if (totalColumns < maxVisibleColumns) {

      startX = size.width - (totalColumns * columnWidth);
      developer.log('SpectrogramPainter: Data fits on screen, aligning right');
    } else {

      startX = 0.0;
      startColumn = totalColumns - maxVisibleColumns;
      developer.log('SpectrogramPainter: Scrolling to show latest data, start column: ${startColumn}');
    }

    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    for (int i = 0; i < math.min(totalColumns, maxVisibleColumns); i++) {
      final colIndex = startColumn + i;
      if (colIndex >= totalColumns) break;

      final column = spectrogramData[colIndex];
      final x = startX + (i * columnWidth);

      for (int bin = 0; bin < column.length; bin++) {
        final magnitude = column[bin];
        final y = size.height - (bin + 1) * binHeight;

        final color = _getGrayscaleColor(magnitude);
        final rect = Rect.fromLTWH(x, y, columnWidth, binHeight);
        canvas.drawRect(rect, Paint()..color = color);
      }
    }

    final recordingLineX = totalColumns < maxVisibleColumns 
        ? startX + (totalColumns * columnWidth)
        : size.width;

    developer.log('SpectrogramPainter: Drawing recording line at x: ${recordingLineX}');
    canvas.drawLine(
      Offset(recordingLineX, 0),
      Offset(recordingLineX, size.height),
      Paint()
        ..color = Colors.red
        ..strokeWidth = 0.5,
    );
  }

  void _paintPlaybackMode(Canvas canvas, Size size, double binHeight, int totalColumns) {
    const double columnWidth = 1.0;
    final totalDataWidth = totalColumns * columnWidth;

    developer.log('SpectrogramPainter: Playback mode - ${totalColumns} columns, total width: ${totalDataWidth}px');

    double progress;
    if (isDragging) {
      progress = dragProgress;
      developer.log('SpectrogramPainter: Using drag progress: ${(progress * 100).toStringAsFixed(1)}%');
    } else if (wavController != null && wavController!.totalDuration.inMilliseconds > 0) {
      final rawPosition = wavController!.currentPosition;
      final totalDuration = wavController!.totalDuration;

      if (rawPosition.inMilliseconds > 0 && rawPosition < totalDuration) {

        final compensatedPosition = Duration(
          milliseconds: rawPosition.inMilliseconds + playbackDelay.inMilliseconds
        );

        progress = compensatedPosition.inMilliseconds / totalDuration.inMilliseconds;
        progress = progress.clamp(0.0, 1.0);

        developer.log('SpectrogramPainter: Applied delay compensation - Raw: ${rawPosition.inSeconds}s, '
            'Compensated: ${compensatedPosition.inSeconds}s');
      } else {

        progress = rawPosition.inMilliseconds / totalDuration.inMilliseconds;
        progress = progress.clamp(0.0, 1.0);
        developer.log('SpectrogramPainter: Using raw position: ${rawPosition.inSeconds}s');
      }
    } else {
      progress = 0.0;
      developer.log('SpectrogramPainter: No controller or duration, using 0% progress');
    }

    final fixedCursorX = size.width * 0.5;

    final targetDataX = progress * totalDataWidth;
    double scrollOffset = targetDataX - fixedCursorX;

    scrollOffset = scrollOffset.clamp(
      -fixedCursorX,
      math.max(0.0, totalDataWidth - fixedCursorX)
    );

    developer.log('SpectrogramPainter: Scroll offset: ${scrollOffset.toStringAsFixed(1)}px, '
        'cursor at: ${fixedCursorX}px');

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    int visibleColumns = 0;
    for (int col = 0; col < totalColumns; col++) {
      final column = spectrogramData[col];
      final x = (col * columnWidth) - scrollOffset;

      if (x + columnWidth >= -10 && x <= size.width + 10) {
        visibleColumns++;

        for (int bin = 0; bin < column.length; bin++) {
          final magnitude = column[bin];
          final y = size.height - (bin + 1) * binHeight;

          final color = _getGrayscaleColor(magnitude);
          final rect = Rect.fromLTWH(x, y, columnWidth, binHeight);
          canvas.drawRect(rect, Paint()..color = color);
        }
      }
    }

    developer.log('SpectrogramPainter: Drew ${visibleColumns} visible columns');

    canvas.drawLine(
      Offset(fixedCursorX, 0),
      Offset(fixedCursorX, size.height),
      Paint()
        ..color = isDragging ? Colors.orange : Colors.red
        ..strokeWidth = 1.5,
    );

    _drawProgressBar(canvas, size, progress);
  }

  void _drawProgressBar(Canvas canvas, Size size, double progress) {
    const double progressBarHeight = 2.0;
    final progressBarY = size.height - progressBarHeight;

    canvas.drawRect(
      Rect.fromLTWH(0, progressBarY, size.width, progressBarHeight),
      Paint()..color = Colors.grey.shade300,
    );

    canvas.drawRect(
      Rect.fromLTWH(0, progressBarY, size.width * progress, progressBarHeight),
      Paint()..color = Colors.red.withOpacity(0.7),
    );
  }

  Color _getGrayscaleColor(double magnitude) {

    final logMagnitude = magnitude > 0 ? math.log(1 + magnitude * 10) / math.log(11) : 0.0;
    final normalizedMag = logMagnitude.clamp(0.0, 1.0);

    if (normalizedMag < 0.05) {
      return Colors.white;
    } else if (normalizedMag < 0.15) {
      final t = (normalizedMag - 0.05) / 0.1;
      return Color.lerp(Colors.white, Colors.grey.shade100, t)!;
    } else if (normalizedMag < 0.3) {
      final t = (normalizedMag - 0.15) / 0.15;
      return Color.lerp(Colors.grey.shade100, Colors.grey.shade300, t)!;
    } else if (normalizedMag < 0.5) {
      final t = (normalizedMag - 0.3) / 0.2;
      return Color.lerp(Colors.grey.shade300, Colors.grey.shade500, t)!;
    } else if (normalizedMag < 0.7) {
      final t = (normalizedMag - 0.5) / 0.2;
      return Color.lerp(Colors.grey.shade500, Colors.grey.shade700, t)!;
    } else if (normalizedMag < 0.85) {
      final t = (normalizedMag - 0.7) / 0.15;
      return Color.lerp(Colors.grey.shade700, Colors.grey.shade900, t)!;
    } else {
      final t = (normalizedMag - 0.85) / 0.15;
      return Color.lerp(Colors.grey.shade900, Colors.black, t)!;
    }
  }

  @override
  bool shouldRepaint(covariant SpectrogramPainter oldDelegate) {

    final shouldRepaint = spectrogramData.length != oldDelegate.spectrogramData.length ||
           spectrogramData != oldDelegate.spectrogramData ||
           isRecording != oldDelegate.isRecording ||
           recordingDuration != oldDelegate.recordingDuration ||
           (isWavPlayback && wavController != null && 
            wavController!.currentPosition != oldDelegate.wavController?.currentPosition) ||
           isDragging != oldDelegate.isDragging ||
           dragProgress != oldDelegate.dragProgress ||
           playbackDelay != oldDelegate.playbackDelay;

    if (shouldRepaint) {
      developer.log('SpectrogramPainter: Repaint needed - data or state changed');
    }

    return shouldRepaint;
  }
}
