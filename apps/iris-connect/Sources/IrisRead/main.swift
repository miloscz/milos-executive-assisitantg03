import Foundation
import Darwin
import ConnectCore

// No Keychain dependency. Only bounded business operations and fixed diagnostics.
do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 1 || arguments.count == 3 else { throw ReadFailure.policyDenied }
    let request = ReadRequest(operation: arguments[0], dateFrom: arguments.count == 3 ? arguments[1] : nil,
                              dateTo: arguments.count == 3 ? arguments[2] : nil)
    let payload = try JSONEncoder().encode(request)
    _ = try ReadRequest.parse(payload)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw ReadFailure.transport }
    defer { close(fd) }
    LocalIPC.prepare(fd, timeout: 550)
    var address = try LocalIPC.address(LocalIPC.socketPath)
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0 else { throw ReadFailure.transport }
    // Mutual verification: a fake socket must not impersonate the bundled native app.
    let app = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        .deletingLastPathComponent().appendingPathComponent("IrisConnect")
    try LocalIPC.requirePeer(fd: fd, hash: LocalIPC.codeHash(LocalIPC.staticCode(app)))
    try LocalIPC.sendFrame(payload, fd: fd)
    let result = try LocalIPC.receiveFrame(fd: fd, maximum: 52_428_800)
    FileHandle.standardOutput.write(result); FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    let code = (error as? ReadFailure ?? .transport).rawValue
    FileHandle.standardOutput.write(Data("{\"ok\":false,\"error\":\"\(code)\"}\n".utf8))
    exit(1)
}
