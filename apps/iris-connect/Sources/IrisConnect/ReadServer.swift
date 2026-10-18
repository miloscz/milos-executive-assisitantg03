import Foundation
import Darwin
import ConnectCore

/// No TCP listener. Socket permissions and audit-token code identity are both required.
final class ReadServer {
    private let hash: String
    private let path: String
    private let validate: (Data) throws -> Void
    private let handler: @MainActor (Data) async -> Data
    private var listener: Int32 = -1
    private let slots = DispatchSemaphore(value: 2)

    init(approvedHelperHash: String, path: String = LocalIPC.socketPath,
         validate: @escaping (Data) throws -> Void = { _ = try ReadRequest.parse($0) }, handler: @escaping @MainActor (Data) async -> Data) {
        hash = approvedHelperHash; self.path = path; self.validate = validate; self.handler = handler
    }

    func start() throws {
        try FileManager.default.createDirectory(at: LocalIPC.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: LocalIPC.directory.path)
        // Never displace another live listener. A stale endpoint is removed only after connection fails.
        if FileManager.default.fileExists(atPath: path) {
            let probe = socket(AF_UNIX, SOCK_STREAM, 0); defer { close(probe) }
            var address = try LocalIPC.address(path)
            let live = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            } }
            guard !live else { throw ReadFailure.pairingRequired }
            try FileManager.default.removeItem(atPath: path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ReadFailure.transport }
        var address = try LocalIPC.address(path)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        } }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 4) == 0 else { close(fd); throw ReadFailure.transport }
        listener = fd
        DispatchQueue.global(qos: .utility).async { [self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { return }
                LocalIPC.prepare(client)
                guard slots.wait(timeout: .now()) == .success else { close(client); continue }
                DispatchQueue.global(qos: .utility).async { [self] in
                    defer { close(client); slots.signal() }
                    do {
                        try LocalIPC.requirePeer(fd: client, hash: hash)
                        let input = try LocalIPC.receiveFrame(fd: client, maximum: 4096)
                        try validate(input)
                        let done = DispatchSemaphore(value: 0)
                        var output = Data()
                        Task { @MainActor in output = await handler(input); done.signal() }
                        done.wait()
                        try LocalIPC.sendFrame(output, fd: client)
                    } catch {
                        let code = (error as? ReadFailure ?? .transport).rawValue
                        try? LocalIPC.sendFrame(Data("{\"ok\":false,\"error\":\"\(code)\"}".utf8), fd: client)
                    }
                }
            }
        }
    }

    func stop() {
        if listener >= 0 { shutdown(listener, SHUT_RDWR); close(listener); listener = -1; unlink(path) }
    }
    deinit { stop() }
}
