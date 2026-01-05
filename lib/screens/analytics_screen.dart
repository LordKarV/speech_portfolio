import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:developer' as developer;
import '../models/analytics.dart';
import '../services/analytics_service.dart';
import '../components/app_button.dart';
import '../components/app_card.dart';
import '../components/app_label.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _analyticsService = AnalyticsService();

  String _selectedPeriod = 'month';
  bool _isLoading = true;
  String _errorMessage = '';

  AnalyticsSummary? _summary;
  List<DailyAnalytics> _dailyAnalytics = [];
  List<WeeklyAnalytics> _weeklyAnalytics = [];

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      developer.log('📊 AnalyticsScreen: Loading analytics for period: $_selectedPeriod');

      final dateRange = _analyticsService.getDateRange(_selectedPeriod);
      final startDate = dateRange['start']!;
      final endDate = dateRange['end']!;

      final results = await Future.wait([
        _analyticsService.getAnalyticsSummary(startDate: startDate, endDate: endDate),
        _analyticsService.getDailyAnalytics(startDate: startDate, endDate: endDate),
        _analyticsService.getWeeklyAnalytics(startDate: startDate, endDate: endDate),
      ]);

      setState(() {
        _summary = results[0] as AnalyticsSummary;
        _dailyAnalytics = results[1] as List<DailyAnalytics>;
        _weeklyAnalytics = results[2] as List<WeeklyAnalytics>;
        _isLoading = false;
      });

      developer.log('✅ AnalyticsScreen: Loaded analytics successfully');
    } catch (e) {
      developer.log('❌ AnalyticsScreen: Error loading analytics: $e');
      setState(() {
        _errorMessage = 'Failed to load analytics: $e';
        _isLoading = false;
      });
    }
  }

  void _onPeriodChanged(String period) {
    if (period != _selectedPeriod) {
      setState(() {
        _selectedPeriod = period;
      });
      _loadAnalytics();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Speech Analytics'),
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loadAnalytics,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading 
          ? _buildLoadingState()
          : _errorMessage.isNotEmpty
              ? _buildErrorState()
              : _buildAnalyticsContent(),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: AppColors.accent,
            strokeWidth: 3,
          ),
          SizedBox(height: AppDimensions.marginLarge),
          AppLabel.secondary('Loading analytics...'),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
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
              'Error Loading Analytics',
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
              onPressed: _loadAnalytics,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsContent() {
    if (_summary == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.paddingLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          _buildPeriodSelector(),

          const SizedBox(height: AppDimensions.marginLarge),

          _buildSummaryCards(),

          const SizedBox(height: AppDimensions.marginLarge),

          _buildCharts(),

          const SizedBox(height: AppDimensions.marginLarge),

          _buildInsights(),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return AppCard.basic(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppLabel.primary(
            'Time Period',
            size: LabelSize.medium,
            fontWeight: FontWeight.w600,
          ),
          const SizedBox(height: AppDimensions.marginMedium),
          Wrap(
            spacing: AppDimensions.marginSmall,
            children: [
              'week',
              'month',
              '3months',
              '6months',
              'year',
            ].map((period) {
              final isSelected = _selectedPeriod == period;
              return FilterChip(
                label: Text(_getPeriodLabel(period)),
                selected: isSelected,
                onSelected: (selected) => _onPeriodChanged(period),
                selectedColor: AppColors.accent.withOpacity(0.2),
                checkmarkColor: AppColors.accent,
                labelStyle: TextStyle(
                  color: isSelected ? AppColors.accent : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _getPeriodLabel(String period) {
    switch (period) {
      case 'week': return '1 Week';
      case 'month': return '1 Month';
      case '3months': return '3 Months';
      case '6months': return '6 Months';
      case 'year': return '1 Year';
      default: return period;
    }
  }

  Widget _buildSummaryCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                title: 'Total Recordings',
                value: _summary!.totalRecordings.toString(),
                icon: Icons.mic_rounded,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: AppDimensions.marginMedium),
            Expanded(
              child: _buildSummaryCard(
                title: 'Total Disfluencies',
                value: _summary!.totalDisfluencies.toString(),
                icon: Icons.analytics_rounded,
                color: AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.marginMedium),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                title: 'Disfluency Rate',
                value: '${_summary!.overallDisfluencyRate.toStringAsFixed(1)}/min',
                icon: Icons.trending_up_rounded,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return AppCard.basic(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: AppDimensions.marginSmall),
              Expanded(
                child: AppLabel.secondary(
                  title,
                  size: LabelSize.small,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.marginSmall),
          AppLabel.primary(
            value,
            size: LabelSize.large,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ],
      ),
    );
  }

  Widget _buildCharts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppLabel.primary(
          'Trends Over Time',
          size: LabelSize.large,
          fontWeight: FontWeight.bold,
        ),
        const SizedBox(height: AppDimensions.marginMedium),

        AppCard.basic(
          padding: const EdgeInsets.all(AppDimensions.paddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppLabel.primary(
                'Daily Disfluency Count',
                size: LabelSize.medium,
                fontWeight: FontWeight.w600,
              ),
              const SizedBox(height: AppDimensions.marginMedium),
              SizedBox(
                height: 200,
                child: _buildDailyDisfluencyChart(),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppDimensions.marginMedium),

        AppCard.basic(
          padding: const EdgeInsets.all(AppDimensions.paddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppLabel.primary(
                'Disfluency Types Distribution',
                size: LabelSize.medium,
                fontWeight: FontWeight.w600,
              ),
              const SizedBox(height: AppDimensions.marginMedium),
              SizedBox(
                height: 200,
                child: _buildDisfluencyTypesChart(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDailyDisfluencyChart() {
    if (_dailyAnalytics.isEmpty) {
      return const Center(
        child: AppLabel.secondary('No data available for the selected period'),
      );
    }

    final maxDisfluencies = _dailyAnalytics.fold(0, (max, daily) => 
        daily.totalDisfluencies > max ? daily.totalDisfluencies : max);

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() < _dailyAnalytics.length) {
                  final date = DateTime.parse(_dailyAnalytics[value.toInt()].date);
                  return Text(
                    '${date.month}/${date.day}',
                    style: const TextStyle(fontSize: 10),
                  );
                }
                return const Text('');
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: _dailyAnalytics.asMap().entries.map((entry) {
              return FlSpot(entry.key.toDouble(), entry.value.totalDisfluencies.toDouble());
            }).toList(),
            isCurved: true,
            color: AppColors.accent,
            barWidth: 3,
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.accent.withOpacity(0.1),
            ),
          ),
        ],
        minX: 0,
        maxX: (_dailyAnalytics.length - 1).toDouble(),
        minY: 0,
        maxY: maxDisfluencies.toDouble(),
      ),
    );
  }

  Widget _buildDisfluencyTypesChart() {
    if (_summary!.totalDisfluencyTypes.isEmpty) {
      return const Center(
        child: AppLabel.secondary('No disfluency data available'),
      );
    }

    final colors = [
      AppColors.accent,
      AppColors.warning,
      AppColors.success,
          AppColors.accentSecondary,
      AppColors.error,
    ];

    return PieChart(
      PieChartData(
        sections: _summary!.totalDisfluencyTypes.entries.map((entry) {
          final index = _summary!.totalDisfluencyTypes.keys.toList().indexOf(entry.key);
          final percentage = (entry.value / _summary!.totalDisfluencies) * 100;

          return PieChartSectionData(
            color: colors[index % colors.length],
            value: entry.value.toDouble(),
            title: '${entry.key}\n${percentage.toStringAsFixed(1)}%',
            radius: 60,
            titleStyle: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }).toList(),
        sectionsSpace: 2,
        centerSpaceRadius: 40,
      ),
    );
  }

  Widget _buildInsights() {
    if (_summary!.insights.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppLabel.primary(
          'Insights & Recommendations',
          size: LabelSize.large,
          fontWeight: FontWeight.bold,
        ),
        const SizedBox(height: AppDimensions.marginMedium),
        ..._summary!.insights.map((insight) => _buildInsightCard(insight)),
      ],
    );
  }

  Widget _buildInsightCard(ImprovementInsight insight) {
    Color cardColor;
    IconData icon;

    switch (insight.type) {
      case 'improvement':
        cardColor = AppColors.success.withOpacity(0.1);
        icon = Icons.trending_up_rounded;
        break;
      case 'consistency':
        cardColor = AppColors.accentSecondary.withOpacity(0.1);
        icon = Icons.schedule_rounded;
        break;
      case 'trend':
        cardColor = AppColors.warning.withOpacity(0.1);
        icon = Icons.analytics_rounded;
        break;
      default:
        cardColor = AppColors.accent.withOpacity(0.1);
        icon = Icons.lightbulb_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppDimensions.marginMedium),
      child: AppCard.basic(
        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
        color: cardColor,
        child: Row(
          children: [
            Icon(icon, color: AppColors.accent, size: 24),
            const SizedBox(width: AppDimensions.marginMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppLabel.primary(
                    insight.title,
                    size: LabelSize.medium,
                    fontWeight: FontWeight.w600,
                  ),
                  const SizedBox(height: AppDimensions.marginXSmall),
                  AppLabel.secondary(
                    insight.description,
                    size: LabelSize.small,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
