import Foundation
import Darwin

public struct MemorySnapshot: Equatable {
    public let totalRAMGB: Double
    public let usedRAMGB: Double
    public let freeRAMGB: Double
    public let appUsageMB: Double

    public var usedPercentage: Double {
        guard totalRAMGB > 0 else { return 0 }
        return min(1.0, max(0.0, usedRAMGB / totalRAMGB))
    }
}

@MainActor
public final class HardwareMonitor: ObservableObject {
    @Published public var currentSnapshot: MemorySnapshot

    private var pollTimer: Timer?

    public init() {
        self.currentSnapshot = Self.readMemory()
        self.pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentSnapshot = Self.readMemory()
            }
        }
    }

    deinit {
        pollTimer?.invalidate()
    }

    public static func readMemory() -> MemorySnapshot {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalGB = Double(totalBytes) / 1_073_741_824.0

        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64()
        let hostPort = mach_host_self()

        let kerr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        var usedGB: Double = 0
        var freeGB: Double = totalGB

        if kerr == KERN_SUCCESS {
            let pageSize = vm_kernel_page_size
            let active = Double(vmStats.active_count) * Double(pageSize)
            let wired = Double(vmStats.wire_count) * Double(pageSize)
            let compressed = Double(vmStats.compressor_page_count) * Double(pageSize)
            usedGB = (active + wired + compressed) / 1_073_741_824.0
            freeGB = max(0, totalGB - usedGB)
        }

        var taskInfo = mach_task_basic_info()
        var taskCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        var appMB: Double = 0
        let taskErr = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(taskCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &taskCount)
            }
        }
        if taskErr == KERN_SUCCESS {
            appMB = Double(taskInfo.resident_size) / 1_048_576.0
        }

        return MemorySnapshot(
            totalRAMGB: totalGB,
            usedRAMGB: usedGB,
            freeRAMGB: freeGB,
            appUsageMB: appMB
        )
    }
}
