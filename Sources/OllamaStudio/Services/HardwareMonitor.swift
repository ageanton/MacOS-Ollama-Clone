import Foundation
import Darwin

/// Queries the macOS Mach kernel (`host_statistics64` and `sysctl`) to provide accurate,
/// zero-overhead Apple Silicon Unified Memory telemetry.
@MainActor
public final class HardwareMonitor: ObservableObject {
    @Published public private(set) var totalMemoryGB: Double = 16.0
    @Published public private(set) var usedMemoryGB: Double = 8.0
    @Published public private(set) var wiredMemoryGB: Double = 2.0
    @Published public private(set) var availableMemoryGB: Double = 8.0
    @Published public private(set) var chipName: String = "Apple Silicon"
    @Published public private(set) var performanceCoreCount: Int = 8
    @Published public private(set) var freeDiskSpaceGB: Double = 100.0

    private var timer: Timer?

    public init() {
        self.totalMemoryGB = Self.readTotalPhysicalMemoryGB()
        self.chipName = Self.readChipBrandString()
        self.performanceCoreCount = Self.readCoreCount()
        refreshMetrics()
        startPolling()
    }

    public func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMetrics()
            }
        }
    }

    public var memoryUsageFraction: Double {
        guard totalMemoryGB > 0 else { return 0 }
        return min(1.0, max(0.0, usedMemoryGB / totalMemoryGB))
    }

    public enum CompatibilityBadge: Equatable {
        case runsGreat(String)
        case runsModerately(String)
        case tooHeavy(String)
    }

    /// Evaluates whether a model of a given byte size will run smoothly on this Mac
    public func evaluateModelCompatibility(modelSizeBytes: Int64) -> CompatibilityBadge {
        let modelGB = Double(modelSizeBytes) / 1_073_741_824.0
        let requiredWithContext = modelGB + 1.2
        if requiredWithContext <= totalMemoryGB * 0.65 {
            return .runsGreat("Runs fast in Metal (\(String(format: "%.1f", modelGB)) GB)")
        } else if requiredWithContext <= totalMemoryGB * 0.82 {
            return .runsModerately("Fits in RAM (\(String(format: "%.1f", modelGB)) GB) — close heavy apps")
        } else {
            return .tooHeavy("Exceeds safe RAM (\(String(format: "%.1f", modelGB)) GB on \(Int(totalMemoryGB)) GB Mac)")
        }
    }

    public func refreshMetrics() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        var pageSize: vm_size_t = 16384
        host_page_size(hostPort, &pageSize)
        let pageBytes = Double(pageSize)

        if result == KERN_SUCCESS {
            let active = Double(stats.active_count) * pageBytes
            let wired = Double(stats.wire_count) * pageBytes
            let compressed = Double(stats.compressor_page_count) * pageBytes
            let usedBytes = active + wired + compressed
            let usedGB = usedBytes / 1_073_741_824.0

            self.wiredMemoryGB = wired / 1_073_741_824.0
            self.usedMemoryGB = min(totalMemoryGB, max(0.5, usedGB))
            self.availableMemoryGB = max(0.0, totalMemoryGB - self.usedMemoryGB)
        }

        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeBytes = attrs[.systemFreeSize] as? NSNumber {
            self.freeDiskSpaceGB = freeBytes.doubleValue / 1_073_741_824.0
        }
    }

    private static func readTotalPhysicalMemoryGB() -> Double {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &size, &len, nil, 0) == 0 {
            return Double(size) / 1_073_741_824.0
        }
        return Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    }

    private static func readChipBrandString() -> String {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 {
                return String(cString: buffer)
            }
        }
        return "Apple Silicon"
    }

    private static func readCoreCount() -> Int {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &count, &size, nil, 0) == 0, count > 0 {
            return Int(count)
        }
        return ProcessInfo.processInfo.activeProcessorCount
    }
}
