import Foundation
import Darwin
import ConnectCore

// Bundled signed helper. No Keychain reads and no credential/token parameters.
do {
    let args = Array(CommandLine.arguments.dropFirst())
    let request: AuthControlRequest
    switch args.first {
    case "status", "prepare":
        guard args.count == 1 else { throw AuthControlFailure.invalidRequest }
        request = AuthControlRequest(operation: args[0])
    case "noticeSent":
        guard args.count == 2, let notice = UUID(uuidString: args[1]) else { throw AuthControlFailure.invalidRequest }
        request = AuthControlRequest(operation: args[0], noticeID: notice)
    case "start":
        guard args.count == 4, let notice = UUID(uuidString: args[1]), let id = UUID(uuidString: args[2]),
              args[3] == "--direct-user-command" else { throw AuthControlFailure.invalidRequest }
        request = AuthControlRequest(operation: args[0], noticeID: notice, requestID: id, directUserCommand: true)
    default: throw AuthControlFailure.invalidRequest
    }
    let payload = try JSONEncoder().encode(request)
    _ = try AuthControlRequest.parse(payload)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw AuthControlFailure.unavailable }
    defer { close(fd) }; LocalIPC.prepare(fd)
    var address = try LocalIPC.address(LocalIPC.authSocketPath)
    let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    } }
    guard connected == 0 else { throw AuthControlFailure.unavailable }
    let native = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().appendingPathComponent("IrisConnect")
    try LocalIPC.requirePeer(fd: fd, hash: LocalIPC.codeHash(LocalIPC.staticCode(native)))
    try LocalIPC.sendFrame(payload, fd: fd)
    let output = try LocalIPC.receiveFrame(fd: fd, maximum: 8192)
    FileHandle.standardOutput.write(output); FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    let code = (error as? AuthControlFailure ?? .unavailable).rawValue
    FileHandle.standardOutput.write(Data("{\"ok\":false,\"error\":\"\(code)\"}\n".utf8)); exit(1)
}
