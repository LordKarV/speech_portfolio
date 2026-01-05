import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:developer' as developer;
import 'dart:io';
import '../components/app_button.dart';
import '../components/app_card.dart';
import '../components/app_label.dart';
import '../components/section_header.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../services/recording_repository.dart';
import '../screens/view_all_recordings_screen.dart';
import '../screens/wav_playback_screen.dart';
import '../screens/analytics_screen.dart';
import 'spectrogram_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _recordingRepository = RecordingRepository();
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _recentRecordings = [];
  bool _isLoadingRecordings = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRecentRecordings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      developer.log('🔄 HomeScreen: App resumed, refreshing recordings');
      _loadRecentRecordings();
    }
  }

  void refreshRecordings() {
    developer.log('🔄 HomeScreen: Manual refresh requested');
    _loadRecentRecordings();
  }

  Future<void> _loadRecentRecordings() async {
    setState(() {
      _isLoadingRecordings = true;
      _errorMessage = '';
    });

    developer.log('📋 HomeScreen: Loading recent recordings');

    try {
      final recordings = await _recordingRepository.getRecentRecordings(limit: 3);
      setState(() {
        _recentRecordings = recordings;
        _isLoadingRecordings = false;
      });
      developer.log('✅ HomeScreen: Loaded ${recordings.length} recent recordings');
    } catch (e) {
      developer.log('❌ HomeScreen: Error loading recordings: $e');
      setState(() {
        _errorMessage = 'Failed to load recordings';
        _isLoadingRecordings = false;
      });
    }
  }

  Future<void> _navigateToRecording(BuildContext context) async {
    developer.log('🎤 HomeScreen: Checking microphone permission for new recording');

    final permission = await Permission.microphone.status;
    developer.log('🔐 HomeScreen: Current microphone permission status: $permission');

    if (!permission.isGranted) {
      developer.log('🔐 HomeScreen: Requesting microphone permission');
      final result = await Permission.microphone.request();
      developer.log('🔐 HomeScreen: Permission request result: $result');

      if (!result.isGranted) {
        developer.log('❌ HomeScreen: Microphone permission denied');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Microphone permission is required for recording'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
    }

    developer.log('✅ HomeScreen: Microphone permission granted, navigating to recording screen');
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SpectrogramScreen(),
        ),
      );
    }
  }

  Future<void> _handleSignOut(BuildContext context) async {
    developer.log('🚪 HomeScreen: User requested sign out');

    final bool? shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.backgroundSecondary,
          title: const AppLabel.primary(
            'Sign Out',
            size: LabelSize.large,
            fontWeight: FontWeight.bold,
          ),
          content: const AppLabel.secondary('Are you sure you want to sign out?'),
          actions: [
            AppButton.secondary(
              onPressed: () {
                developer.log('🚪 HomeScreen: Sign out cancelled');
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            AppButton.primary(
              onPressed: () {
                developer.log('🚪 HomeScreen: Sign out confirmed');
                Navigator.of(context).pop(true);
              },
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );

    if (shouldSignOut == true) {
      try {
        developer.log('🚪 HomeScreen: Signing out user');
        await FirebaseAuth.instance.signOut();
        developer.log('✅ HomeScreen: User signed out successfully');
      } catch (e) {
        developer.log('❌ HomeScreen: Error signing out: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error signing out: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  void _handleRecordingTap(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> recordingDoc) async {
    final data = recordingDoc.data();
    final title = data['title'] ?? 'Untitled Recording';
    final storagePath = data['storagePath'] as String?;
    final durationMs = data['durationMs'] as int? ?? 0;

    developer.log('🎵 HomeScreen: Recording tapped - $title');

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
      developer.log('❌ HomeScreen: Error downloading audio file: $e');
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

    developer.log('📥 HomeScreen: Downloading audio file from: $storagePath');
    developer.log('📁 HomeScreen: Saving to: ${localFile.path}');

    await ref.writeToFile(localFile);

    developer.log('✅ HomeScreen: Audio file downloaded successfully');
    return localFile.path;
  }

  void _handleViewAllRecordings(BuildContext context) {
    developer.log('📋 HomeScreen: View all recordings requested');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ViewAllRecordingsScreen(),
      ),
    );
  }

  void _navigateToAnalytics(BuildContext context) {
    developer.log('📊 HomeScreen: Navigating to analytics screen');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AnalyticsScreen(),
      ),
    );
  }

  const HomeScreen({super.key});

  /// Handle navigation to spectrogram screen with microphone permission check
  Future<void> _navigateToRecording(BuildContext context) async {
    developer.log('🎤 HomeScreen: Checking microphone permission for new recording');
    
    // Check current microphone permission status
    final permission = await Permission.microphone.status;
    developer.log('🔐 HomeScreen: Current microphone permission status: $permission');
    
    if (!permission.isGranted) {
      developer.log('🔐 HomeScreen: Requesting microphone permission');
      final result = await Permission.microphone.request();
      developer.log('🔐 HomeScreen: Permission request result: $result');
      
      if (!result.isGranted) {
        developer.log('❌ HomeScreen: Microphone permission denied');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Microphone permission is required for recording'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
    }
    
    developer.log('✅ HomeScreen: Microphone permission granted, navigating to recording screen');
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SpectrogramScreen(),
        ),
      );
    }
  }

  /// Handle user sign out with confirmation dialog
  Future<void> _handleSignOut(BuildContext context) async {
    developer.log('🚪 HomeScreen: User requested sign out');
    
    // Show confirmation dialog
    final bool? shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.backgroundSecondary,
          title: const AppLabel.primary(
            'Sign Out',
            size: LabelSize.large,
            fontWeight: FontWeight.bold,
          ),
          content: const AppLabel.secondary('Are you sure you want to sign out?'),
          actions: [
            AppButton.secondary(
              onPressed: () {
                developer.log('🚪 HomeScreen: Sign out cancelled');
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            AppButton.primary(
              onPressed: () {
                developer.log('🚪 HomeScreen: Sign out confirmed');
                Navigator.of(context).pop(true);
              },
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );
    
    if (shouldSignOut == true) {
      try {
        developer.log('🚪 HomeScreen: Signing out user');
        await FirebaseAuth.instance.signOut();
        developer.log('✅ HomeScreen: User signed out successfully');
      } catch (e) {
        developer.log('❌ HomeScreen: Error signing out: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error signing out: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  /// Handle recording item tap (placeholder for future implementation)
  void _handleRecordingTap(BuildContext context, Map<String, String> recording) {
    developer.log('🎵 HomeScreen: Recording tapped - ${recording['title']}');
    
    // TODO: Navigate to recording details or playback screen
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing ${recording['title']}...'),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  /// Handle view all recordings tap (placeholder for future implementation)
  void _handleViewAllRecordings(BuildContext context) {
    developer.log('📋 HomeScreen: View all recordings requested');
    
    // TODO: Navigate to full history screen
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Full history coming soon!'),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    final User? user = FirebaseAuth.instance.currentUser;
    final String displayName = user?.displayName ?? user?.email?.split('@')[0] ?? 'User';

    developer.log('🏠 HomeScreen: Building home screen for user: $displayName');
    developer.log('📊 HomeScreen: Displaying ${_recentRecordings.length} recent recordings');

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              _buildHeader(context, displayName),

              const SizedBox(height: AppDimensions.marginLarge),

              _buildNewRecordingCard(context),

              const SizedBox(height: AppDimensions.marginXLarge),

              _buildRecentRecordingsHeader(context),

              const SizedBox(height: AppDimensions.marginMedium),

              _buildRecentRecordingsList(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String displayName) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppLabel.primary(
                'Welcome, ${displayName.capitalize()}',
                size: LabelSize.xlarge,
                fontWeight: FontWeight.bold,
              ),
              const SizedBox(height: AppDimensions.marginXSmall),
              const AppLabel.secondary('Ready to analyze your speech?'),
            ],
          ),
        ),

        Row(
          children: [

            AppButton.secondary(
              onPressed: () => _navigateToAnalytics(context),
              size: ButtonSize.small,
              child: const Icon(Icons.analytics_rounded, size: 20),
            ),
            const SizedBox(width: AppDimensions.marginSmall),

            _buildUserProfileMenu(context, displayName),
          ],
        ),
      ],
    );
  }

  Widget _buildUserProfileMenu(BuildContext context, String displayName) {
    return PopupMenuButton<String>(
      icon: CircleAvatar(
        radius: 23,
        backgroundColor: AppColors.accent,
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      onSelected: (value) async {
        developer.log('👤 HomeScreen: Profile menu item selected: $value');
        if (value == 'signout') {
          await _handleSignOut(context);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'signout',
          child: Row(
            children: [
              Icon(Icons.logout, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const AppLabel.secondary('Sign out'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNewRecordingCard(BuildContext context) {
    return GestureDetector(
      onTap: () => _navigateToRecording(context),
      child: SizedBox(
        width: double.infinity,
        child: AppCard.elevated(
          padding: const EdgeInsets.all(AppDimensions.paddingXXLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 0,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  size: 50,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppDimensions.marginXLarge),
              const AppLabel.primary(
                "New Recording",  
                size: LabelSize.xlarge,
                fontWeight: FontWeight.bold,
              ),
              const SizedBox(height: AppDimensions.marginMedium),
              const AppLabel.secondary(
                "Tap to start recording.",
                size: LabelSize.medium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentRecordingsHeader(BuildContext context) {
    return SectionHeader(
      title: 'Recent Recordings',
      action: AppButton.tertiary(
        onPressed: () => _handleViewAllRecordings(context),
        child: const Text('View all'),
      ),
    );
  }

  Widget _buildRecentRecordingsList(BuildContext context) {
    return Expanded(
      child: _isLoadingRecordings
          ? const Center(
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
            )
          : _errorMessage.isNotEmpty
              ? Center(
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
                          onPressed: _loadRecentRecordings,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : _recentRecordings.isEmpty
                  ? const Center(
                      child: AppLabel.secondary('No recordings yet'),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadRecentRecordings,
                      color: AppColors.accent,
                      child: ListView.separated(
                        itemCount: _recentRecordings.length,
                        separatorBuilder: (context, index) => const SizedBox(height: AppDimensions.marginSmall),
                        itemBuilder: (context, index) {
                          final recording = _recentRecordings[index];
                          return _buildRecordingListItem(context, recording);
                        },
                      ),
                    ),
    );
  }

  Widget _buildRecordingListItem(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> recordingDoc) {
    final data = recordingDoc.data();
    final title = data['title'] ?? 'Untitled Recording';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final durationMs = data['durationMs'] as int? ?? 0;
    final duration = Duration(milliseconds: durationMs);

    return GestureDetector(
      onTap: () => _handleRecordingTap(context, recordingDoc),
      onLongPress: () => _showDeleteRecordingConfirmation(context, recordingDoc),
      child: AppCard.basic(
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
                  _formatDate(createdAt),
                  size: LabelSize.small,
                ),
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.paddingMedium,
                  vertical: AppDimensions.paddingSmall,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
                  border: Border.all(
                    color: AppColors.accent.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: AppLabel.primary(
                  _formatDuration(duration),
                  fontWeight: FontWeight.w600,
                  size: LabelSize.small,
                  color: AppColors.accent,
                ),
              ),
              SizedBox(width: AppDimensions.marginSmall),
              Icon(
                Icons.more_vert,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
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

  void _showDeleteRecordingConfirmation(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> recordingDoc) {
    final data = recordingDoc.data();
    final title = data['title'] ?? 'Untitled Recording';

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
            'Are you sure you want to delete "$title"? This action cannot be undone.',
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
                _deleteRecording(recordingDoc);
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

  Future<void> _deleteRecording(QueryDocumentSnapshot<Map<String, dynamic>> recordingDoc) async {
    try {
      developer.log('🗑️ Deleting recording: ${recordingDoc.id}');

      final data = recordingDoc.data();
      final title = data['title'] ?? 'Untitled Recording';

      await recordingDoc.reference.delete();

      final localFilePath = data['localFilePath'] as String?;
      if (localFilePath != null && localFilePath.isNotEmpty) {
        try {
          final file = File(localFilePath);
          if (await file.exists()) {
            await file.delete();
            developer.log('✅ Local file deleted: $localFilePath');
          }
        } catch (e) {
          developer.log('⚠️ Could not delete local file: $e');
        }
      }

      setState(() {
        _recentRecordings.removeWhere((doc) => doc.id == recordingDoc.id);
      });

      developer.log('✅ Recording deleted successfully: $title');

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
      developer.log('❌ Error deleting recording: $e');

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

extension StringCapitalization on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}
