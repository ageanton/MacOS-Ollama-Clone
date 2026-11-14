set -eo pipefail
cat << 'EOF' > Motif/Sources/Motif/Engine/ReasoningAndMemoryEngine.swift
import Foundation
import Darwin
import Metal

// MARK: - Stop-Safe Stateful Thinking Stream Parser
public final class StatefulThinkingStreamParser {
    public enum State {
        case normalOrAwaitingOpeningTag
        case insideThinkingBlock
        case postThinkingAnswer
    }

    public private(set) var state: State = .normalOrAwaitingOpeningTag
    private var pendingBuffer: String = ""
    private let openTags = ["<think>", "<thought>", "<reasoning>", "<|thought|>"]
    private let closeTags = ["</think>", "</thought>", "</reasoning>", "<|/thought|>"]

    public private(set) var accumulatedThinking: String = ""
    public private(set) var accumulatedAnswer: String = ""
    public private(set) var isCurrentlyThinking: Bool = false
    public private(set) var thinkingStartTime: Date?
    public private(set) var thinkingDurationSeconds: Double = 0.0

    public init() {}

    public func preloadExisting(
        thinking: String,
        answer: String,
        resumeInsideThinking: Bool,
        priorThinkingDuration: Double = 0.0
    ) {
        accumulatedThinking = thinking
        accumulatedAnswer = answer
        thinkingDurationSeconds = priorThinkingDuration
        if resumeInsideThinking {
            state = .insideThinkingBlock
            isCurrentlyThinking = true
            thinkingStartTime = Date().addingTimeInterval(-priorThinkingDuration)
        } else if !thinking.isEmpty || !answer.isEmpty {
            state = .postThinkingAnswer
            isCurrentlyThinking = false
        } else {
            state = .normalOrAwaitingOpeningTag
            isCurrentlyThinking = false
        }
    }

    public func ingestExplicitThinkingDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        if thinkingStartTime == nil {
            thinkingStartTime = Date()
        }
        isCurrentlyThinking = true
        accumulatedThinking += delta
        if let start = thinkingStartTime {
            thinkingDurationSeconds = Date().timeIntervalSince(start)
        }
    }

    public func ingestContentChunk(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        pendingBuffer += chunk
        processBuffer()
    }

    public func flushPendingBufferWithoutLosingState(markComplete: Bool) {
        if !pendingBuffer.isEmpty {
            switch state {
            case .insideThinkingBlock:
                accumulatedThinking += pendingBuffer
            case .normalOrAwaitingOpeningTag, .postThinkingAnswer:
                accumulatedAnswer += pendingBuffer
            }
            pendingBuffer = ""
        }
        if let start = thinkingStartTime, isCurrentlyThinking {
            thinkingDurationSeconds = Date().timeIntervalSince(start)
        }
        if markComplete {
            isCurrentlyThinking = false
        }
    }

    private func processBuffer() {
        var keepProcessing = true
        while keepProcessing && !pendingBuffer.isEmpty {
            keepProcessing = false

            switch state {
            case .normalOrAwaitingOpeningTag:
                if let match = findFirstTag(in: pendingBuffer, tags: openTags) {
                    let prefix = String(pendingBuffer[..<match.range.lowerBound])
                    if !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        accumulatedAnswer += prefix
                    }
                    pendingBuffer.removeSubrange(..<match.range.upperBound)
                    state = .insideThinkingBlock
                    isCurrentlyThinking = true
                    if thinkingStartTime == nil {
                        thinkingStartTime = Date()
                    }
                    keepProcessing = true
                } else if let partialIdx = trailingPartialTagIndex(in: pendingBuffer, tags: openTags) {
                    let safePrefix = String(pendingBuffer[..<partialIdx])
                    accumulatedAnswer += safePrefix
                    pendingBuffer.removeSubrange(..<partialIdx)
                } else {
                    if isCurrentlyThinking && !accumulatedThinking.isEmpty {
                        if let start = thinkingStartTime {
                            thinkingDurationSeconds = Date().timeIntervalSince(start)
                        }
                        isCurrentlyThinking = false
                    }
                    accumulatedAnswer += pendingBuffer
                    pendingBuffer = ""
                }

            case .insideThinkingBlock:
                if let start = thinkingStartTime {
                    thinkingDurationSeconds = Date().timeIntervalSince(start)
                }
                if let match = findFirstTag(in: pendingBuffer, tags: closeTags) {
                    let thoughtSegment = String(pendingBuffer[..<match.range.lowerBound])
                    accumulatedThinking += thoughtSegment
                    pendingBuffer.removeSubrange(..<match.range.upperBound)
                    if pendingBuffer.hasPrefix("\n") {
                        pendingBuffer.removeFirst()
                    }
                    isCurrentlyThinking = false
                    state = .postThinkingAnswer
                    keepProcessing = true
                } else if let partialIdx = trailingPartialTagIndex(in: pendingBuffer, tags: closeTags) {
                    let safeThought = String(pendingBuffer[..<partialIdx])
                    accumulatedThinking += safeThought
                    pendingBuffer.removeSubrange(..<partialIdx)
                } else {
                    accumulatedThinking += pendingBuffer
                    pendingBuffer = ""
                }

            case .postThinkingAnswer:
                if let match = findFirstTag(in: pendingBuffer, tags: closeTags) {
                    let thoughtSegment = String(pendingBuffer[..<match.range.lowerBound])
                    accumulatedThinking += thoughtSegment
                    pendingBuffer.removeSubrange(..<match.range.upperBound)
                    if pendingBuffer.hasPrefix("\n") {
                        pendingBuffer.removeFirst()
                    }
                    isCurrentlyThinking = false
                    keepProcessing = true
                } else {
                    accumulatedAnswer += pendingBuffer
                    pendingBuffer = ""
                }
            }
        }
    }

    private func findFirstTag(in text: String, tags: [String]) -> (tag: String, range: Range<String.Index>)? {
        var earliest: (String, Range<String.Index>)? = nil
        for tag in tags {
            if let range = text.range(of: tag) {
                if earliest == nil || range.lowerBound < earliest!.1.lowerBound {
                    earliest = (tag, range)
                }
            }
        }
        return earliest
    }

    private func trailingPartialTagIndex(in text: String, tags: [String]) -> String.Index? {
        guard let lastAngle = text.lastIndex(of: "<") else { return nil }
        let suffix = String(text[lastAngle...])
        for tag in tags {
            if tag.hasPrefix(suffix) && suffix.count < tag.count {
                return lastAngle
            }
        }
        return nil
    }
}

// MARK: - Kernel-Level Mach VM + proc_pidinfo + Metal Headroom Telemetry
public struct UnifiedMemorySnapshot: Equatable, Sendable {
    public var totalPhysicalRAMBytes: Int64
    public var totalSystemUsedBytes: Int64
    public var systemAndOSWiredBytes: Int64
    public var modelWeightsResidentBytes: Int64
    public var kvCacheAllocatedBytes: Int64
    public var metalRecommendedMaxBytes: Int64
    public var baselineRAMBytesBeforeLoad: Int64
    public var targetModelSizeBytes: Int64
    public var historySamplesGB: [Double]

    public var freeHeadroomBytes: Int64 {
        max(0, totalPhysicalRAMBytes - totalSystemUsedBytes)
    }

    public var totalGB: Double { Double(totalPhysicalRAMBytes) / 1_073_741_824.0 }
    public var usedGB: Double { Double(totalSystemUsedBytes) / 1_073_741_824.0 }
    public var systemGB: Double { Double(systemAndOSWiredBytes) / 1_073_741_824.0 }
    public var weightsGB: Double { Double(modelWeightsResidentBytes) / 1_073_741_824.0 }
    public var kvCacheGB: Double { Double(kvCacheAllocatedBytes) / 1_073_741_824.0 }
    public var headroomGB: Double { Double(freeHeadroomBytes) / 1_073_741_824.0 }
    public var metalMaxGB: Double { Double(metalRecommendedMaxBytes) / 1_073_741_824.0 }
    public var targetModelGB: Double { Double(targetModelSizeBytes) / 1_073_741_824.0 }

    public var activeRAMDeltaGB: Double {
        if baselineRAMBytesBeforeLoad > 0 {
            let rawDelta = Double(totalSystemUsedBytes - baselineRAMBytesBeforeLoad) / 1_073_741_824.0
            if rawDelta > 0.05 {
                return rawDelta
            }
        }
        return weightsGB
    }

    public var loadProgressAgainstTarget: Double {
        guard targetModelSizeBytes > 0 else { return 0.0 }
        let allocated = max(Double(modelWeightsResidentBytes), activeRAMDeltaGB * 1_073_741_824.0)
        return min(0.99, max(0.0, allocated / Double(targetModelSizeBytes)))
    }

    public var usageFraction: Double {
        guard totalPhysicalRAMBytes > 0 else { return 0 }
        return min(1.0, Double(totalSystemUsedBytes) / Double(totalPhysicalRAMBytes))
    }

    public var weightsFraction: Double {
        guard totalPhysicalRAMBytes > 0 else { return 0 }
        return min(1.0, Double(modelWeightsResidentBytes) / Double(totalPhysicalRAMBytes))
    }
}

public enum HardwareMemoryEngine {
    public static let cachedMetalRecommendedMaxBytes: Int64 = {
        let totalRAM = Int64(ProcessInfo.processInfo.physicalMemory)
        return Int64(MTLCreateSystemDefaultDevice()?.recommendedMaxWorkingSetSize ?? UInt64(Double(totalRAM) * 0.75))
    }()

    public static func queryOllamaProcessResidentBytes() -> Int64 {
        let maxPids = 2048
        var pids = [pid_t](repeating: 0, count: maxPids)
        let byteSize = Int32(maxPids * MemoryLayout<pid_t>.stride)
        let countBytes = proc_listallpids(&pids, byteSize)
        guard countBytes > 0 else { return 0 }
        let pidCount = Int(countBytes) / MemoryLayout<pid_t>.stride

        var totalOllamaRSS: Int64 = 0
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }
            let nameLen = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            if nameLen > 0 {
                let procName = String(cString: nameBuffer).lowercased()
                if procName.contains("ollama") {
                    var taskInfo = proc_taskinfo()
                    let infoSize = Int32(MemoryLayout<proc_taskinfo>.stride)
                    let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, infoSize)
                    if ret == infoSize {
                        totalOllamaRSS += Int64(taskInfo.pti_resident_size)
                    }
                }
            }
        }
        return totalOllamaRSS
    }

    public static func queryAppleSiliconMemory(
        liveOllamaVRAMBytes: Int64,
        estimatedKVCacheBytes: Int64,
        baselineRAMBytesBeforeLoad: Int64,
        targetModelSizeBytes: Int64,
        previousHistory: [Double]
    ) -> UnifiedMemorySnapshot {
        let totalRAM = Int64(ProcessInfo.processInfo.physicalMemory)
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        var pageSize: vm_size_t = vm_kernel_page_size
        host_page_size(hostPort, &pageSize)
        let pageBytes = Int64(pageSize)

        let kernResult = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        var trueSystemUsedBytes: Int64 = totalRAM / 2
        if kernResult == KERN_SUCCESS {
            let internalPages = Int64(vmStats.internal_page_count)
            let purgeablePages = Int64(vmStats.purgeable_count)
            let appPages = max(0, internalPages - purgeablePages)
            let wiredPages = Int64(vmStats.wire_count)
            let compressedPages = Int64(vmStats.compressor_page_count)
            trueSystemUsedBytes = min(totalRAM, (appPages + wiredPages + compressedPages) * pageBytes)
        }

        let kernelOllamaRSS = queryOllamaProcessResidentBytes()
        let effectiveOllamaBytes = max(liveOllamaVRAMBytes, kernelOllamaRSS)

        let actualKVBytes = effectiveOllamaBytes > 0 ? min(estimatedKVCacheBytes, effectiveOllamaBytes / 4) : 0
        let actualWeightsBytes = max(0, effectiveOllamaBytes - actualKVBytes)
        let otherSystemUsedBytes = max(1_073_741_824, trueSystemUsedBytes - effectiveOllamaBytes)
        let totalUsed = min(totalRAM, otherSystemUsedBytes + actualWeightsBytes + actualKVBytes)

        let metalMax = cachedMetalRecommendedMaxBytes

        var history = previousHistory
        history.append(Double(totalUsed) / 1_073_741_824.0)
        if history.count > 30 {
            history.removeFirst()
        }

        return UnifiedMemorySnapshot(
            totalPhysicalRAMBytes: totalRAM,
            totalSystemUsedBytes: totalUsed,
            systemAndOSWiredBytes: otherSystemUsedBytes,
            modelWeightsResidentBytes: actualWeightsBytes,
            kvCacheAllocatedBytes: actualKVBytes,
            metalRecommendedMaxBytes: metalMax,
            baselineRAMBytesBeforeLoad: baselineRAMBytesBeforeLoad,
            targetModelSizeBytes: targetModelSizeBytes,
            historySamplesGB: history
        )
    }
}
EOF
