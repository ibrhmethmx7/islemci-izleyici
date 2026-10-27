import Foundation

// `IslemciIzleyici --dump [tur]`: arayüzün kullandığı ölçümleri terminale yazar ve çıkar.
// Değerleri top / vm_stat / df ile karşılaştırmak için.
enum Dump {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--dump") else { return }
        let rounds = (i + 1 < args.count ? Int(args[i + 1]) : nil) ?? 3
        let sampler = Sampler()
        _ = sampler.sample()
        for _ in 0..<rounds {
            Thread.sleep(forTimeInterval: Monitor.interval)
            let s = sampler.sample()
            print("== \(s.date.formatted(date: .omitted, time: .standard))  CPU \(Fmt.pct(s.cpuTotal)) (uygulamalar \(Fmt.pct(s.cpuUser)), sistem \(Fmt.pct(s.cpuSystem)))")
            for p in s.processes {
                let name = p.name.padding(toLength: 34, withPad: " ", startingAt: 0)
                print("   \(String(p.pid).padding(toLength: 6, withPad: " ", startingAt: 0)) \(name) \(Fmt.pct(p.cpu))\t\(p.estimated ? "–" : (p.memExact ? "" : "≈") + Fmt.mem(p.memBytes))\t\(ProcessCatalog.describe(p.name) ?? "")\(p.detail.map { " · " + $0 } ?? "")")
            }
            print("   -- bellek sırası: " + s.memoryHogs.map { "\($0.name) \($0.memExact ? "" : "≈")\(Fmt.mem($0.memBytes))" }.joined(separator: ", "))
            let m = s.memory
            print("   bellek \(Fmt.mem(m.used))/\(Fmt.mem(m.total)) baskı=\(m.pressure) swap=\(Fmt.mem(m.swapUsed))")
            for v in s.volumes {
                print("   disk \(v.name): \(Fmt.disk(v.availableImportant)) kullanılabilir, \(Fmt.disk(v.availableStrict)) boş, toplam \(Fmt.disk(v.total))")
            }
            fflush(stdout)
        }
        exit(0)
    }
}
