import Foundation
import os

/// Footprint sampling for chasing out-of-memory terminations.
///
/// `os_proc_available_memory()` returns the bytes this process may still
/// allocate before jetsam kills it — the number that actually matters, and one
/// that varies hugely by device. `phys_footprint` is what jetsam measures.
nonisolated enum MemoryProbe {
    static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    static func availableBytes() -> Int { os_proc_available_memory() }

    /// Logs footprint and headroom at a named point on the crash trail.
    static func mark(_ label: String) {
        let used = Double(footprintBytes()) / 1_048_576
        let free = Double(availableBytes()) / 1_048_576
        GameLogger.mark(.lifecycle, String(
            format: "memory %@ — footprint %.0f MB, headroom %.0f MB", label, used, free
        ))
    }
}
