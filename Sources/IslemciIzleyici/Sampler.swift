import Foundation
import Darwin

// Tek bir ölçümün sonucu. Arka planda hesaplanır, ana iş parçacığında gösterilir.
struct Snapshot {
    var date = Date()
    var cpuReady = false          // ilk ölçümde fark olmadığı için CPU henüz bilinmez
    var cpuTotal: Double = 0      // 0–100, bütün çekirdeklerin ortalaması
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var coreCount = ProcessInfo.processInfo.activeProcessorCount
    var processes: [ProcRow] = []    // CPU'ya göre ilk 10
    var memoryHogs: [ProcRow] = []   // belleğe göre ilk 10
    var processCount = 0
    var memory = MemoryInfo()
    var volumes: [VolumeInfo] = []
}

struct ProcRow: Identifiable, Equatable {
    let pid: Int32
    let uid: UInt32
    let name: String
    let cpu: Double               // tek çekirdeğe göre yüzde (Etkinlik Monitörü gibi)
    let memBytes: UInt64
    let memExact: Bool            // true: gerçek bellek (phys_footprint); false: yalnızca RSS
    let nice: Int
    var detail: String?           // örn. python betiğinin adı
    var estimated = false         // kernel_task: doğrudan ölçülemiyor, kalandan hesaplanır
    var id: Int32 { pid }
}

struct MemoryInfo {
    enum Pressure { case normal, warning, critical, unknown }
    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: Pressure = .unknown
    var freePercent: Int?         // kern.memorystatus_level
    var swapOutPerSec: Double?    // bayt/sn; diske yazılan (yavaşlatan budur)
    var swapInPerSec: Double?     // bayt/sn; diskten geri okunan
    var used: UInt64 { app + wired + compressed }
}

struct VolumeInfo: Identifiable {
    let name: String
    let path: String
    let total: Int64
    let availableImportant: Int64 // macOS'un "kullanılabilir" dediği (temizlenebilir alan dahil)
    let availableStrict: Int64    // df'teki gibi, şu an gerçekten boş olan
    var id: String { path }
}

// Yalnızca Monitor'ün seri kuyruğunda kullanılır; durumuna aynı anda iki yerden erişilmez.
final class Sampler: @unchecked Sendable {
    private let host = mach_host_self()
    private let pageSize: UInt64 = sysctlValue("hw.pagesize", as: UInt64.self) ?? 16384
    private var prevTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var prevCPUTimes: [Int32: Double] = [:]
    private var prevDate: Date?
    private let myUID = getuid()
    private var prevSwap: (ins: UInt64, outs: UInt64, date: Date)?

    // Süreç listesi yalnızca pencere açıkken gerekir; menü çubuğu için toplam CPU ve disk yeter.
    func sample(processes: Bool = true) -> Snapshot {
        var snap = Snapshot()
        sampleCPU(into: &snap)
        if processes { sampleProcesses(into: &snap) }
        snap.memory = sampleMemory()
        snap.volumes = sampleVolumes()
        return snap
    }

    // MARK: Toplam CPU

    private func sampleCPU(into snap: inout Snapshot) {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let t = info.cpu_ticks
        let now = (user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
        defer { prevTicks = now }
        guard let p = prevTicks else { return }
        let user = Double(now.user &- p.user) + Double(now.nice &- p.nice)
        let system = Double(now.system &- p.system)
        let idle = Double(now.idle &- p.idle)
        let all = user + system + idle
        guard all > 0 else { return }
        snap.cpuReady = true
        snap.cpuUser = user / all * 100
        snap.cpuSystem = system / all * 100
        snap.cpuTotal = snap.cpuUser + snap.cpuSystem
    }

    // MARK: Süreçler

    // /bin/ps root yetkisiyle (setuid) çalıştığı için sistem süreçlerini de görür.
    private func sampleProcesses(into snap: inout Snapshot) {
        guard let out = run("/bin/ps", ["-Aceo", "pid=,uid=,rss=,time=,pcpu=,nice=,comm="]) else { return }
        let now = Date()
        let elapsed = prevDate.map { now.timeIntervalSince($0) } ?? 0
        // Pencere uzun süre kapalı kaldıysa önceki ölçüm bayattır; fark anlık değeri vermez.
        let fresh = elapsed > 0.5 && elapsed < 3 * 2.0
        var times: [Int32: Double] = [:]
        var rows: [ProcRow] = []
        var deltasValid = fresh

        for line in out.split(separator: "\n") {
            let f = fields(String(line), count: 6)
            guard f.count == 7, let pid = Int32(f[0]), let uid = UInt32(f[1]),
                  let rssKB = UInt64(f[2]), let cpuTime = parseCPUTime(f[3]),
                  let pcpu = Double(f[4]), let nice = Int(f[5]) else { continue }
            times[pid] = cpuTime
            // Anlık değer: birikmiş CPU süresinin farkı. İlk ölçümde ps'in ortalamasına düş.
            var cpu = pcpu
            if fresh, let prev = prevCPUTimes[pid], cpuTime >= prev {
                cpu = (cpuTime - prev) / elapsed * 100
            } else if prevCPUTimes[pid] != nil {
                deltasValid = false
            }
            // RSS sıkıştırılmış ve swap'taki belleği saymaz. Kendi süreçlerimiz için Etkinlik
            // Monitörü'nün "Bellek" sütunundaki phys_footprint okunabilir; diğerleri RSS'te kalır.
            let footprint = uid == myUID ? physFootprint(pid) : nil
            rows.append(ProcRow(pid: pid, uid: uid, name: f[6], cpu: cpu,
                                memBytes: footprint ?? rssKB * 1024, memExact: footprint != nil, nice: nice))
        }
        prevCPUTimes = times
        prevDate = now
        snap.processCount = rows.count

        // ps PID 0'ı (kernel_task) göstermez, yetkisiz okunamaz da. Toplam meşguliyetten
        // görünen süreçlerin toplamını çıkarınca kalan büyük ölçüde kernel_task'tır.
        if deltasValid && snap.cpuReady {
            let busy = snap.cpuTotal * Double(snap.coreCount)
            let seen = rows.reduce(0) { $0 + $1.cpu }
            let rest = busy - seen
            if rest > 1 {
                var k = ProcRow(pid: 0, uid: 0, name: "kernel_task", cpu: rest, memBytes: 0, memExact: false, nice: 0)
                k.estimated = true
                rows.append(k)
            }
        }

        var byCPU = Array(rows.sorted { $0.cpu > $1.cpu }.prefix(10))
        var byMem = Array(rows.filter { !$0.estimated }.sorted { $0.memBytes > $1.memBytes }.prefix(10))
        addDetails(to: &byCPU)
        addDetails(to: &byMem)
        snap.processes = byCPU
        snap.memoryHogs = byMem
    }

    private func physFootprint(_ pid: Int32) -> UInt64? {
        var info = rusage_info_v4()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return r == 0 ? info.ri_phys_footprint : nil
    }

    // Python/ffmpeg/node satırları için hangi dosyayla çalıştığını ekler.
    private func addDetails(to rows: inout [ProcRow]) {
        let wanted = rows.filter { ProcessCatalog.wantsArguments($0.name) }.map { String($0.pid) }
        guard !wanted.isEmpty,
              let out = run("/bin/ps", ["-o", "pid=,args=", "-p", wanted.joined(separator: ",")]) else { return }
        var args: [Int32: String] = [:]
        for line in out.split(separator: "\n") {
            let f = fields(String(line), count: 1)
            if f.count == 2, let pid = Int32(f[0]) { args[pid] = f[1] }
        }
        for i in rows.indices {
            if let a = args[rows[i].pid] {
                rows[i].detail = ProcessCatalog.detail(name: rows[i].name, args: a)
            }
        }
    }

    // MARK: Bellek

    private func sampleMemory() -> MemoryInfo {
        var m = MemoryInfo()
        m.total = sysctlValue("hw.memsize", as: UInt64.self) ?? 0
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            // Etkinlik Monitörü ile aynı ayrım: uygulama + kalıcı + sıkıştırılmış = kullanılan.
            m.app = UInt64(vm.internal_page_count &- vm.purgeable_count) * pageSize
            m.wired = UInt64(vm.wire_count) * pageSize
            m.compressed = UInt64(vm.compressor_page_count) * pageSize
            m.cached = UInt64(vm.external_page_count + vm.purgeable_count) * pageSize
            let now = (ins: vm.swapins, outs: vm.swapouts, date: Date())
            if let p = prevSwap, now.ins >= p.ins, now.outs >= p.outs {
                let dt = now.date.timeIntervalSince(p.date)
                if dt > 0.5 {
                    m.swapInPerSec = Double((now.ins - p.ins) * pageSize) / dt
                    m.swapOutPerSec = Double((now.outs - p.outs) * pageSize) / dt
                }
            }
            prevSwap = now
        }
        if let swap = sysctlValue("vm.swapusage", as: xsw_usage.self) {
            m.swapUsed = swap.xsu_used
            m.swapTotal = swap.xsu_total
        }
        switch sysctlValue("kern.memorystatus_vm_pressure_level", as: Int32.self) {
        case 1: m.pressure = .normal
        case 2: m.pressure = .warning
        case 4: m.pressure = .critical
        default: m.pressure = .unknown
        }
        m.freePercent = sysctlValue("kern.memorystatus_level", as: Int32.self).map(Int.init)
        return m
    }

    // MARK: Disk

    private func sampleVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsBrowsableKey,
                                      .volumeIsLocalKey]
        var urls = [URL(fileURLWithPath: "/")]
        let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                            options: [.skipHiddenVolumes]) ?? []
        urls += mounted.filter { $0.path.hasPrefix("/Volumes/") }

        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  let total = v.volumeTotalCapacity, total > 0 else { return nil }
            if url.path != "/" && v.volumeIsBrowsable == false { return nil }
            let strict = Int64(v.volumeAvailableCapacity ?? 0)
            let important = v.volumeAvailableCapacityForImportantUsage ?? strict
            let name = url.path == "/" ? "Mac diski" : (v.volumeName ?? url.lastPathComponent)
            return VolumeInfo(name: name, path: url.path, total: Int64(total),
                              availableImportant: important, availableStrict: strict)
        }
    }
}

// MARK: Yardımcılar

func sysctlValue<T>(_ name: String, as type: T.Type) -> T? {
    var size = MemoryLayout<T>.size
    let ptr = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<T>.alignment)
    defer { ptr.deallocate() }
    guard sysctlbyname(name, ptr, &size, nil, 0) == 0, size == MemoryLayout<T>.size else { return nil }
    return ptr.load(as: T.self)
}

func run(_ path: String, _ args: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8)
}

// İlk `count` alanı boşluklardan böler, geri kalanı (içinde boşluk olabilen süreç adı) tek alan olur.
func fields(_ line: String, count: Int) -> [String] {
    var result: [String] = []
    var rest = Substring(line)
    for _ in 0..<count {
        rest = rest.drop { $0 == " " }
        guard let end = rest.firstIndex(of: " ") else { return result + [String(rest)] }
        result.append(String(rest[..<end]))
        rest = rest[end...]
    }
    result.append(String(rest.drop { $0 == " " }))
    return result
}

// "3863:40.89", "1:02:03.45" ya da "2-01:02:03" biçimlerini saniyeye çevirir.
func parseCPUTime(_ s: String) -> Double? {
    var days = 0.0
    var body = Substring(s)
    if let dash = body.firstIndex(of: "-") {
        days = Double(body[..<dash]) ?? 0
        body = body[body.index(after: dash)...]
    }
    var total = 0.0
    for part in body.split(separator: ":") {
        guard let v = Double(part) else { return nil }
        total = total * 60 + v
    }
    return days * 86400 + total
}
