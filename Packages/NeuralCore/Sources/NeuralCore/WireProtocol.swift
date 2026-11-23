import Foundation

/// Fixed binary protocol shared by Mac Streamer and (later) ESP32 firmware.
public enum WireProtocol {
    public static let magic: UInt32 = 0x4E524C31 // "NRL1"
    public static let defaultPort: UInt16 = 9000
    public static let defaultChannelCount: Int = 64
    public static let defaultSampleRate: Double = 10_000

    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        public static let acceptIntent = Flags(rawValue: 1 << 0)
        public static let rejectIntent = Flags(rawValue: 1 << 1)
    }

    /// Packed header preceding Int16 channel samples.
    public struct Header {
        public var magic: UInt32
        public var seq: UInt32
        public var hostTimeNs: UInt64
        public var channelCount: UInt16
        public var flags: UInt16

        public static let byteCount = 20

        public init(
            magic: UInt32 = WireProtocol.magic,
            seq: UInt32,
            hostTimeNs: UInt64,
            channelCount: UInt16,
            flags: UInt16 = 0
        ) {
            self.magic = magic
            self.seq = seq
            self.hostTimeNs = hostTimeNs
            self.channelCount = channelCount
            self.flags = flags
        }

        public func encode(into buffer: inout [UInt8], at offset: Int = 0) {
            precondition(buffer.count >= offset + Self.byteCount)
            writeUInt32(magic, into: &buffer, at: offset)
            writeUInt32(seq, into: &buffer, at: offset + 4)
            writeUInt64(hostTimeNs, into: &buffer, at: offset + 8)
            writeUInt16(channelCount, into: &buffer, at: offset + 16)
            writeUInt16(flags, into: &buffer, at: offset + 18)
        }

        public static func decode(from bytes: UnsafeRawBufferPointer) -> Header? {
            guard bytes.count >= byteCount else { return nil }
            let magic = readUInt32(bytes, at: 0)
            guard magic == WireProtocol.magic else { return nil }
            return Header(
                magic: magic,
                seq: readUInt32(bytes, at: 4),
                hostTimeNs: readUInt64(bytes, at: 8),
                channelCount: readUInt16(bytes, at: 16),
                flags: readUInt16(bytes, at: 18)
            )
        }
    }

    public static func packetByteCount(channels: Int) -> Int {
        Header.byteCount + channels * MemoryLayout<Int16>.size
    }
}

// MARK: - Little-endian helpers

@inline(__always)
private func writeUInt16(_ value: UInt16, into buffer: inout [UInt8], at offset: Int) {
    var le = value.littleEndian
    withUnsafeBytes(of: &le) { raw in
        for i in 0..<2 { buffer[offset + i] = raw[i] }
    }
}

@inline(__always)
private func writeUInt32(_ value: UInt32, into buffer: inout [UInt8], at offset: Int) {
    var le = value.littleEndian
    withUnsafeBytes(of: &le) { raw in
        for i in 0..<4 { buffer[offset + i] = raw[i] }
    }
}

@inline(__always)
private func writeUInt64(_ value: UInt64, into buffer: inout [UInt8], at offset: Int) {
    var le = value.littleEndian
    withUnsafeBytes(of: &le) { raw in
        for i in 0..<8 { buffer[offset + i] = raw[i] }
    }
}

@inline(__always)
private func readUInt16(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt16 {
    var value: UInt16 = 0
    withUnsafeMutableBytes(of: &value) { dest in
        dest.copyBytes(from: UnsafeRawBufferPointer(rebasing: bytes[offset..<offset + 2]))
    }
    return UInt16(littleEndian: value)
}

@inline(__always)
private func readUInt32(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt32 {
    var value: UInt32 = 0
    withUnsafeMutableBytes(of: &value) { dest in
        dest.copyBytes(from: UnsafeRawBufferPointer(rebasing: bytes[offset..<offset + 4]))
    }
    return UInt32(littleEndian: value)
}

@inline(__always)
private func readUInt64(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt64 {
    var value: UInt64 = 0
    withUnsafeMutableBytes(of: &value) { dest in
        dest.copyBytes(from: UnsafeRawBufferPointer(rebasing: bytes[offset..<offset + 8]))
    }
    return UInt64(littleEndian: value)
}
