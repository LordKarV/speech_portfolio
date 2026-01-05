import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/analytics.dart';

class AnalyticsService {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Future<AnalyticsSummary> getAnalyticsSummary({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');

    developer.log('📊 AnalyticsService: Getting analytics summary from ${startDate.toIso8601String()} to ${endDate.toIso8601String()}');

    try {

      final recordingsSnapshot = await _fs
          .collection('users')
          .doc(uid)
          .collection('recordings')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      int totalRecordings = 0;
      int totalDisfluencies = 0;
      Duration totalRecordingTime = Duration.zero;
      Map<String, int> totalDisfluencyTypes = {};
      double totalConfidence = 0.0;
      int recordingsWithConfidence = 0;

      for (final recordingDoc in recordingsSnapshot.docs) {
        final recordingData = recordingDoc.data();
        totalRecordings++;

        final durationMs = recordingData['durationMs'] as int? ?? 0;
        totalRecordingTime += Duration(milliseconds: durationMs);

        final eventsSnapshot = await recordingDoc.reference
            .collection('events')
            .get();

        for (final eventDoc in eventsSnapshot.docs) {
          final eventData = eventDoc.data();
          totalDisfluencies++;

          final type = eventData['type'] as String? ?? 'Unknown';
          totalDisfluencyTypes[type] = (totalDisfluencyTypes[type] ?? 0) + 1;

          final confidence = eventData['conf'] as double? ?? 0.0;
          if (confidence > 0) {
            totalConfidence += confidence;
            recordingsWithConfidence++;
          }
        }
      }

      final averageConfidence = recordingsWithConfidence > 0 
          ? totalConfidence / recordingsWithConfidence 
          : 0.0;

      final overallDisfluencyRate = totalRecordingTime.inMinutes > 0
          ? totalDisfluencies / totalRecordingTime.inMinutes
          : 0.0;

      final insights = await _generateInsights(
        totalRecordings: totalRecordings,
        totalDisfluencies: totalDisfluencies,
        totalRecordingTime: totalRecordingTime,
        disfluencyTypes: totalDisfluencyTypes,
        averageConfidence: averageConfidence,
        startDate: startDate,
        endDate: endDate,
      );

      final summary = AnalyticsSummary(
        totalRecordings: totalRecordings,
        totalDisfluencies: totalDisfluencies,
        totalRecordingTime: totalRecordingTime,
        overallDisfluencyRate: overallDisfluencyRate,
        totalDisfluencyTypes: totalDisfluencyTypes,
        averageConfidence: averageConfidence,
        insights: insights,
        lastUpdated: DateTime.now(),
      );

      developer.log('✅ AnalyticsService: Generated summary - $totalRecordings recordings, $totalDisfluencies disfluencies');
      return summary;

    } catch (e) {
      developer.log('❌ AnalyticsService: Error getting analytics summary: $e');
      rethrow;
    }
  }

  Future<List<DailyAnalytics>> getDailyAnalytics({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');

    developer.log('📊 AnalyticsService: Getting daily analytics from ${startDate.toIso8601String()} to ${endDate.toIso8601String()}');

    try {

      final recordingsSnapshot = await _fs
          .collection('users')
          .doc(uid)
          .collection('recordings')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> recordingsByDate = {};

      for (final recordingDoc in recordingsSnapshot.docs) {
        final createdAt = (recordingDoc.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        final dateKey = _formatDate(createdAt);
        recordingsByDate.putIfAbsent(dateKey, () => []).add(recordingDoc);
      }

      List<DailyAnalytics> dailyAnalytics = [];

      for (final entry in recordingsByDate.entries) {
        final date = entry.key;
        final recordings = entry.value;

        int totalRecordings = recordings.length;
        int totalDisfluencies = 0;
        Map<String, int> disfluencyTypes = {};
        double totalConfidence = 0.0;
        int eventsWithConfidence = 0;
        Duration totalRecordingTime = Duration.zero;

        for (final recordingDoc in recordings) {
          final recordingData = recordingDoc.data();

          final durationMs = recordingData['durationMs'] as int? ?? 0;
          totalRecordingTime += Duration(milliseconds: durationMs);

          final eventsSnapshot = await recordingDoc.reference
              .collection('events')
              .get();

          for (final eventDoc in eventsSnapshot.docs) {
            final eventData = eventDoc.data();
            totalDisfluencies++;

            final type = eventData['type'] as String? ?? 'Unknown';
            disfluencyTypes[type] = (disfluencyTypes[type] ?? 0) + 1;

            final confidence = eventData['conf'] as double? ?? 0.0;
            if (confidence > 0) {
              totalConfidence += confidence;
              eventsWithConfidence++;
            }
          }
        }

        final averageConfidence = eventsWithConfidence > 0 
            ? totalConfidence / eventsWithConfidence 
            : 0.0;

        dailyAnalytics.add(DailyAnalytics(
          date: date,
          totalRecordings: totalRecordings,
          totalDisfluencies: totalDisfluencies,
          disfluencyTypes: disfluencyTypes,
          averageConfidence: averageConfidence,
          totalRecordingTime: totalRecordingTime,
          createdAt: DateTime.now(),
        ));
      }

      dailyAnalytics.sort((a, b) => a.date.compareTo(b.date));

      developer.log('✅ AnalyticsService: Generated ${dailyAnalytics.length} daily analytics');
      return dailyAnalytics;

    } catch (e) {
      developer.log('❌ AnalyticsService: Error getting daily analytics: $e');
      rethrow;
    }
  }

  Future<List<WeeklyAnalytics>> getWeeklyAnalytics({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final dailyAnalytics = await getDailyAnalytics(
      startDate: startDate,
      endDate: endDate,
    );

    List<WeeklyAnalytics> weeklyAnalytics = [];

    Map<String, List<DailyAnalytics>> weeklyGroups = {};

    for (final daily in dailyAnalytics) {
      final date = DateTime.parse(daily.date);
      final weekStart = _getWeekStart(date);
      final weekKey = _formatDate(weekStart);

      weeklyGroups.putIfAbsent(weekKey, () => []).add(daily);
    }

    for (final entry in weeklyGroups.entries) {
      final weekStart = entry.key;
      final dailyBreakdown = entry.value;

      int totalRecordings = dailyBreakdown.fold(0, (sum, daily) => sum + daily.totalRecordings);
      int totalDisfluencies = dailyBreakdown.fold(0, (sum, daily) => sum + daily.totalDisfluencies);
      Duration totalRecordingTime = dailyBreakdown.fold(
        Duration.zero, 
        (sum, daily) => sum + daily.totalRecordingTime
      );

      Map<String, int> disfluencyTypes = {};
      double totalConfidence = 0.0;
      int daysWithConfidence = 0;

      for (final daily in dailyBreakdown) {

        for (final typeEntry in daily.disfluencyTypes.entries) {
          disfluencyTypes[typeEntry.key] = 
              (disfluencyTypes[typeEntry.key] ?? 0) + typeEntry.value;
        }

        if (daily.averageConfidence > 0) {
          totalConfidence += daily.averageConfidence;
          daysWithConfidence++;
        }
      }

      final averageConfidence = daysWithConfidence > 0 
          ? totalConfidence / daysWithConfidence 
          : 0.0;

      final weekEnd = _getWeekEnd(DateTime.parse(weekStart));

      weeklyAnalytics.add(WeeklyAnalytics(
        weekStart: weekStart,
        weekEnd: _formatDate(weekEnd),
        totalRecordings: totalRecordings,
        totalDisfluencies: totalDisfluencies,
        disfluencyTypes: disfluencyTypes,
        averageConfidence: averageConfidence,
        totalRecordingTime: totalRecordingTime,
        dailyBreakdown: dailyBreakdown,
      ));
    }

    weeklyAnalytics.sort((a, b) => a.weekStart.compareTo(b.weekStart));

    developer.log('✅ AnalyticsService: Generated ${weeklyAnalytics.length} weekly analytics');
    return weeklyAnalytics;
  }

  Future<List<ImprovementInsight>> _generateInsights({
    required int totalRecordings,
    required int totalDisfluencies,
    required Duration totalRecordingTime,
    required Map<String, int> disfluencyTypes,
    required double averageConfidence,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    List<ImprovementInsight> insights = [];

    final periodDays = endDate.difference(startDate).inDays + 1;
    final periodWeeks = (periodDays / 7).ceil();

    if (totalRecordings > 0) {
      final avgRecordingsPerDay = totalRecordings / periodDays;
      if (avgRecordingsPerDay >= 1.0) {
        insights.add(ImprovementInsight(
          type: 'consistency',
          title: 'Great Consistency!',
          description: 'You\'ve been recording ${avgRecordingsPerDay.toStringAsFixed(1)} times per day on average. Keep it up!',
          period: 'current',
          generatedAt: DateTime.now(),
        ));
      } else if (avgRecordingsPerDay >= 0.5) {
        insights.add(ImprovementInsight(
          type: 'consistency',
          title: 'Good Progress',
          description: 'You\'re recording ${avgRecordingsPerDay.toStringAsFixed(1)} times per day. Try to increase to daily practice.',
          period: 'current',
          generatedAt: DateTime.now(),
        ));
      }
    }

    if (totalRecordingTime.inMinutes > 0) {
      final disfluencyRate = totalDisfluencies / totalRecordingTime.inMinutes;
      if (disfluencyRate < 2.0) {
        insights.add(ImprovementInsight(
          type: 'improvement',
          title: 'Low Disfluency Rate',
          description: 'Your disfluency rate is ${disfluencyRate.toStringAsFixed(1)} per minute, which is excellent!',
          value: disfluencyRate,
          period: 'current',
          generatedAt: DateTime.now(),
        ));
      } else if (disfluencyRate < 5.0) {
        insights.add(ImprovementInsight(
          type: 'improvement',
          title: 'Moderate Disfluency Rate',
          description: 'Your disfluency rate is ${disfluencyRate.toStringAsFixed(1)} per minute. Consider practicing relaxation techniques.',
          value: disfluencyRate,
          period: 'current',
          generatedAt: DateTime.now(),
        ));
      }
    }

    if (disfluencyTypes.isNotEmpty) {
      final dominantType = disfluencyTypes.entries.reduce((a, b) => a.value > b.value ? a : b);
      final percentage = (dominantType.value / totalDisfluencies) * 100;

      insights.add(ImprovementInsight(
        type: 'trend',
        title: 'Most Common Type',
        description: '${dominantType.key} represents ${percentage.toStringAsFixed(1)}% of your disfluencies. Focus on techniques for this type.',
        value: percentage,
        period: 'current',
        generatedAt: DateTime.now(),
      ));
    }

    if (averageConfidence > 0) {
      if (averageConfidence > 0.7) {
        insights.add(ImprovementInsight(
          type: 'improvement',
          title: 'High Confidence Detection',
          description: 'Your speech analysis shows high confidence levels, indicating clear speech patterns.',
          value: averageConfidence * 100,
          period: 'current',
          generatedAt: DateTime.now(),
        ));
      }
    }

    return insights;
  }

  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    return date.subtract(Duration(days: weekday - 1));
  }

  DateTime _getWeekEnd(DateTime weekStart) {
    return weekStart.add(const Duration(days: 6));
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Map<String, DateTime> getDateRange(String period) {
    final now = DateTime.now();
    switch (period) {
      case 'week':
        return {
          'start': now.subtract(const Duration(days: 7)),
          'end': now,
        };
      case 'month':
        return {
          'start': DateTime(now.year, now.month - 1, now.day),
          'end': now,
        };
      case '3months':
        return {
          'start': DateTime(now.year, now.month - 3, now.day),
          'end': now,
        };
      case '6months':
        return {
          'start': DateTime(now.year, now.month - 6, now.day),
          'end': now,
        };
      case 'year':
        return {
          'start': DateTime(now.year - 1, now.month, now.day),
          'end': now,
        };
      default:
        return {
          'start': now.subtract(const Duration(days: 30)),
          'end': now,
        };
    }
  }
}
