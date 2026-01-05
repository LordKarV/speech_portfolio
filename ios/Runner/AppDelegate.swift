import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

    private lazy var coreMLClassifier: CoreMLStutteringClassifier = {
        return CoreMLStutteringClassifier()
    }()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        GeneratedPluginRegistrant.register(with: self)

        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let controller = self.window?.rootViewController as? FlutterViewController else {
                return
            }

            let coreMLChannel = FlutterMethodChannel(
                name: "coreml_stuttering_classifier",
                binaryMessenger: controller.binaryMessenger
            )

            coreMLChannel.setMethodCallHandler { [weak self] (call, result) in
                self?.handleCoreMLMethodCall(call: call, result: result)
            }

            _ = self.coreMLClassifier.loadModel()
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func handleCoreMLMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            let loaded = coreMLClassifier.loadModel()
            if !loaded {

                result(FlutterError(
                    code: "MODEL_LOAD_FAILED",
                    message: "Failed to load Core ML model. Check Xcode console for details.",
                    details: nil
                ))
            } else {
                result(true)
            }

        case "analyzeAudioFile":
            guard let args = call.arguments as? [String: Any],
                  let audioFilePath = args["audioFilePath"] as? String else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "audioFilePath is required",
                    details: nil
                ))
                return
            }

            coreMLClassifier.analyzeAudioFile(audioFilePath: audioFilePath) { analysisResult in
                if let resultDict = analysisResult {
                    result(resultDict)
                } else {
                    result(FlutterError(
                        code: "ANALYSIS_FAILED",
                        message: "Core ML analysis failed",
                        details: nil
                    ))
                }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}