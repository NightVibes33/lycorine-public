import Foundation
import Darwin

/// Sends ONLY the public, unauthenticated RemotePairing hello.
/// Does not send a pairing file, perform a pair-setup, or contact Apple TSS.
/// Frames match idevice v0.1.68's RpPairingSocket and attemptPairVerify.
enum LycorineRemotePairingProbe {
    private static let magic = Array("RPPairing".utf8)

    static func test(host: String, port: UInt16) -> String {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = CFSwapInt16HostToBig(port)
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            return "Stage 0: invalid endpoint IPv4"
        }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return "Stage 0: cannot open TCP socket" }
        defer { close(fd) }

        // Bounded connect; unlike repeated RSD retries, never mutates a pairing record.
        let oldFlags = fcntl(fd, F_GETFL, 0)
        guard oldFlags >= 0, fcntl(fd, F_SETFL, oldFlags | O_NONBLOCK) == 0 else {
            return "Stage 0: cannot configure TCP socket"
        }
        let result = withUnsafePointer(to: &address) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                Darwin.connect(fd, sock, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 {
            guard errno == EINPROGRESS else {
                return "Stage 1: TCP connect failed (\(String(cString: strerror(errno))))"
            }
            var event = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let count = poll(&event, 1, 2500)
            if count == 0 { return "Stage 1: TCP connect timed out" }
            if count < 0 { return "Stage 1: TCP connect poll failed" }
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else {
                return "Stage 1: TCP status could not be checked"
            }
            if error != 0 {
                return "Stage 1: TCP connect failed (\(String(cString: strerror(error))))"
            }
        }
        guard fcntl(fd, F_SETFL, oldFlags) == 0 else {
            return "Stage 1: cannot restore socket mode"
        }
        var deadline = timeval(tv_sec: 3, tv_usec: 0)
        withUnsafePointer(to: &deadline) { p in
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, p, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, p, socklen_t(MemoryLayout<timeval>.size))
        }

        let plain: [String: Any] = [
            "request": ["_0": ["handshake": ["_0": [
                "hostOptions": ["attemptPairVerify": true],
                "wireProtocolVersion": 19
            ]]]]
        ]
        let packet: [String: Any] = [
            "message": ["plain": ["_0": plain]],
            "originatedBy": "host",
            "sequenceNumber": 0
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: packet, options: []),
              json.count > 0, json.count <= 4096 else {
            return "Stage 2: cannot serialize RemotePairing hello"
        }
        let length = UInt16(json.count)
        var frame = magic
        frame.append(UInt8(length >> 8))
        frame.append(UInt8(length & 0xff))
        frame.append(contentsOf: json)

        let sent: Bool = frame.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return false }
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.send(fd, base.advanced(by: offset), bytes.count - offset, 0)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
        guard sent else {
            return "Stage 2: TCP connected, but RemotePairing hello could not be sent"
        }
        func readExactly(_ count: Int) -> [UInt8]? {
            var bytes = [UInt8](repeating: 0, count: count)
            var offset = 0
            while offset < count {
                let n = bytes.withUnsafeMutableBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return -1 }
                    return Darwin.recv(fd, base.advanced(by: offset), count - offset, 0)
                }
                if n <= 0 { return nil }
                offset += n
            }
            return bytes
        }
        guard let header = readExactly(magic.count + 2) else {
            return "Stage 3: TCP connected and hello sent; peer closed, reset or timed out before RemotePairing response. Endpoint/protocol mismatch is possible; pairing keys have not been tested."
        }
        guard Array(header.prefix(magic.count)) == magic else {
            return "Stage 3: peer replied, but not with RemotePairing frame magic. Wrong protocol/service is likely."
        }
        let responseLength = Int(header[magic.count]) * 256 + Int(header[magic.count + 1])
        guard responseLength > 0 && responseLength <= 16384,
              let payload = readExactly(responseLength) else {
            return "Stage 3: RemotePairing frame header found, but payload is invalid or timed out."
        }
        guard let root = (try? JSONSerialization.jsonObject(with: Data(payload))) as? [String: Any],
              let envelope = root["message"] as? [String: Any],
              let rawPlain = envelope["plain"] as? [String: Any],
              let message = rawPlain["_0"] as? [String: Any],
              let response = message["response"] as? [String: Any],
              let layer = response["_1"] as? [String: Any],
              layer["handshake"] != nil else {
            return "Stage 3: RemotePairing packet received, but initial handshake structure was unexpected."
        }
        return "Stage 3: Valid RemotePairing hello response received at \(host):\(port). Next failure, if any, is during pairing verification, pairing setup, or tunnel creation. No credentials sent."
    }
}
