import AppKit
import Foundation

@MainActor
final class Monitor: ObservableObject {
    @Published private(set) var snap = Snapshot()
    @Published var message: String?

    nonisolated static let interval: TimeInterval = 2
    // Kapatılırsa oturum düşer ya da sistem bozulur; düğmeler bunlarda hiç açılmaz.
    private static let protectedNames: Set<String> = ["windowserver", "kernel_task", "launchd", "loginwindow"]

    private let sampler = Sampler()
    private let queue = DispatchQueue(label: "islemci-izleyici.sampler", qos: .utility)
    private var sampling = false
    private var timer: Timer?
    private var messageClear: DispatchWorkItem?

    var windowOpen = false {
        didSet { if windowOpen && !oldValue { tick() } }
    }

    init() {
        tick()
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard !sampling else { return }
        sampling = true
        let sampler = self.sampler
        let withProcesses = windowOpen
        queue.async {
            let s = sampler.sample(processes: withProcesses)
            DispatchQueue.main.async {
                self.snap = s
                self.sampling = false
            }
        }
    }

    var mainVolume: VolumeInfo? { snap.volumes.first { $0.path == "/" } }

    var menuTitle: String {
        var title = snap.cpuReady ? "CPU " + Fmt.pct(snap.cpuTotal) : "CPU …"
        if let v = mainVolume, v.availableImportant < DiskLevel.warning {
            title += " · Disk " + Fmt.disk(v.availableImportant)
        }
        return title
    }

    // MARK: Süreç işlemleri

    func canControl(_ p: ProcRow) -> Bool {
        p.uid == getuid() && p.pid != getpid() && !Self.protectedNames.contains(p.name.lowercased())
    }

    func lowerPriority(_ p: ProcRow) {
        guard canControl(p), stillSameProcess(p) else { return }
        errno = 0
        let current = getpriority(PRIO_PROCESS, id_t(p.pid))
        if current == -1 && errno != 0 {
            show("Öncelik okunamadı: \(String(cString: strerror(errno)))")
            return
        }
        let target = min(current + 10, 20)
        guard target > current else {
            show("\(p.name) zaten en düşük öncelikte.")
            return
        }
        if setpriority(PRIO_PROCESS, id_t(p.pid), target) == 0 {
            show("\(p.name) önceliği düşürüldü (nice \(current) → \(target)).")
        } else {
            show("Öncelik değiştirilemedi: \(String(cString: strerror(errno)))")
        }
    }

    func confirmAndTerminate(_ p: ProcRow) {
        guard canControl(p) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "“\(p.name)” sonlandırılsın mı?"
        var info = "PID \(p.pid)"
        if let d = ProcessCatalog.describe(p.name) { info += " · \(d)" }
        info += "\n\nSürece kapanma sinyali (SIGTERM) gönderilir. Kaydedilmemiş iş kaybolabilir; devam eden bir render yarıda kalır."
        alert.informativeText = info
        alert.addButton(withTitle: "Vazgeç")
        let kill = alert.addButton(withTitle: "Sonlandır")
        kill.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        guard stillSameProcess(p) else { return }
        if Darwin.kill(p.pid, SIGTERM) == 0 {
            show("\(p.name) için kapanma sinyali gönderildi.")
        } else {
            show("Sonlandırılamadı: \(String(cString: strerror(errno)))")
        }
    }

    // Liste en fazla 2 sn eski; bu arada PID başka bir sürece geçmiş olabilir.
    private func stillSameProcess(_ p: ProcRow) -> Bool {
        let name = run("/bin/ps", ["-c", "-o", "comm=", "-p", String(p.pid)])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name == p.name { return true }
        show("\(p.name) artık çalışmıyor; bir şey yapılmadı.")
        return false
    }

    private func show(_ text: String) {
        message = text
        messageClear?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.message = nil }
        messageClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }
}

enum DiskLevel {
    static let critical: Int64 = 20_000_000_000
    static let warning: Int64 = 50_000_000_000
}

enum Fmt {
    // Türkçede yüzde işareti başa gelir: %43
    static func pct(_ v: Double) -> String {
        (v * 10).rounded() < 100 ? "%" + decimal(v, 1) : "%" + String(Int(v.rounded()))
    }

    // Disk: Finder gibi 1000 tabanlı.
    static func disk(_ b: Int64) -> String {
        let gb = Double(b) / 1e9
        if gb >= 100 { return "\(Int(gb.rounded())) GB" }
        if gb >= 1 { return decimal(gb, 1) + " GB" }
        return "\(Int((Double(b) / 1e6).rounded())) MB"
    }

    // Bellek: Etkinlik Monitörü gibi 1024 tabanlı.
    static func mem(_ b: UInt64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb >= 1 { return decimal(gb, 1) + " GB" }
        return "\(Int((Double(b) / 1_048_576).rounded())) MB"
    }

    static func decimal(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
    }
}
