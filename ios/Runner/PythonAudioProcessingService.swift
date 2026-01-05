import AVFoundation
import Flutter
import Foundation
import UIKit

class PythonAudioProcessingService {
    static let shared = PythonAudioProcessingService()

    private init() {
        print("🎵 PythonAudioProcessingService: Initializing singleton instance")
    }

    func setupChannel(_ channel: FlutterMethodChannel) {
        print("📡 PythonAudioProcessingService: Setting up method channel handler")

        channel.setMethodCallHandler { [weak self] (call, result) in
            print("📞 PythonAudioProcessingService: Received method call: \(call.method)")
            self?.handleMethodCall(call: call, result: result)
        }

        print("✅ PythonAudioProcessingService: Audio processing channel setup complete")
    }

    func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("🎯 PythonAudioProcessingService: Processing method: \(call.method)")

        switch call.method {
        case "processAudioStreams":
            print("🔊 PythonAudioProcessingService: Handling processAudioStreams request")
            processAudioStreams(arguments: call.arguments, result: result)
        default:
            print("❌ PythonAudioProcessingService: Unknown method: \(call.method)")
            result(FlutterMethodNotImplemented)
        }
    }

    private func processAudioStreams(arguments: Any?, result: @escaping FlutterResult) {
        print("🔍 PythonAudioProcessingService: Processing audio streams request")
        print("📝 PythonAudioProcessingService: Raw arguments received: \(String(describing: arguments))")

        guard let args = arguments as? [String: Any] else {
            print("❌ PythonAudioProcessingService: Failed to cast arguments to dictionary")
            result(
                FlutterError(
                    code: "INVALID_ARGUMENTS", 
                    message: "Arguments not a dictionary", 
                    details: nil
                )
            )
            return
        }

        print("📋 PythonAudioProcessingService: Arguments keys: \(args.keys)")

        guard let audioStreams = args["audioStreams"] as? [FlutterStandardTypedData] else {
            print("❌ PythonAudioProcessingService: Failed to extract audioStreams from arguments")
            print("📋 PythonAudioProcessingService: audioStreams type: \(type(of: args["audioStreams"]))")
            result(
                FlutterError(
                    code: "INVALID_ARGUMENTS", 
                    message: "Invalid audio streams", 
                    details: nil
                )
            )
            return
        }

        print("🔊 PythonAudioProcessingService: Successfully extracted \(audioStreams.count) audio streams")

        DispatchQueue.global(qos: .userInitiated).async {
            print("🔄 PythonAudioProcessingService: Starting background audio processing")
            var analysisResults: [SoundAnalysisResult] = []

            for (index, audioData) in audioStreams.enumerated() {
                print("🎵 PythonAudioProcessingService: Processing stream \(index) with \(audioData.data.count) bytes")
                let analysisResult = self.analyzeAudio(data: audioData.data, fileIndex: index)
                analysisResults.append(analysisResult)
                print("✅ PythonAudioProcessingService: Completed analysis for stream \(index)")
            }

            print("📊 PythonAudioProcessingService: Total analysis results: \(analysisResults.count)")

            DispatchQueue.main.async {
                let resultArray = analysisResults.map { $0.toDictionary() }
                print("📤 PythonAudioProcessingService: Sending back \(resultArray.count) results to Flutter")
                print("📤 PythonAudioProcessingService: Results preview: \(resultArray)")
                result(resultArray)
            }
        }
    }

    private func analyzeAudio(data: Data, fileIndex: Int) -> SoundAnalysisResult {
        print("🔍 PythonAudioProcessingService: Analyzing audio segment \(fileIndex): \(data.count) bytes")

        print("⏳ PythonAudioProcessingService: Simulating audio analysis processing time")
        Thread.sleep(forTimeInterval: 0.1)

        let success = Double.random(in: 0...1) > 0.1
        print("🎲 PythonAudioProcessingService: Analysis success simulation: \(success)")

        let probableMatches: [String]
        if success {
            print("✅ PythonAudioProcessingService: Generating probable matches for successful analysis")
            probableMatches = generateProbableMatches()
        } else {
            print("❌ PythonAudioProcessingService: No matches for failed analysis")
            probableMatches = []
        }

        print("✅ PythonAudioProcessingService: Analysis complete for segment \(fileIndex): success=\(success), matches=\(probableMatches.count)")

        return SoundAnalysisResult(
            fileIndex: fileIndex,
            success: success,
            probableMatches: probableMatches
        )
    }

    private func generateProbableMatches() -> [String] {
        print("🎯 PythonAudioProcessingService: Generating probable speech pattern matches")

        let allMatches = [
          "sound repetition detected, probability 80",
            "syllable repetition found, probability 50",
            "word repetition identified, probability 75",
            "sound prolongation detected, probability 30",
            "silent block observed, probability 90",
            "prolongation detected, probability 85",
            "repetition pattern found, probability 70",
            "block behavior identified, probability 60",
        ]

        let matchCount = Int.random(in: 2...5)
        let selectedMatches = allMatches.shuffled().prefix(matchCount)

        print("🔢 PythonAudioProcessingService: Generated \(matchCount) probable matches")

        return Array(selectedMatches)
    }
}

struct SoundAnalysisResult {
    let fileIndex: Int
    let success: Bool
    let probableMatches: [String]

    func toDictionary() -> [String: Any] {
        return [
            "fileIndex": fileIndex,
            "success": success,
            "probableMatches": probableMatches,
        ]
    }
}
