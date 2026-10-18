import Foundation
import Darwin

/// Foundation launches the worker in its own process group. Stop that entire
/// group so the stdio MCP child cannot survive the tunnel or its GUI host.
enum WorkerLifecycle {
    static func stop(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        if pid > 1, getpgid(pid) == pid, getpgrp() != pid {
            _ = kill(-pid, SIGTERM)
            // Let the client finish deleting its own health file before another
            // worker can start and publish a replacement at the same path.
            let deadline = Date().addingTimeInterval(3)
            while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { _ = kill(-pid, SIGKILL) }
        } else {
            process.terminate()
        }
    }
}

/// launchctl sends SIGTERM, which does not call AppKit's termination delegate
/// by default. Dispatch it through normal app termination instead.
final class TerminationSignals {
    private var sources: [DispatchSourceSignal] = []
    init(queue: DispatchQueue = .main, handler: @escaping @Sendable () -> Void) {
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler(handler: handler)
            source.resume()
            sources.append(source)
        }
    }
    deinit { for source in sources { source.cancel() } }
}

/// A second copy must not start another worker for the same local installation.
final class HostLease {
    private var descriptor: Int32 = -1
    var isHeld: Bool { descriptor >= 0 }
    func acquire(at path: String) -> Bool {
        guard descriptor == -1 else { return false }
        let fd = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return false }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == geteuid(), info.st_mode & 0o077 == 0,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return false }
        descriptor = fd
        return true
    }
    deinit { if descriptor >= 0 { close(descriptor) } }
}
