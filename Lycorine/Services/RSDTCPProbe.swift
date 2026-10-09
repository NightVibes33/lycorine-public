import Foundation
import Darwin

/// One short TCP connect only. Does not exchange pairing credentials or TSS data.
/// A listening socket is not evidence that the peer accepts this pairing file.
enum LycorineTCPProbe {
    static func check(host: String, port: UInt16) -> String {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(port)
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            return "Invalid IPv4 endpoint \(host)"
        }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return "Could not create TCP socket: \(errno)" }
        defer { close(fd) }

        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            return "Could not set TCP nonblocking mode"
        }

        let status = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                Darwin.connect(fd, pointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if status == 0 {
            return "TCP connected to \(host):\(port). Pairing acceptance is still unknown."
        }
        let firstError = errno
        guard firstError == EINPROGRESS else {
            return "TCP refused/failed at \(host):\(port): \(String(cString: strerror(firstError)))"
        }
        var event = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&event, 1, 2500)
        if ready == 0 { return "TCP timeout at \(host):\(port) (2.5 seconds)" }
        if ready < 0 {
            return "TCP poll failed at \(host):\(port): \(String(cString: strerror(errno)))"
        }
        var socketError: Int32 = 0
        var errorLength = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &errorLength) == 0 else {
            return "TCP socket status unavailable at \(host):\(port)"
        }
        if socketError == 0 {
            return "TCP connected to \(host):\(port). Pairing acceptance is still unknown."
        }
        return "TCP failed at \(host):\(port): \(String(cString: strerror(socketError)))"
    }
}
