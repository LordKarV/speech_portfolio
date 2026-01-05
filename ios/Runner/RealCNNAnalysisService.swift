import Foundation
import AVFoundation
import CoreML
import Accelerate
import UIKit

struct ModelInfo: Codable {
    let inputShape: [Int]
    let outputShape: [Int]
    let classNames: [String]
    let inputType: String
    let outputType: String
}

struct AudioSegment {
    let audioData: [Float]
    let sampleRate: Double
    let startTime: Double
    let endTime: Double
}

struct CNNPrediction {
    let classIndex: Int
    let className: String
    let confidence: Float
    let probabilities: [Float]
}

struct CNNEvent {
    let t0: Double
    let t1: Double
    let type: String
    let confidence: Float
    let probability: Float
    let severity: String
    let source: String
    let modelVersion: String
}

struct CNNAnalysisResult {
    let events: [CNNEvent]
    let summary: CNNAnalysisSummary
    let processingInfo: CNNAnalysisProcessingInfo
}

struct CNNAnalysisSummary {
    let segmentCount: Int
    let hasEvents: Bool
    let error: String?
}

struct CNNAnalysisProcessingInfo {
    let modelVersion: String
    let processingTime: Double
    let error: String?
}

enum CNNAnalysisError: Error {
    case modelNotFound
    case audioFileNotFound
    case audioProcessingFailed
    case modelInferenceFailed
    case invalidAudioFormat
}

class RealCNNAnalysisService {
    private var model: MLModel?
    private let classNames = ["blocks", "prolongations", "repetitions"]
    private let segmentDuration: Double = 5.0
    private let targetSpectrogramSize = (height: 128, width: 128)

    init() throws {
        try loadModel()
    }

    private func loadModel() throws {
        guard let modelPath = Bundle.main.path(forResource: "cnn_model", ofType: "mlmodelc") else {

            guard let h5ModelPath = Bundle.main.path(forResource: "cnn_model", ofType: "h5") else {
                throw CNNAnalysisError.modelNotFound
            }
            print("⚠️ H5 model found but Core ML conversion needed: \(h5ModelPath)")
            throw CNNAnalysisError.modelNotFound
        }

        do {
            model = try MLModel(contentsOf: URL(fileURLWithPath: modelPath))
            print("✅ Core ML model loaded successfully from: \(modelPath)")
        } catch {
            print("❌ Failed to load Core ML model: \(error)")
            throw CNNAnalysisError.modelNotFound
        }
    }

    func analyzeAudioFile(audioFilePath: String) throws -> CNNAnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        print("🎯 Starting REAL CNN analysis for: \(audioFilePath)")

        guard let model = model else {
            throw CNNAnalysisError.modelNotFound
        }

        let audioSegments = try loadAndSegmentAudio(audioFilePath: audioFilePath)
        print("📊 Created \(audioSegments.count) audio segments")

        var events: [CNNEvent] = []

        for (index, segment) in audioSegments.enumerated() {
            do {

                let spectrogram = try generateMelSpectrogram(
                    audioData: segment.audioData,
                    sampleRate: segment.sampleRate
                )

                let prediction = try runCNNInference(
                    spectrogram: spectrogram,
                    model: model
                )

                if prediction.confidence > 0.3 {
                    let event = CNNEvent(
                        t0: segment.startTime * 1000,
                        t1: segment.endTime * 1000,
                        type: prediction.className,
                        confidence: prediction.confidence,
                        probability: prediction.confidence * 100,
                        severity: getSeverity(for: prediction.confidence),
                        source: "coreml_model",
                        modelVersion: "h5_v1"
                    )
                    events.append(event)

                    print("🎯 Detected \(prediction.className) at \(segment.startTime)-\(segment.endTime)s (confidence: \(prediction.confidence))")
                }

            } catch {
                print("⚠️ Error processing segment \(index): \(error)")

            }
        }

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime

        let summary = CNNAnalysisSummary(
            segmentCount: events.count,
            hasEvents: !events.isEmpty,
            error: nil
        )

        let processingInfo = CNNAnalysisProcessingInfo(
            modelVersion: "h5_v1",
            processingTime: processingTime,
            error: nil
        )

        print("🎉 REAL CNN analysis complete: \(events.count) events found in \(processingTime)s")

        return CNNAnalysisResult(
            events: events,
            summary: summary,
            processingInfo: processingInfo
        )
    }

    private func loadAndSegmentAudio(audioFilePath: String) throws -> [AudioSegment] {
        let audioURL = URL(fileURLWithPath: audioFilePath)
        let audioFile = try AVAudioFile(forReading: audioURL)

        let frameCount = UInt32(audioFile.length)
        let sampleRate = audioFile.processingFormat.sampleRate
        let duration = Double(frameCount) / sampleRate

        print("📊 Audio duration: \(duration)s, sample rate: \(sampleRate)Hz")

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
            throw CNNAnalysisError.audioProcessingFailed
        }

        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw CNNAnalysisError.audioProcessingFailed
        }

        let audioData = Array(UnsafeBufferPointer(start: channelData, count: Int(frameCount)))

        var segments: [AudioSegment] = []
        let samplesPerSegment = Int(segmentDuration * sampleRate)

        for i in 0..<Int(ceil(duration / segmentDuration)) {
            let startSample = i * samplesPerSegment
            let endSample = min(startSample + samplesPerSegment, audioData.count)

            let segmentData = Array(audioData[startSample..<endSample])
            let startTime = Double(i) * segmentDuration
            let endTime = min(Double(i + 1) * segmentDuration, duration)

            let segment = AudioSegment(
                audioData: segmentData,
                sampleRate: sampleRate,
                startTime: startTime,
                endTime: endTime
            )
            segments.append(segment)
        }

        return segments
    }

    private func generateMelSpectrogram(audioData: [Float], sampleRate: Double) throws -> [Float] {
        print("🎵 Generating mel spectrogram for \(audioData.count) samples")

        let nFFT = 2048
        let hopLength = 512
        let nMelBins = 128

        let windowedAudio = applyHannWindow(audioData, windowSize: nFFT)

        let stft = computeSTFT(windowedAudio, nFFT: nFFT, hopLength: hopLength)

        let melSpectrogram = convertToMelScale(stft, sampleRate: sampleRate, nMelBins: nMelBins)

        let melSpectrogramDB = convertToDecibels(melSpectrogram)

        let resizedSpectrogram = resizeSpectrogram(melSpectrogramDB, targetSize: targetSpectrogramSize)

        let rgbSpectrogram = convertToRGB(resizedSpectrogram)

        print("✅ Mel spectrogram generated: \(rgbSpectrogram.count) values")

        return rgbSpectrogram
    }

    private func applyHannWindow(_ audio: [Float], windowSize: Int) -> [Float] {
        var windowed = audio

        var window = [Float](repeating: 0, count: windowSize)
        vDSP_hann_window(&window, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))

        vDSP_vmul(audio, 1, window, 1, &windowed, 1, vDSP_Length(min(audio.count, windowSize)))

        return windowed
    }

    private func computeSTFT(_ audio: [Float], nFFT: Int, hopLength: Int) -> [[Float]] {

        let frameCount = (audio.count - nFFT) / hopLength + 1
        var stft: [[Float]] = []

        for i in 0..<frameCount {
            let start = i * hopLength
            let end = min(start + nFFT, audio.count)
            let frame = Array(audio[start..<end])

            var paddedFrame = frame
            if paddedFrame.count < nFFT {
                paddedFrame += Array(repeating: 0, count: nFFT - paddedFrame.count)
            }

            let fftResult = computeFFT(paddedFrame)
            stft.append(fftResult)
        }

        return stft
    }

    private func computeFFT(_ audio: [Float]) -> [Float] {
        let log2n = vDSP_Length(log2(Double(audio.count)))
        let fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2))

        var realParts = audio
        var imaginaryParts = [Float](repeating: 0, count: audio.count)

        var splitComplex = DSPSplitComplex(realp: &realParts, imagp: &imaginaryParts)

        vDSP_fft_zrip(fftSetup!, &splitComplex, 1, log2n, Int32(FFT_FORWARD))

        var magnitudes = [Float](repeating: 0, count: audio.count / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(audio.count / 2))

        vDSP_destroy_fftsetup(fftSetup)

        return magnitudes
    }

    private func convertToMelScale(_ stft: [[Float]], sampleRate: Double, nMelBins: Int) -> [[Float]] {

        var melSpectrogram: [[Float]] = []

        for frame in stft {

            let melFrame = downsampleToMelBins(frame, nMelBins: nMelBins)
            melSpectrogram.append(melFrame)
        }

        return melSpectrogram
    }

    private func downsampleToMelBins(_ frame: [Float], nMelBins: Int) -> [Float] {
        let binSize = frame.count / nMelBins
        var melFrame: [Float] = []

        for i in 0..<nMelBins {
            let start = i * binSize
            let end = min(start + binSize, frame.count)
            let binValues = Array(frame[start..<end])

            let average = binValues.reduce(0, +) / Float(binValues.count)
            melFrame.append(average)
        }

        return melFrame
    }

    private func convertToDecibels(_ spectrogram: [[Float]]) -> [[Float]] {
        var dbSpectrogram: [[Float]] = []

        for frame in spectrogram {
            var dbFrame = frame

            vDSP_vdbcon(frame, 1, &dbFrame, 1, vDSP_Length(frame.count), 1)
            dbSpectrogram.append(dbFrame)
        }

        return dbSpectrogram
    }

    private func resizeSpectrogram(_ spectrogram: [[Float]], targetSize: (height: Int, width: Int)) -> [[Float]] {

        let originalHeight = spectrogram.count
        let originalWidth = spectrogram.first?.count ?? 0

        var resized: [[Float]] = []

        for y in 0..<targetSize.height {
            let sourceY = Int(Double(y) * Double(originalHeight) / Double(targetSize.height))
            var row: [Float] = []

            for x in 0..<targetSize.width {
                let sourceX = Int(Double(x) * Double(originalWidth) / Double(targetSize.width))
                let value = spectrogram[min(sourceY, originalHeight - 1)][min(sourceX, originalWidth - 1)]
                row.append(value)
            }

            resized.append(row)
        }

        return resized
    }

    private func convertToRGB(_ spectrogram: [[Float]]) -> [Float] {

        var rgbData: [Float] = []

        for row in spectrogram {
            for value in row {

                let normalizedValue = (value + 80) / 80.0
                let clampedValue = max(0, min(1, normalizedValue))

                rgbData.append(clampedValue)
                rgbData.append(clampedValue)
                rgbData.append(clampedValue)
            }
        }

        return rgbData
    }

    private func runCNNInference(spectrogram: [Float], model: MLModel) throws -> CNNPrediction {
        print("🤖 Running REAL CNN inference on \(spectrogram.count) values")

        let inputArray = try MLMultiArray(shape: [1, 128, 128, 3], dataType: .float32)

        for i in 0..<spectrogram.count {
            inputArray[i] = NSNumber(value: spectrogram[i])
        }

        let input = CNNModelInput(input: inputArray)

        let output = try model.prediction(from: input)

        guard let outputArray = output.featureValue(for: "output")?.multiArrayValue else {
            throw CNNAnalysisError.modelInferenceFailed
        }

        var probabilities: [Float] = []
        for i in 0..<classNames.count {
            probabilities.append(Float(truncating: outputArray[i]))
        }

        let maxIndex = probabilities.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let confidence = probabilities[maxIndex]
        let className = classNames[maxIndex]

        print("🎯 CNN prediction: \(className) (confidence: \(confidence))")

        return CNNPrediction(
            classIndex: maxIndex,
            className: className,
            confidence: confidence,
            probabilities: probabilities
        )
    }

    private func getSeverity(for confidence: Float) -> String {
        if confidence >= 0.8 {
            return "high"
        } else if confidence >= 0.6 {
            return "medium"
        } else {
            return "low"
        }
    }
}

struct CNNModelInput: MLFeatureProvider {
    let input: MLMultiArray

    var featureNames: Set<String> {
        return ["input"]
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "input" {
            return MLFeatureValue(multiArray: input)
        }
        return nil
    }
}
