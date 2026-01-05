# Speech Analysis App

A Flutter-based speech pathology analysis app that uses CNN models to detect speech disfluencies including blocks, prolongations, and repetitions.

## Features

- **Real-time Audio Recording**: Record speech samples with high-quality audio capture
- **CNN Analysis**: Advanced deep learning model for speech disfluency detection
- **H5 Model Integration**: Uses Keras H5 models for accurate speech analysis
- **Cross-platform**: Works on iOS and Android
- **Firebase Integration**: Cloud storage and user authentication
- **Analytics Dashboard**: Track progress and view analysis results

## Model Architecture

The app uses a CNN model trained on speech disfluency data to classify audio segments into:
- **Blocks**: Sudden stops or pauses in speech
- **Prolongations**: Extended sounds or syllables
- **Repetitions**: Repeated sounds, syllables, or words

### Model Format
- **Primary**: Keras H5 (.h5) format for maximum accuracy
- **Fallback**: TensorFlow Lite (.tflite) format for compatibility
- **Input**: 128x128x3 RGB mel spectrograms
- **Output**: 3-class classification with confidence scores

## Technical Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Python with TensorFlow/Keras
- **Model**: CNN with H5 format
- **Audio Processing**: Librosa for mel spectrogram generation
- **Cloud**: Firebase (Authentication, Storage, Firestore)
- **Platform**: iOS (with Python backend integration)

## Setup Instructions

### Prerequisites
- Flutter SDK
- Python 3.x with required packages
- iOS development environment (Xcode)
- Firebase project setup

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd speech_app
   ```

2. **Install Flutter dependencies**
   ```bash
   flutter pub get
   ```

3. **Install Python dependencies**
   ```bash
   cd python_services
   pip install -r requirements.txt
   ```

4. **Setup iOS H5 integration**
   ```bash
   ./setup_ios_h5.sh
   cd ios && pod install
   ```

5. **Configure Firebase**
   - Add your `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Update Firebase configuration in `lib/firebase_options.dart`

6. **Run the app**
   ```bash
   flutter run
   ```

## Project Structure

```
speech_app/
├── lib/                    # Flutter app source code
│   ├── components/         # Reusable UI components
│   ├── screens/           # App screens
│   ├── services/          # Business logic services
│   └── theme/             # App theming
├── python_services/       # Python backend services
│   ├── models/           # CNN models (H5 and TFLite)
│   ├── audio_processor.py # Audio processing pipeline
│   └── cnn_analysis_service.py # CNN analysis service
├── ios/                   # iOS-specific code
│   └── Runner/           # iOS app bundle with Python services
└── android/              # Android-specific code
```

## Key Files

- **H5 Integration Guide**: `H5_INTEGRATION_GUIDE.md`
- **CNN Analysis Service**: `lib/services/cnn_analysis_service.dart`
- **Python Backend**: `python_services/cnn_analysis_service.py`
- **iOS Integration**: `ios/Runner/PythonCNNAnalysisService.swift`

## Acknowledgments

Special thanks to [Eduardo](https://github.com/eduardo92) for his help on the spectrogram display system and native iOS audio processing integration.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
