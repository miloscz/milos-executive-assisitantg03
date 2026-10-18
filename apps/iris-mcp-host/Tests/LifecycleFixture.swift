import Foundation
import Darwin

@main
struct LifecycleFixture {
    static func main() throws {
        let lease = HostLease()
        guard CommandLine.arguments.count == 2, lease.acquire(at: CommandLine.arguments[1]) else { exit(2) }
        let second = HostLease()
        guard !second.acquire(at: CommandLine.arguments[1]) else { exit(3) }
        let worker = Process(), output = Pipe()
        worker.executableURL = URL(fileURLWithPath: "/bin/sh")
        worker.arguments = ["-c", "sleep 120 & echo $!; wait"]
        worker.standardOutput = output; worker.standardError = FileHandle.nullDevice
        let signals = TerminationSignals(queue: .global()) {
            WorkerLifecycle.stop(worker)
            worker.waitUntilExit()
            exit(0)
        }
        try worker.run()
        let bytes = output.fileHandleForReading.availableData
        guard let text = String(data: bytes, encoding: .utf8), let child = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              getpgid(child) == worker.processIdentifier, getpgid(worker.processIdentifier) == worker.processIdentifier else { exit(4) }
        print("\(worker.processIdentifier) \(child)")
        fflush(stdout)
        withExtendedLifetime((lease, second, signals)) { dispatchMain() }
    }
}
