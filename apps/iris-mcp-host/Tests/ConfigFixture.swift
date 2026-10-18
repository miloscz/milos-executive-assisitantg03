import Foundation

// Test-only: generate the production YAML shape with fixed synthetic inputs.
@main struct ConfigFixture {
    static func main() {
        print(TunnelPolicy.config(
            id: "tunnel_0123456789abcdef0123456789abcdef",
            command: "/bin/bash '/synthetic/path with space/run-stdio.sh'"
        )!)
    }
}
