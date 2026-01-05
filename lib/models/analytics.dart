import 'package:cloud_firestore/cloud_firestore.dart';

class DailyAnalytics {
  final String date;
  final int totalRecordings;
  final int totalDisfluencies;
  final Map<String, int> disfluencyTypes;
  final double averageConfidence;
  final Duration totalRecordingTime;
  final DateTime createdAt;

  DailyAnalytics({
    required this.date,
    required this.totalRecordings,
    required this.totalDisfluencies,
    required this.disfluencyTypes,
    required this.averageConfidence,
    required this.totalRecordingTime,
    required this.createdAt,
  });

  factory DailyAnalytics.fromMap(Map<String, dynamic> map) {
    return DailyAnalytics(
      date: map['date'] ?? '',
      totalRecordings: map['totalRecordings'] ?? 0,
      totalDisfluencies: map['totalDisfluencies'] ?? 0,
      disfluencyTypes: Map<String, int>.from(map['disfluencyTypes'] ?? {}),
      averageConfidence: (map['averageConfidence'] ?? 0.0).toDouble(),
      totalRecordingTime: Duration(milliseconds: map['totalRecordingTimeMs'] ?? 0),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'totalRecordings': totalRecordings,
      'totalDisfluencies': totalDisfluencies,
      'disfluencyTypes': disfluencyTypes,
      'averageConfidence': averageConfidence,
      'totalRecordingTimeMs': totalRecordingTime.inMilliseconds,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  double get disfluencyRate {
    if (totalRecordingTime.inMinutes == 0) return 0.0;
    return totalDisfluencies / totalRecordingTime.inMinutes;
  }

  String get dominantDisfluencyType {
    if (disfluencyTypes.isEmpty) return 'None';
    return disfluencyTypes.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }
}

class WeeklyAnalytics {
  final String weekStart;
  final String weekEnd;
  final int totalRecordings;
  final int totalDisfluencies;
  final Map<String, int> disfluencyTypes;
  final double averageConfidence;
  final Duration totalRecordingTime;
  final List<DailyAnalytics> dailyBreakdown;

  WeeklyAnalytics({
    required this.weekStart,
    required this.weekEnd,
    required this.totalRecordings,
    required this.totalDisfluencies,
    required this.disfluencyTypes,
    required this.averageConfidence,
    required this.totalRecordingTime,
    required this.dailyBreakdown,
  });

  double get averageDisfluencyRate {
    if (totalRecordingTime.inMinutes == 0) return 0.0;
    return totalDisfluencies / totalRecordingTime.inMinutes;
  }

  double? getWeekOverWeekImprovement(WeeklyAnalytics? previousWeek) {
    if (previousWeek == null) return null;
    final currentRate = averageDisfluencyRate;
    final previousRate = previousWeek.averageDisfluencyRate;
    if (previousRate == 0) return null;
    return ((previousRate - currentRate) / previousRate) * 100;
  }
}

class ImprovementInsight {
  final String type;
  final String title;
  final String description;
  final double? value;
  final String period;
  final DateTime generatedAt;

  ImprovementInsight({
    required this.type,
    required this.title,
    required this.description,
    this.value,
    required this.period,
    required this.generatedAt,
  });

  factory ImprovementInsight.fromMap(Map<String, dynamic> map) {
    return ImprovementInsight(
      type: map['type'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      value: map['value']?.toDouble(),
      period: map['period'] ?? '',
      generatedAt: (map['generatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'title': title,
      'description': description,
      if (value != null) 'value': value,
      'period': period,
      'generatedAt': Timestamp.fromDate(generatedAt),
    };
  }
}

class AnalyticsSummary {
  final int totalRecordings;
  final int totalDisfluencies;
  final Duration totalRecordingTime;
  final double overallDisfluencyRate;
  final Map<String, int> totalDisfluencyTypes;
  final double averageConfidence;
  final List<ImprovementInsight> insights;
  final DateTime lastUpdated;

  AnalyticsSummary({
    required this.totalRecordings,
    required this.totalDisfluencies,
    required this.totalRecordingTime,
    required this.overallDisfluencyRate,
    required this.totalDisfluencyTypes,
    required this.averageConfidence,
    required this.insights,
    required this.lastUpdated,
  });

  double? getOverallImprovement(AnalyticsSummary? previousPeriod) {
    if (previousPeriod == null) return null;
    final currentRate = overallDisfluencyRate;
    final previousRate = previousPeriod.overallDisfluencyRate;
    if (previousRate == 0) return null;
    return ((previousRate - currentRate) / previousRate) * 100;
  }
}
