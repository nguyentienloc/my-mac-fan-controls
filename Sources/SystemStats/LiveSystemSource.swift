import Darwin
import Foundation

/// Đọc số liệu thật qua Mach, sysctl và thông tin ổ đĩa. Không cần quyền root.
public final class LiveSystemSource: SystemSource {
    private let host = mach_host_self()

    public init() {}

    public func cpuTicks() -> CPUTicks? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        // Mỗi nhân có CPU_STATE_MAX giá trị theo thứ tự USER, SYSTEM, IDLE, NICE; cộng dồn mọi nhân.
        // Bộ đếm tick theo nhân là 32-bit; khi nó tràn, mẫu đó cho nil (CPUUsage xử lý).
        var sums = [UInt64](repeating: 0, count: Int(CPU_STATE_MAX))
        for cpu in 0..<Int(cpuCount) {
            for state in 0..<Int(CPU_STATE_MAX) {
                sums[state] += UInt64(UInt32(bitPattern: info[cpu * Int(CPU_STATE_MAX) + state]))
            }
        }
        return CPUTicks(user: sums[Int(CPU_STATE_USER)], system: sums[Int(CPU_STATE_SYSTEM)],
                        idle: sums[Int(CPU_STATE_IDLE)], nice: sums[Int(CPU_STATE_NICE)])
    }

    public func memoryCounts() -> MemoryCounts? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return MemoryCounts(internalPages: UInt64(stats.internal_page_count),
                            purgeablePages: UInt64(stats.purgeable_count),
                            wiredPages: UInt64(stats.wire_count),
                            compressedPages: UInt64(stats.compressor_page_count))
    }

    public func pageSize() -> UInt64 {
        UInt64(vm_kernel_page_size)
    }

    public func physicalMemory() -> UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// 0 nếu đọc lỗi (được hiểu là "bình thường").
    public func memoryPressureLevel() -> Int32 {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return 0 }
        return level
    }

    public func diskCapacity() -> (free: UInt64, total: UInt64)? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity,
              free >= 0, total > 0 else { return nil }
        return (free: UInt64(free), total: UInt64(total))
    }

    /// Bộ đếm byte 64-bit của card Wi-Fi/Ethernet (`en*`) đang UP, không loopback. Nguồn IFMIB_IFDATA cho
    /// số đầy đủ 64-bit; NET_RT_IFLIST2 thì bị cắt còn 32-bit và làm tròn 1 KB khi không có quyền root.
    public func interfaceCounters() -> [String: InterfaceCounters] {
        guard let list = if_nameindex() else { return [:] }
        defer { if_freenameindex(list) }

        var counters: [String: InterfaceCounters] = [:]
        var index = 0
        while list[index].if_index != 0 {
            defer { index += 1 }
            guard let namePointer = list[index].if_name else { continue }
            let name = String(cString: namePointer)
            guard NetworkStats.isCounted(name: name),
                  let data = ifmibData(interfaceIndex: list[index].if_index) else { continue }
            let flags = data.ifmd_flags
            guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            counters[name] = InterfaceCounters(received: data.ifmd_data.ifi_ibytes,
                                               sent: data.ifmd_data.ifi_obytes)
        }
        return counters
    }

    /// Đọc `ifmibdata` (cờ và bộ đếm 64-bit) của một card theo chỉ số; `nil` nếu sysctl lỗi.
    private func ifmibData(interfaceIndex: UInt32) -> ifmibdata? {
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(interfaceIndex), IFDATA_GENERAL]
        var data = ifmibdata()
        var size = MemoryLayout<ifmibdata>.size
        guard sysctl(&mib, UInt32(mib.count), &data, &size, nil, 0) == 0 else { return nil }
        return data
    }
}
