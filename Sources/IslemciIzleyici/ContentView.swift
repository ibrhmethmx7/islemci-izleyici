import SwiftUI

struct ContentView: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        let s = monitor.snap
        VStack(alignment: .leading, spacing: 12) {
            CPUSection(snap: s)
            Divider()
            MemorySection(mem: s.memory)
            Divider()
            DiskSection(volumes: s.volumes)
            Divider()
            ProcessSection(snap: s)
            Divider()
            footer(s)
        }
        .padding(14)
        .frame(width: 440)
        .onAppear { monitor.windowOpen = true }
        .onDisappear { monitor.windowOpen = false }
    }

    private func footer(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let m = monitor.message {
                Text(m).foregroundStyle(.blue)
            } else {
                Text("Son ölçüm \(s.date.formatted(date: .omitted, time: .standard)) · \(s.processCount) süreç")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Toggle("Açılışta başlat", isOn: Binding(
                    get: { monitor.launchAtLogin },
                    set: { monitor.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button("Etkinlik Monitörü") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
                Button("Çık") { NSApp.terminate(nil) }
            }
        }
        .font(.caption)
        .lineLimit(1)
    }
}

// MARK: Bölümler

private struct CPUSection: View {
    let snap: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Toplam CPU").font(.caption).foregroundStyle(.secondary)
                    Text(snap.cpuReady ? Fmt.pct(snap.cpuTotal) : "…")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("uygulamalar \(Fmt.pct(snap.cpuUser))")
                    Text("sistem \(Fmt.pct(snap.cpuSystem))")
                    Text("\(snap.coreCount) çekirdek")
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            UsageBar(fraction: snap.cpuTotal / 100, color: levelColor(snap.cpuTotal, warn: 60, crit: 85))
        }
    }
}

private struct MemorySection: View {
    let mem: MemoryInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bellek").font(.headline)
                PressureBadge(pressure: mem.pressure)
                Spacer()
                Text("\(Fmt.mem(mem.used)) / \(Fmt.mem(mem.total)) kullanılıyor")
                    .monospacedDigit()
            }
            UsageBar(fraction: mem.total > 0 ? Double(mem.used) / Double(mem.total) : 0,
                     color: pressureColor(mem.pressure))
            Text("uygulamalar \(Fmt.mem(mem.app)) · kalıcı \(Fmt.mem(mem.wired)) · sıkıştırılmış \(Fmt.mem(mem.compressed)) · önbellek \(Fmt.mem(mem.cached))")
                .font(.caption).foregroundStyle(.secondary)
            if mem.swapUsed > 0 {
                Text(swapText)
                    .font(.caption)
                    .foregroundStyle(swapWriting ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension MemorySection {
    // Yavaşlatan, swap'ın büyüklüğü değil diske sürekli yazılmasıdır.
    var swapWriting: Bool { (mem.swapOutPerSec ?? 0) > 1_048_576 }

    var swapText: String {
        let base = "Swap (diske taşan bellek): \(Fmt.mem(mem.swapUsed))"
        guard let out = mem.swapOutPerSec, let inn = mem.swapInPerSec else { return base }
        if swapWriting {
            return base + " — şu an diske yazılıyor (\(Fmt.mem(UInt64(out)))/sn), RAM yetmiyor; bu yavaşlatır."
        }
        if inn > 1_048_576 {
            return base + " — yeni yazma yok, diskten geri okunuyor (\(Fmt.mem(UInt64(inn)))/sn)."
        }
        return base + " — durgun, şu an diske yazılmıyor. Yeniden başlatınca sıfırlanır."
    }
}

private struct DiskSection: View {
    let volumes: [VolumeInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(volumes) { v in
                let color = diskColor(v.availableImportant)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(v.name).font(.headline)
                        Spacer()
                        Text(Fmt.disk(v.availableImportant))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                            .monospacedDigit()
                        Text("boş").foregroundStyle(color)
                    }
                    UsageBar(fraction: 1 - Double(v.availableImportant) / Double(v.total), color: color)
                    HStack {
                        Text("toplam \(Fmt.disk(v.total))")
                        if v.availableImportant - v.availableStrict > 1_000_000_000 {
                            Text("· şu an gerçekten boş \(Fmt.disk(v.availableStrict)), gerisini macOS gerekince boşaltır")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if v.availableImportant < DiskLevel.critical {
                        Text("Disk dolmak üzere: 4K render yarıda kesilebilir.")
                            .font(.caption.bold()).foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

private struct ProcessSection: View {
    @EnvironmentObject var monitor: Monitor
    @AppStorage("belleğeGöreSırala") private var byMemory = false
    let snap: Snapshot

    var body: some View {
        let rows = byMemory ? snap.memoryHogs : snap.processes
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(byMemory ? "En çok bellek kullananlar" : "En çok CPU kullananlar").font(.headline)
                Spacer()
                Picker("Sırala", selection: $byMemory) {
                    Text("CPU").tag(false)
                    Text("Bellek").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Text(byMemory
                 ? "Bellek: Etkinlik Monitörü'ndeki gerçek bellek. ≈ işaretliler sistem süreçleri; yalnızca RAM'deki kısmı ölçülebiliyor."
                 : "CPU: %100 = 1 çekirdek, toplam \(snap.coreCount) çekirdek.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Süreç")
                Spacer()
                Text("CPU").frame(width: 52, alignment: .trailing)
                Text("Bellek").frame(width: 62, alignment: .trailing)
                Color.clear.frame(width: 22, height: 1)
            }
            .font(.caption).foregroundStyle(.secondary)

            ForEach(rows) { p in
                ProcessRowView(p: p, controllable: monitor.canControl(p))
            }
            if rows.isEmpty {
                Text("Ölçülüyor…").foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProcessRowView: View {
    @EnvironmentObject var monitor: Monitor
    let p: ProcRow
    let controllable: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(p.name).lineLimit(1).truncationMode(.middle)
                    if p.nice > 0 {
                        Text("düşük öncelik")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(.blue.opacity(0.15)))
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Fmt.pct(p.cpu))
                .monospacedDigit()
                .foregroundStyle(levelColor(p.cpu, warn: 50, crit: 100, base: .primary))
                .frame(width: 52, alignment: .trailing)
            Text(p.estimated ? "–" : (p.memExact ? "" : "≈") + Fmt.mem(p.memBytes))
                .monospacedDigit()
                .frame(width: 62, alignment: .trailing)
            Menu {
                Button("Önceliği düşür (nice +10)") { monitor.lowerPriority(p) }
                Divider()
                Button("Sonlandır…", role: .destructive) { monitor.confirmAndTerminate(p) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 22)
            .disabled(!controllable)
            .opacity(controllable ? 1 : 0.3)
            .help(controllable ? "Önceliği düşür ya da sonlandır" : "Sistem ya da başka kullanıcıya ait; değiştirilemez")
        }
    }

    private var subtitle: String {
        let parts = [ProcessCatalog.describe(p.name), p.detail, p.estimated ? "tahmini" : nil].compactMap { $0 }
        return parts.isEmpty ? "PID \(p.pid)" : parts.joined(separator: " · ")
    }
}

// MARK: Küçük parçalar

private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

private struct PressureBadge: View {
    let pressure: MemoryInfo.Pressure

    var body: some View {
        let text: String = switch pressure {
        case .normal: "baskı normal"
        case .warning: "baskı yüksek"
        case .critical: "baskı kritik"
        case .unknown: "baskı bilinmiyor"
        }
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(pressureColor(pressure).opacity(0.2)))
            .foregroundStyle(pressureColor(pressure))
    }
}

private func levelColor(_ v: Double, warn: Double, crit: Double, base: Color = .green) -> Color {
    v >= crit ? .red : v >= warn ? .orange : base
}

private func pressureColor(_ p: MemoryInfo.Pressure) -> Color {
    switch p {
    case .normal: .green
    case .warning: .orange
    case .critical: .red
    case .unknown: .gray
    }
}

private func diskColor(_ free: Int64) -> Color {
    free < DiskLevel.critical ? .red : free < DiskLevel.warning ? .orange : .green
}
