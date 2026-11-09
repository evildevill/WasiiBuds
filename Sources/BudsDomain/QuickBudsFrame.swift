import Foundation

/// Parser for a complete, unsliced protocol frame (PROTOCOL.md §2).
public struct WasiiBudsFrame: Equatable, Sendable {
    public let command: UInt16
    public let sequence: UInt8
    public let payload: [UInt8]

    public enum ParseError: Error, Equatable {
        case malformed
        case slicedFrame
    }

    public init(command: UInt16, sequence: UInt8, payload: [UInt8]) {
        self.command = command
        self.sequence = sequence
        self.payload = payload
    }

    public func encoded() -> [UInt8] {
        let length = 7 + payload.count
        precondition(length <= 4096)
        var output: [UInt8] = [0xAA]
        var remaining = length
        repeat {
            let byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            output.append(remaining == 0 ? byte : byte | 0x80)
        } while remaining != 0
        output += [0, 0, UInt8(command & 0xFF), UInt8(command >> 8), sequence,
                   UInt8(payload.count & 0xFF), UInt8((payload.count >> 8) & 0xFF)]
        output += payload
        return output
    }

    public static func parse(_ bytes: [UInt8]) throws -> Self {
        guard bytes.first == 0xAA else { throw ParseError.malformed }
        var length = 0
        var shift = 0
        var cursor = 1
        var terminated = false
        for _ in 0..<3 {
            guard cursor < bytes.count else { throw ParseError.malformed }
            let part = bytes[cursor]
            cursor += 1
            length |= Int(part & 0x7F) << shift
            if part & 0x80 == 0 {
                terminated = true
                break
            }
            shift += 7
        }
        guard terminated, length >= 7, length <= 4096,
              bytes.count == cursor + length,
              bytes[cursor + 1] == 0 else { throw ParseError.malformed }
        guard bytes[cursor] == 0 else { throw ParseError.slicedFrame }
        let header = cursor + 2
        let payloadLength = Int(bytes[header + 3]) | Int(bytes[header + 4]) << 8
        guard payloadLength == length - 7 else { throw ParseError.malformed }
        return Self(command: UInt16(bytes[header]) | UInt16(bytes[header + 1]) << 8,
                    sequence: bytes[header + 2],
                    payload: Array(bytes[(header + 5)..<bytes.count]))
    }
}

/// GATT notifications may split a frame at any byte. The protocol may also
/// divide a large message into numbered first, middle and last slices.
public struct WasiiBudsStream: Sendable {
    private var buffer: [UInt8] = []
    private var slices: [UInt8]?
    private var nextSliceNumber: UInt8 = 0

    public init() {}

    public mutating func append(_ bytes: [UInt8]) -> [WasiiBudsFrame] {
        buffer += bytes
        var messages: [WasiiBudsFrame] = []
        while !buffer.isEmpty {
            guard let start = buffer.firstIndex(of: 0xAA) else {
                buffer.removeAll()
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            var length = 0
            var shift = 0
            var cursor = 1
            var complete = false
            while cursor < buffer.count && cursor <= 3 {
                let byte = buffer[cursor]
                length |= Int(byte & 0x7F) << shift
                cursor += 1
                if byte & 0x80 == 0 { complete = true; break }
                shift += 7
            }
            if !complete {
                if buffer.count > 3 { buffer.removeFirst(); continue }
                break
            }
            guard buffer.count > cursor else { break }
            let kind = buffer[cursor]
            let isSlice = (1...3).contains(kind)
            guard length >= (isSlice ? 4 : 7), length <= 4096 else {
                buffer.removeFirst()
                slices = nil
                continue
            }
            let end = cursor + length
            guard buffer.count >= end else { break }
            if isSlice {
                if buffer[cursor + 1] == 0 {
                    let number = buffer[cursor + 2]
                    let data = Array(buffer[(cursor + 3)..<end])
                    if kind == 1, number == 0 {
                        slices = data
                        nextSliceNumber = 1
                    } else if (kind == 2 || kind == 3), number == nextSliceNumber,
                              let previous = slices, previous.count + data.count <= 4096 {
                        slices = previous + data
                        nextSliceNumber &+= 1
                        if kind == 3, let joined = slices, joined.count >= 5 {
                            let size = Int(joined[3]) | Int(joined[4]) << 8
                            if size <= joined.count - 5 {
                                messages.append(.init(command: UInt16(joined[0]) | UInt16(joined[1]) << 8,
                                                      sequence: joined[2],
                                                      payload: Array(joined[5..<(5 + size)])))
                            }
                            slices = nil
                        }
                    } else {
                        slices = nil
                    }
                } else {
                    slices = nil
                }
            } else if let message = try? WasiiBudsFrame.parse(Array(buffer[..<end])) {
                slices = nil
                messages.append(message)
            }
            buffer.removeFirst(end)
        }
        return messages
    }
}
