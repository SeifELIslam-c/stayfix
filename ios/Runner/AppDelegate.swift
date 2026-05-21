import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let apiKey = loadGoogleMapsApiKey() {
      GMSServices.provideAPIKey(apiKey)
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func loadGoogleMapsApiKey() -> String? {
    let candidatePaths = [
      Bundle.main.path(forResource: ".env", ofType: nil),
      Bundle.main.path(forResource: "flutter_assets/.env", ofType: nil),
      Bundle.main.resourcePath.map { "\($0)/flutter_assets/.env" },
    ]

    for path in candidatePaths.compactMap({ $0 }) {
      if let raw = try? String(contentsOfFile: path, encoding: .utf8) {
        for line in raw.components(separatedBy: .newlines) {
          let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
          if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
          let separatorIndex = trimmed.firstIndex(of: "=") ?? trimmed.firstIndex(of: ":")
          guard let separator = separatorIndex else { continue }
          let key = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
          let value = trimmed[trimmed.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
          if key == "GOOGLE_MAPS_API_KEY", !value.isEmpty {
            return value
          }
        }
      }
    }

    return nil
  }
}
