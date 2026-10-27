import Foundation

// Bilinen süreçlerin kısa Türkçe açıklamaları. İlk eşleşen kural kazanır.
enum ProcessCatalog {
    private enum Match { case exact, prefix, contains }

    private static let rules: [(String, Match, String)] = [
        ("ffmpeg", .prefix, "video kodlama / render"),
        ("ffprobe", .prefix, "video bilgisi okuma"),
        ("python", .prefix, "Python betiği"),
        ("node", .exact, "Node.js betiği"),
        ("next-server", .prefix, "Next.js geliştirme sunucusu"),
        ("mds_stores", .exact, "Spotlight indeksleme"),
        ("mdworker", .prefix, "Spotlight dosya tarama"),
        ("mds", .exact, "Spotlight yöneticisi"),
        ("spotlightknowledged", .prefix, "Spotlight bilgi indeksleme"),
        ("corespotlightd", .exact, "Spotlight"),
        ("windowserver", .exact, "ekran çizimi"),
        ("kernel_task", .exact, "çekirdek; ısınınca CPU'yu frenler"),
        ("brave browser helper (renderer)", .exact, "tarayıcı sekmesi"),
        ("brave browser helper (gpu)", .exact, "tarayıcı grafik işlemi"),
        ("brave browser helper", .prefix, "tarayıcı yardımcı süreci"),
        ("brave browser", .exact, "Brave tarayıcı"),
        ("google chrome helper (renderer)", .exact, "tarayıcı sekmesi"),
        ("google chrome helper", .prefix, "tarayıcı yardımcı süreci"),
        ("safari", .exact, "Safari tarayıcı"),
        ("com.apple.webkit", .prefix, "web içeriği (Safari vb.)"),
        ("whatsapp", .prefix, "WhatsApp mesajlaşma"),
        ("claude helper", .prefix, "Claude uygulaması"),
        ("claude", .exact, "Claude"),
        ("code helper", .prefix, "VS Code"),
        ("com.docker", .prefix, "Docker"),
        ("docker", .prefix, "Docker"),
        ("com.apple.virtualization.virtualmachine", .exact, "sanal makine (Docker vb.)"),
        ("coreaudiod", .exact, "ses sistemi"),
        ("photoanalysisd", .exact, "Fotoğraflar analizi"),
        ("mediaanalysisd", .exact, "medya analizi"),
        ("backupd", .exact, "Time Machine yedekleme"),
        ("bird", .exact, "iCloud Drive eşitleme"),
        ("cloudd", .exact, "iCloud eşitleme"),
        ("fileproviderd", .exact, "bulut dosya eşitleme"),
        ("softwareupdated", .exact, "yazılım güncelleme"),
        ("nsurlsessiond", .exact, "arka plan indirme"),
        ("fseventsd", .exact, "dosya değişikliği takibi"),
        ("xprotect", .prefix, "zararlı yazılım taraması"),
        ("syspolicyd", .exact, "uygulama güvenlik denetimi"),
        ("trustd", .exact, "sertifika denetimi"),
        ("swift-frontend", .exact, "Swift derleme"),
        ("finder", .exact, "Finder"),
        ("dock", .exact, "Dock"),
        ("launchd", .exact, "sistem başlatıcı"),
        ("mobileassetd", .exact, "Apple bileşen indirme"),
        ("runningboardd", .exact, "uygulama yaşam döngüsü"),
        ("powerd", .exact, "güç yönetimi"),
        ("bluetoothd", .exact, "Bluetooth"),
        ("airportd", .exact, "Wi-Fi"),
        ("photolibraryd", .exact, "Fotoğraflar arşivi"),
        ("screencapture", .exact, "ekran görüntüsü"),
        ("logd", .exact, "sistem günlüğü"),
        ("activity monitor", .exact, "Etkinlik Monitörü"),
        ("top", .exact, "süreç izleme"),
        ("usagetrackingagent", .exact, "Ekran Süresi takibi"),
        ("islemciizleyici", .exact, "bu uygulama"),
    ]

    static func describe(_ name: String) -> String? {
        // Masaüstü uygulaması "Claude", komut satırı aracı "claude" adıyla çalışır.
        if name == "claude" { return "Claude Code" }
        if name == "Claude" { return "Claude masaüstü uygulaması" }
        let n = name.lowercased()
        for (pattern, match, text) in rules {
            switch match {
            case .exact where n == pattern: return text
            case .prefix where n.hasPrefix(pattern): return text
            case .contains where n.contains(pattern): return text
            default: continue
            }
        }
        return nil
    }

    static func wantsArguments(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.hasPrefix("python") || n.hasPrefix("ffmpeg") || n == "node"
    }

    // Python/node için betik adı, ffmpeg için çıktı dosyasının adı.
    static func detail(name: String, args: String) -> String? {
        let parts = args.split(separator: " ").map(String.init)
        let n = name.lowercased()
        if n.hasPrefix("ffmpeg") {
            guard let last = parts.last, !last.hasPrefix("-"), parts.count > 1 else { return nil }
            return "→ " + (last as NSString).lastPathComponent
        }
        let script = parts.dropFirst().first { $0.hasSuffix(".py") || $0.hasSuffix(".js") || $0.hasSuffix(".mjs") }
        if let s = script { return (s as NSString).lastPathComponent }
        if let i = parts.firstIndex(of: "-m"), i + 1 < parts.count { return "-m " + parts[i + 1] }
        return nil
    }
}
