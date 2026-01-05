import 'package:flutter/material.dart';
import 'package:speech_app/services/recording_repository.dart';
import 'package:speech_app/components/app_button.dart';
import 'package:speech_app/components/app_card.dart';
import 'package:speech_app/components/app_label.dart';
import 'package:speech_app/theme/app_colors.dart';
import 'package:speech_app/theme/app_dimensions.dart';
import 'package:speech_app/screens/wav_playback_screen.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

class ViewAllRecordingsScreen extends StatefulWidget {
  const ViewAllRecordingsScreen({super.key});

  @override
  State<ViewAllRecordingsScreen> createState() => _ViewAllRecordingsScreenState();
}

class _ViewAllRecordingsScreenState extends State<ViewAllRecordingsScreen> {
  final _recordingRepository = RecordingRepository();
  final _searchController = TextEditingController();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _recordings = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredRecordings = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecordings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    developer.log('📋 ViewAllRecordingsScreen: Loading all recordings');

    try {
      final recordings = await _recordingRepository.getRecentRecordings(limit: 100);
      setState(() {
        _recordings = recordings;
        _filteredRecordings = recordings;
        _isLoading = false;
      });
      developer.log('✅ ViewAllRecordingsScreen: Loaded ${recordings.length} recordings');
    } catch (e) {
      developer.log('❌ ViewAllRecordingsScreen: Error loading recordings: $e');
      setState(() {
        _errorMessage = 'Failed to load recordings: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _filterRecordings(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredRecordings = _recordings;
      } else {
        _filteredRecordings = _recordings.where((recordingDoc) {
          final data = recordingDoc.data();
          final title = data['title'] ?? 'Untitled Recording';
          final createdAt = data['createdAt'] as Timestamp?;
          final formattedDate = _formatDate(createdAt?.toDate());

          return title.toLowerCase().contains(_searchQuery) ||
                 formattedDate.toLowerCase().contains(_searchQuery);
        }).toList();
      }
    });
  }

  void _handleRecordingTap(QueryDocumentSnapshot<Map<String, dynamic>> recordingDoc) async {
    final data = recordingDoc.data();
    final title = data['title'] ?? 'Untitled Recording';
    final storagePath = data['storagePath'] as String?;
    final durationMs = data['durationMs'] as int? ?? 0;

    developer.log('🎵 ViewAllRecordingsScreen: Playing recording: $title');

    if (storagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recording file not found'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {

      final localFilePath = await _downloadAudioFile(storagePath, title);

      if (mounted) {
        Navigator.of(context).pop();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WavPlaybackScreen(
              wavFilePath: localFilePath,
              recordingDuration: Duration(milliseconds: durationMs),
              recordingId: recordingDoc.id,
            ),
          ),
        );
      }
    } catch (e) {
      developer.log('❌ ViewAllRecordingsScreen: Error downloading audio file: $e');
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load recording: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<String> _downloadAudioFile(String storagePath, String title) async {
    final storage = FirebaseStorage.instance;
    final ref = storage.ref(storagePath);

    final directory = await getApplicationDocumentsDirectory();
    final fileName = '${title.replaceAll(RegExp(r'[^\w\s-]'), '_')}_${DateTime.now().millisecondsSinceEpoch}.wav';
    final localFile = File('${directory.path}/$fileName');

    developer.log('📥 ViewAllRecordingsScreen: Downloading audio file from: $storagePath');
    developer.log('📁 ViewAllRecordingsScreen: Saving to: ${localFile.path}');

    await ref.writeToFile(localFile);

    developer.log('✅ ViewAllRecordingsScreen: Audio file downloaded successfully');
    return localFile.path;
  }

  Future<void> _handleDeleteRecording(QueryDocumentSnapshot<Map<String, dynamic>> recordingDoc) async {
    final data = recordingDoc.data();
    final title = data['title'] ?? 'Untitled Recording';

    developer.log('🗑️ ViewAllRecordingsScreen: Deleting recording: $title');

    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.backgroundSecondary,
          title: const AppLabel.primary(
            'Delete Recording',
            size: LabelSize.large,
            fontWeight: FontWeight.bold,
          ),
          content: AppLabel.secondary(
            'Are you sure you want to delete "$title"? This action cannot be undone.',
          ),
          actions: [
            AppButton.secondary(
              onPressed: () {
                developer.log('🗑️ ViewAllRecordingsScreen: Delete cancelled');
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            AppButton.danger(
              onPressed: () {
                developer.log('🗑️ ViewAllRecordingsScreen: Delete confirmed');
                Navigator.of(context).pop(true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      try {
        developer.log('🗑️ ViewAllRecordingsScreen: Deleting recording from Firestore');

        await recordingDoc.reference.delete();

        final localFilePath = data['localFilePath'] as String?;
        if (localFilePath != null && localFilePath.isNotEmpty) {
          try {
            final file = File(localFilePath);
            if (await file.exists()) {
              await file.delete();
              developer.log('✅ ViewAllRecordingsScreen: Local file deleted: $localFilePath');
            }
          } catch (e) {
            developer.log('⚠️ ViewAllRecordingsScreen: Could not delete local file: $e');
          }
        }

        setState(() {
          _recordings.removeWhere((doc) => doc.id == recordingDoc.id);
          _filteredRecordings.removeWhere((doc) => doc.id == recordingDoc.id);
        });

        developer.log('✅ ViewAllRecordingsScreen: Recording deleted successfully: $title');

        if (mounted) {
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

      } catch (e) {
        developer.log('❌ ViewAllRecordingsScreen: Error deleting recording: $e');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: AppLabel.primary('Failed to delete recording: $e', color: Colors.white),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('All Recordings'),
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loadRecordings,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [

            Padding(
              padding: const EdgeInsets.all(AppDimensions.paddingLarge),
              child: TextField(
                controller: _searchController,
                onChanged: _filterRecordings,
                decoration: InputDecoration(
                  hintText: 'Search recordings...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            _filterRecordings('');
                          },
                          icon: const Icon(Icons.clear_rounded),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
                    borderSide: const BorderSide(color: AppColors.accent, width: 2),
                  ),
                ),
              ),
            ),

            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: AppColors.accent,
              strokeWidth: 3,
            ),
            SizedBox(height: AppDimensions.marginLarge),
            AppLabel.secondary('Loading recordings...'),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: AppCard.elevated(
          padding: const EdgeInsets.all(AppDimensions.paddingXLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 48,
              ),
              const SizedBox(height: AppDimensions.marginLarge),
              AppLabel.primary(
                'Error Loading Recordings',
                size: LabelSize.large,
                fontWeight: FontWeight.bold,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.marginMedium),
              AppLabel.secondary(
                _errorMessage,
                size: LabelSize.medium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.marginLarge),
              AppButton.primary(
                onPressed: _loadRecordings,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredRecordings.isEmpty) {
      return Center(
        child: AppCard.elevated(
          padding: const EdgeInsets.all(AppDimensions.paddingXLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.mic_off_rounded,
                color: AppColors.textTertiary,
                size: 48,
              ),
              const SizedBox(height: AppDimensions.marginLarge),
              AppLabel.primary(
                _searchQuery.isNotEmpty ? 'No Results Found' : 'No Recordings Yet',
                size: LabelSize.large,
                fontWeight: FontWeight.bold,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.marginMedium),
              AppLabel.secondary(
                _searchQuery.isNotEmpty 
                    ? 'Try adjusting your search terms'
                    : 'Start recording to see your speech analysis here',
                size: LabelSize.medium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingLarge),
      itemCount: _filteredRecordings.length,
      itemBuilder: (context, index) {
        final recording = _filteredRecordings[index];
        return _buildRecordingListItem(recording);
      },
    );
  }

  Widget _buildRecordingListItem(QueryDocumentSnapshot<Map<String, dynamic>> recordingDoc) {
    final data = recordingDoc.data();
    final title = data['title'] ?? 'Untitled Recording';
    final createdAt = data['createdAt'] as Timestamp?;
    final durationMs = data['durationMs'] as int? ?? 0;
    final duration = Duration(milliseconds: durationMs);

    return AppCard.basic(
      margin: const EdgeInsets.only(bottom: AppDimensions.marginSmall),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          vertical: AppDimensions.paddingMedium,
          horizontal: AppDimensions.paddingLarge,
        ),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(0.2),
                blurRadius: 8,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.audiotrack_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        title: AppLabel.primary(
          title,
          fontWeight: FontWeight.w600,
          size: LabelSize.medium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppDimensions.marginXSmall),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 14,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: AppDimensions.marginXSmall),
              AppLabel.secondary(
                _formatDate(createdAt?.toDate()),
                size: LabelSize.small,
              ),
              const SizedBox(width: AppDimensions.marginMedium),
              Icon(
                Icons.access_time_rounded,
                size: 14,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: AppDimensions.marginXSmall),
              AppLabel.secondary(
                '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                size: LabelSize.small,
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'play':
                _handleRecordingTap(recordingDoc);
                break;
              case 'delete':
                _handleDeleteRecording(recordingDoc);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem<String>(
              value: 'play',
              child: Row(
                children: [
                  Icon(Icons.play_arrow_rounded, color: AppColors.accent),
                  SizedBox(width: 8),
                  Text('Play'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_rounded, color: AppColors.error),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        ),
        onTap: () => _handleRecordingTap(recordingDoc),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown date';

    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      final months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
  }
}
