class AudioConfig {

  static const String _currentPreset = 'balanced';

  static const Map<String, Map<String, dynamic>> _presets = {
     'performance': {
      'fftSize': 1536,
      'hopSize': 256,
      'numBands': 96,
      'description': 'Fast processing with good detail'
    },
    'balanced': {
      'fftSize': 2048,
      'hopSize': 256,
      'numBands': 128,
      'description': 'Optimal quality/performance balance'
    },
    'high_quality': {
      'fftSize': 2048,
      'hopSize': 128,
      'numBands': 160,
      'description': 'Superior quality for detailed analysis'
    },
  };

  static const int delayPlayback = 300;
  static const int sampleRate = 44100;
  static const int channels = 1;
  static const double maxFreq = 8000.0;
  static const int historySize = 300;
  static const int timingHistorySize = 50;

  static int get fftSize => _presets[_currentPreset]!['fftSize'] as int;
  static int get hopSize => _presets[_currentPreset]!['hopSize'] as int;
  static int get numBands => _presets[_currentPreset]!['numBands'] as int;
  static int get bufferSize => fftSize;

  static double get timePerColumn => hopSize / sampleRate;
  static double get overlapPercentage => ((fftSize - hopSize) / fftSize * 100);
  static double get updateRateMs => (hopSize / sampleRate * 1000);
  static double get frequencyResolution => sampleRate / fftSize;

  static String get currentPreset => _currentPreset;
  static String get currentDescription => _presets[_currentPreset]!['description'] as String;

  static Map<String, dynamic> getCurrentConfig() {
    return {
      'preset': currentPreset,
      'description': currentDescription,
      'sampleRate': sampleRate,
      'fftSize': fftSize,
      'hopSize': hopSize,
      'numBands': numBands,
      'maxFreq': maxFreq,
      'bufferSize': bufferSize,
      'overlapPercentage': '${overlapPercentage.toStringAsFixed(1)}%',
      'updateRateMs': '${updateRateMs.toStringAsFixed(1)}ms',
      'frequencyResolution': '${frequencyResolution.toStringAsFixed(1)}Hz',
      'timePerColumn': '${(timePerColumn * 1000).toStringAsFixed(2)}ms',
    };
  }
}