import Foundation
import ServiceManagement

// Açılışta başlatma. macOS'un Giriş Öğeleri listesine eklenir; Sistem Ayarları >
// Genel > Giriş Öğeleri'nden de kapatılabilir.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var statusText: String {
        switch SMAppService.mainApp.status {
        case .enabled: "açık"
        case .notRegistered: "kapalı"
        case .requiresApproval: "onay bekliyor (Sistem Ayarları > Genel > Giriş Öğeleri)"
        case .notFound: "bulunamadı"
        @unknown default: "bilinmiyor"
        }
    }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    // `IslemciIzleyici --login-item on|off|status`
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--login-item") else { return }
        let action = i + 1 < args.count ? args[i + 1] : "status"
        do {
            switch action {
            case "on": try set(true)
            case "off": try set(false)
            default: break
            }
            print("Açılışta başlat: \(statusText)")
            exit(0)
        } catch {
            print("Açılışta başlat değiştirilemedi: \(error.localizedDescription)")
            exit(1)
        }
    }
}
