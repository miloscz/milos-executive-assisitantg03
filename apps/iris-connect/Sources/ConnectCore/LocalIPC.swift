import Foundation
import Darwin
import Security

/// Business JSON only. This transport has no credential, URL, header or script API.
public enum LocalIPC {
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Iris Connect")
    }
    public static var authSocketPath: String { directory.appendingPathComponent("auth.sock").path }
    public static var socketPath: String { directory.appendingPathComponent("read.sock").path }

    public static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { throw ReadFailure.policyDenied }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { storage in
            storage.initializeMemory(as: UInt8.self, repeating: 0)
            storage.copyBytes(from: path.utf8)
        }
        return address
    }

    public static func prepare(_ fd: Int32, timeout: Int = 5) {
        var noPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout.size(ofValue: noPipe)))
        var time = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &time, socklen_t(MemoryLayout.size(ofValue: time)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &time, socklen_t(MemoryLayout.size(ofValue: time)))
    }

    public static func send(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw ReadFailure.transport }; offset += n
            }
        }
    }

    public static func receive(_ count: Int, fd: Int32) throws -> Data {
        guard count >= 0, count <= 52_428_800 else { throw ReadFailure.responseTooLarge }
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let n = Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw ReadFailure.transport }; offset += n
            }
        }
        return data
    }

    public static func sendFrame(_ data: Data, fd: Int32) throws {
        guard data.count <= 52_428_800 else { throw ReadFailure.responseTooLarge }
        var length = UInt32(data.count).bigEndian
        try send(withUnsafeBytes(of: &length) { Data($0) }, fd: fd)
        try send(data, fd: fd)
    }

    public static func receiveFrame(fd: Int32, maximum: Int) throws -> Data {
        let header = try receive(4, fd: fd)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= maximum else { throw ReadFailure.responseTooLarge }
        return try receive(Int(length), fd: fd)
    }

    /// Audit token binds the socket to a process incarnation, avoiding PID reuse.
    public static func peerCode(fd: Int32) throws -> SecCode {
        var uid: uid_t = 0; var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid() else { throw ReadFailure.pairingRequired }
        var audit = audit_token_t(); var length = socklen_t(MemoryLayout.size(ofValue: audit))
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &audit, &length) == 0,
              length == MemoryLayout.size(ofValue: audit) else { throw ReadFailure.pairingRequired }
        let data = withUnsafeBytes(of: &audit) { Data($0) }
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit as String: data] as CFDictionary, [], &code) == errSecSuccess,
              let code else { throw ReadFailure.pairingRequired }
        return code
    }

    public static func staticCode(_ url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { throw ReadFailure.pairingRequired }
        return code
    }

    public static func codeHash(_ code: SecStaticCode) throws -> String {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any], let hash = dict[kSecCodeInfoUnique as String] as? Data,
              let flags = dict[kSecCodeInfoFlags as String] as? UInt32, flags & 0x10000 != 0 else { throw ReadFailure.pairingRequired }
        let ents = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        for name in ["com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation",
                     "com.apple.security.cs.allow-dyld-environment-variables", "com.apple.security.cs.allow-unsigned-executable-memory"] {
            if ents[name] as? Bool == true { throw ReadFailure.pairingRequired }
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    public static func requirePeer(fd: Int32, hash: String) throws {
        let code = try peerCode(fd: fd)
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("cdhash H\"\(hash)\"" as CFString, [], &requirement) == errSecSuccess,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else { throw ReadFailure.pairingRequired }
    }
}
