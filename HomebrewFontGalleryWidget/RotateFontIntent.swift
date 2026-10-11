import AppIntents
import Foundation

/// Counts the presses of the back and forward buttons, separately for each size of widget.
enum WidgetPosition {
    private static func key(_ size: String) -> String { "presses.\(size)" }

    static func presses(for size: String) -> Int {
        UserDefaults.standard.integer(forKey: key(size))
    }

    static func move(_ size: String, by step: Int) {
        UserDefaults.standard.set(presses(for: size) + step, forKey: key(size))
    }
}

/// The back and forward buttons. WidgetKit redraws the widget when this has run.
struct RotateFontIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Another Font"
    static var isDiscoverable = false

    @Parameter(title: "Size") var size: String
    @Parameter(title: "Step") var step: Int

    init() {}

    init(size: String, step: Int) {
        self.size = size
        self.step = step
    }

    func perform() async throws -> some IntentResult {
        WidgetPosition.move(size, by: step)
        return .result()
    }
}
