import Foundation
import CoreML
import AVFoundation
import Accelerate

@objc class CoreMLStutteringClassifier: NSObject {
    private var model: MLModel?
    private let classNames = ["repetitions", "fluent"]

    private let sampleRate: Double = 16000.0
    private let nMels: Int = 80
    private let nFFT: Int = 2048
    private let hopLength: Int = 512
    private let targetFrames: Int = 128
    private let fmin: Double = 0.0
    private let fmax: Double = 8000.0

    private let windowDuration: Double = 3.0
    private let hopDuration: Double = 1.0

    @objc func loadModel() -> Bool {
        print("🔍 CoreML: Attempting to load model...")

        if let compiledModelURL = Bundle.main.url(forResource: "repetitions_fluent", withExtension: "mlmodelc") {
            print("✅ CoreML: Found compiled model at: \(compiledModelURL.path)")
            do {
                model = try MLModel(contentsOf: compiledModelURL)
                print("✅ CoreML: Model loaded successfully from compiled version!")
                print("   Model description: \(model?.modelDescription.description ?? "N/A")")
                return true
            } catch {
                print("❌ CoreML: Failed to load compiled model: \(error)")
                print("   Error details: \(error.localizedDescription)")
            }
        }

        guard let modelURL = Bundle.main.url(forResource: "repetitions_fluent", withExtension: "mlmodel") else {
            print("❌ CoreML: Neither compiled (.mlmodelc) nor source (.mlmodel) model found in bundle")
            print("   Bundle path: \(Bundle.main.bundlePath)")

            if let resourcePath = Bundle.main.resourcePath {
                print("   Bundle resources: \(try? FileManager.default.contentsOfDirectory(atPath: resourcePath) ?? [])")
            }
            return false
        }

        print("✅ CoreML: Found source model file at: \(modelURL.path)")

        do {

            print("🔄 CoreML: Compiling model from source...")
            let compiledModelURL = try MLModel.compileModel(at: modelURL)
            print("✅ CoreML: Model compiled to: \(compiledModelURL.path)")

            model = try MLModel(contentsOf: compiledModelURL)
            print("✅ CoreML: Model loaded successfully!")
            print("   Model description: \(model?.modelDescription.description ?? "N/A")")
            return true
        } catch {
            print("❌ CoreML: Failed to load model: \(error)")
            print("   Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("   Error domain: \(nsError.domain)")
                print("   Error code: \(nsError.code)")
                print("   User info: \(nsError.userInfo)")
            }
            return false
        }
    }

    @objc func analyzeAudioFile(audioFilePath: String, result: @escaping (NSDictionary?) -> Void) {
        guard let model = model else {
            print("❌ CoreML: Model not loaded")
            result(nil)
            return
        }

        print("🎯 CoreML: Starting analysis for: \(audioFilePath)")
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let audioURL = URL(string: audioFilePath) ?? URL(fileURLWithPath: audioFilePath) as URL? else {
            print("❌ CoreML: Invalid audio file path")
            result(nil)
            return
        }

        do {

            let audioFile = try AVAudioFile(forReading: audioURL)
            let frameCount = UInt32(audioFile.length)
            let fileSampleRate = audioFile.processingFormat.sampleRate
            let duration = Double(frameCount) / fileSampleRate

            print("📊 CoreML: Audio duration: \(duration)s, sample rate: \(fileSampleRate)Hz")

            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
                print("❌ CoreML: Failed to create audio buffer")
                result(nil)
                return
            }

            try audioFile.read(into: buffer)

            guard let channelData = buffer.floatChannelData?[0] else {
                print("❌ CoreML: Failed to get channel data")
                result(nil)
                return
            }

            var audioData = Array(UnsafeBufferPointer(start: channelData, count: Int(frameCount)))

            if fileSampleRate != sampleRate {
                audioData = resampleAudio(audioData, fromRate: fileSampleRate, toRate: sampleRate)
                print("🔄 CoreML: Resampled from \(fileSampleRate)Hz to \(sampleRate)Hz")
            }

            normalizeAudio(&audioData)

            let events = performSlidingWindowDetection(audioData: audioData, model: model, duration: duration)

            let processingTime = CFAbsoluteTimeGetCurrent() - startTime

            let eventsArray = events.map { event -> NSDictionary in
                return [
                    "type": event["type"] as! String,
                    "confidence": event["confidence"] as! Double,
                    "probability": Int((event["confidence"] as! Double) * 100),
                    "t0": event["t0"] as! Int,
                    "t1": event["t1"] as! Int,
                    "seconds": (event["t0"] as! Int) / 1000,
                    "severity": event["severity"] as! String,
                    "source": "coreml_model",
                    "model_version": "repetitions_fluent_v1"
                ]
            }

            let summary: NSDictionary = [
                "segmentCount": events.count,
                "hasEvents": !events.isEmpty,
                "error": NSNull()
            ]

            let processingInfo: NSDictionary = [
                "model_path": "repetitions_fluent.mlmodel",
                "input_file": audioFilePath,
                "processing_time": processingTime,
                "errors": []
            ]

            let resultDict: NSDictionary = [
                "events": eventsArray,
                "summary": summary,
                "processing_info": processingInfo
            ]

            print("✅ CoreML: Analysis complete - \(events.count) events found in \(processingTime)s")
            result(resultDict)

        } catch {
            print("❌ CoreML: Error processing audio: \(error)")
            result(nil)
        }
    }

    private func performSlidingWindowDetection(audioData: [Float], model: MLModel, duration: Double) -> [[String: Any]] {
        var events: [[String: Any]] = []
        let windowSamples = Int(windowDuration * sampleRate)
        let hopSamples = Int(hopDuration * sampleRate)

        var windowPredictions: [[String: Any]] = []

        var startIdx = 0
        while startIdx + windowSamples <= audioData.count {
            let endIdx = startIdx + windowSamples
            let windowAudio = Array(audioData[startIdx..<endIdx])
            let windowStartTime = Double(startIdx) / sampleRate
            let windowEndTime = Double(endIdx) / sampleRate

            guard let spectrogram = extractLogMelSpectrogram(audioData: windowAudio) else {
                startIdx += hopSamples
                continue
            }

            if let prediction = runInference(spectrogram: spectrogram, model: model) {
                let windowPred: [String: Any] = [
                    "start_time": windowStartTime,
                    "end_time": windowEndTime,
                    "class": prediction["class"] as! String,
                    "confidence": prediction["confidence"] as! Double,
                    "probabilities": prediction["probabilities"] as! [String: Double]
                ]
                windowPredictions.append(windowPred)
            }

            startIdx += hopSamples
        }

        events = postProcessPredictions(windowPredictions, minDuration: 0.5, threshold: 0.30)

        return events
    }

    private func extractLogMelSpectrogram(audioData: [Float]) -> [[Float]]? {

        var normalizedAudio = audioData
        normalizeAudio(&normalizedAudio)

        guard let melSpec = computeMelSpectrogram(audioData: normalizedAudio) else {
            return nil
        }

        var logMel = melSpec.map { row in
            row.map { max($0, 1e-10) }.map { log10($0) }
        }

        if let maxVal = logMel.flatMap({ $0 }).max() {
            logMel = logMel.map { row in
                row.map { ($0 - maxVal) * 20.0 }
            }
        }

        var finalMel = logMel
        if finalMel.first?.count ?? 0 > targetFrames {
            finalMel = finalMel.map { Array($0.prefix(targetFrames)) }
        } else if finalMel.first?.count ?? 0 < targetFrames {
            let padWidth = targetFrames - (finalMel.first?.count ?? 0)
            finalMel = finalMel.map { row in
                row + Array(repeating: -80.0, count: padWidth)
            }
        }

        return finalMel
    }

    private func computeMelSpectrogram(audioData: [Float]) -> [[Float]]? {

        let frameCount = (audioData.count - nFFT) / hopLength + 1
        var melSpectrogram: [[Float]] = []

        let melFilters = createMelFilterBank()

        for frameIdx in 0..<frameCount {
            let start = frameIdx * hopLength
            let end = min(start + nFFT, audioData.count)

            var frame = Array(audioData[start..<end])

            if frame.count < nFFT {
                frame += Array(repeating: 0.0, count: nFFT - frame.count)
            }

            applyHannWindow(&frame)

            guard let fftMagnitude = computeFFTMagnitude(frame) else {
                continue
            }

            var melFrame = [Float](repeating: 0.0, count: nMels)
            for (melIdx, filter) in melFilters.enumerated() {
                var sum: Float = 0.0
                for (freqIdx, weight) in filter.enumerated() {
                    if freqIdx < fftMagnitude.count {
                        sum += fftMagnitude[freqIdx] * weight
                    }
                }
                melFrame[melIdx] = sum
            }

            melSpectrogram.append(melFrame)
        }

        return melSpectrogram.isEmpty ? nil : melSpectrogram
    }

    private func createMelFilterBank() -> [[Float]] {

        let nyquist = sampleRate / 2.0
        let melMax = 2595.0 * log10(1.0 + (fmax / 700.0))
        let melMin = 2595.0 * log10(1.0 + (fmin / 700.0))

        var filters: [[Float]] = []
        let nFFTBins = nFFT / 2 + 1

        for i in 0..<nMels {
            let melCenter = melMin + (melMax - melMin) * Double(i) / Double(nMels - 1)
            let freqCenter = 700.0 * (pow(10.0, melCenter / 2595.0) - 1.0)
            let binCenter = Int(freqCenter / nyquist * Double(nFFTBins))

            var filter = [Float](repeating: 0.0, count: nFFTBins)

            let bandwidth = Int(Double(nFFTBins) / Double(nMels) * 2.0)
            for j in max(0, binCenter - bandwidth)..<min(nFFTBins, binCenter + bandwidth) {
                let distance = abs(j - binCenter)
                if distance < bandwidth {
                    filter[j] = Float(1.0 - Double(distance) / Double(bandwidth))
                }
            }

            filters.append(filter)
        }

        return filters
    }

    private func applyHannWindow(_ frame: inout [Float]) {
        let windowSize = frame.count
        for i in 0..<windowSize {
            let windowValue = 0.5 * (1.0 - cos(2.0 * Double.pi * Double(i) / Double(windowSize - 1)))
            frame[i] *= Float(windowValue)
        }
    }

    private func computeFFTMagnitude(_ frame: [Float]) -> [Float]? {
        let count = frame.count
        let log2n = vDSP_Length(log2(Double(count)))

        guard let fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2)) else {
            return nil
        }

        var realParts = frame
        var imaginaryParts = [Float](repeating: 0.0, count: count)
        var splitComplex = DSPSplitComplex(realp: &realParts, imagp: &imaginaryParts)

        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, Int32(FFT_FORWARD))

        var magnitudes = [Float](repeating: 0.0, count: count / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(count / 2))

        vDSP_destroy_fftsetup(fftSetup)

        return magnitudes
    }

    private func runInference(spectrogram: [[Float]], model: MLModel) -> [String: Any]? {

        guard let inputArray = try? MLMultiArray(shape: [1, 1, 80, 128], dataType: .float32) else {
            print("❌ CoreML: Failed to create input array")
            return nil
        }

        var idx = 0
        for mel in 0..<80 {
            for time in 0..<128 {
                let value = spectrogram[mel][time]
                inputArray[idx] = NSNumber(value: value)
                idx += 1
            }
        }

        do {
            let inputFeature = MLFeatureValue(multiArray: inputArray)
            let inputProvider = try MLDictionaryFeatureProvider(dictionary: ["spectrogram": inputFeature])

            let prediction = try model.prediction(from: inputProvider)

            guard let outputFeature = prediction.featureValue(for: "classProbabilities"),
                  let outputArray = outputFeature.multiArrayValue else {
                print("❌ CoreML: Failed to get output")
                return nil
            }

            let repetitionProb = Double(truncating: outputArray[0])
            let fluentProb = Double(truncating: outputArray[1])

            let predictedClass = repetitionProb > fluentProb ? "repetitions" : "fluent"
            let confidence = max(repetitionProb, fluentProb)

            return [
                "class": predictedClass,
                "confidence": confidence,
                "probabilities": [
                    "repetitions": repetitionProb,
                    "fluent": fluentProb
                ] as [String: Double]
            ]
        } catch {
            print("❌ CoreML: Prediction failed: \(error)")
            return nil
        }
    }

    private func postProcessPredictions(_ predictions: [[String: Any]], minDuration: Double, threshold: Double) -> [[String: Any]] {
        var events: [[String: Any]] = []
        var currentEvent: [String: Any]?

        for pred in predictions {
            let className = pred["class"] as! String
            let confidence = pred["confidence"] as! Double
            let startTime = pred["start_time"] as! Double
            let endTime = pred["end_time"] as! Double

            if className == "fluent" {
                if let event = currentEvent {
                    let duration = (event["end_time"] as! Double) - (event["start_time"] as! Double)
                    if duration >= minDuration {
                        events.append(event)
                    }
                }
                currentEvent = nil
                continue
            }

            if confidence < threshold {
                if let event = currentEvent {
                    let duration = (event["end_time"] as! Double) - (event["start_time"] as! Double)
                    if duration >= minDuration {
                        events.append(event)
                    }
                }
                currentEvent = nil
                continue
            }

            let probs = pred["probabilities"] as! [String: Double]
            let fluentProb = probs["fluent"] ?? 0.0
            let repetitionProb = probs["repetitions"] ?? 0.0

            if fluentProb > 0.75 && repetitionProb < 0.4 {

                continue
            }

            if repetitionProb < fluentProb + 0.05 {

                continue
            }

            if let event = currentEvent, event["class"] as! String == className {

                currentEvent!["end_time"] = endTime
                currentEvent!["confidence"] = max(event["confidence"] as! Double, confidence)
            } else {

                if let event = currentEvent {
                    let duration = (event["end_time"] as! Double) - (event["start_time"] as! Double)
                    if duration >= minDuration {
                        events.append(event)
                    }
                }

                currentEvent = [
                    "class": className,
                    "start_time": startTime,
                    "end_time": endTime,
                    "confidence": confidence
                ]
            }
        }

        if let event = currentEvent {
            let duration = (event["end_time"] as! Double) - (event["start_time"] as! Double)
            if duration >= minDuration {
                events.append(event)
            }
        }

        return events.map { event -> [String: Any] in
            let startTime = event["start_time"] as! Double
            let endTime = event["end_time"] as! Double
            let confidence = event["confidence"] as! Double

            return [
                "type": event["class"] as! String,
                "t0": Int(startTime * 1000),
                "t1": Int(endTime * 1000),
                "confidence": confidence,
                "severity": confidence > 0.7 ? "high" : (confidence > 0.5 ? "medium" : "low")
            ]
        }
    }

    private func resampleAudio(_ audio: [Float], fromRate: Double, toRate: Double) -> [Float] {

        let ratio = toRate / fromRate
        let newLength = Int(Double(audio.count) * ratio)
        var resampled = [Float](repeating: 0.0, count: newLength)

        for i in 0..<newLength {
            let srcIdx = Double(i) / ratio
            let idx1 = Int(srcIdx)
            let idx2 = min(idx1 + 1, audio.count - 1)
            let frac = srcIdx - Double(idx1)
            resampled[i] = audio[idx1] * Float(1.0 - frac) + audio[idx2] * Float(frac)
        }

        return resampled
    }

    private func normalizeAudio(_ audio: inout [Float]) {
        guard let maxVal = audio.map({ abs($0) }).max(), maxVal > 0 else {
            return
        }
        let scale = 0.95 / maxVal
        audio = audio.map { $0 * scale }
    }
}
