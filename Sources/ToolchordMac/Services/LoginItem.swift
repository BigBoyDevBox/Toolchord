import Foundation
import ServiceManagement

/// Opt-in launch at login through `SMAppService.mainApp`. The status is read
/// from the system each time rather than stored, because the user can change
/// it in System Settings › General › Login Items.
@MainActor
enum LoginItem {
    enum State: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable(String)
    }

    static var state: State {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return .unavailable("Available when Toolchord runs as an app bundle.")
        }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    /// Returns an error message when the change could not be made.
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "macOS couldn’t change the login item: \(error.localizedDescription)"
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
