import Foundation

/// Lossless, platform-independent persistence for per-pixel region identifiers.
public enum RegionMap {
    public enum CodingError: Error, Equatable {
        case invalidDimensions
        case invalidData
    }

    private static let magic: [UInt8] = [0x50, 0x42, 0x4E, 0x52] // PBNR
    private static let headerSize = 12

    public static func encode(regionIds: [Int], width: Int, height: Int) throws -> Data {
        guard width >= 0, height >= 0,
              width <= Int(UInt32.max), height <= Int(UInt32.max),
              width.multipliedReportingOverflow(by: height).overflow == false,
              regionIds.count == width * height,
              regionIds.allSatisfy({ $0 >= 0 && UInt64($0) <= UInt64(UInt32.max) })
        else { throw CodingError.invalidDimensions }

        var data = Data(magic)
        append(UInt32(width), to: &data)
        append(UInt32(height), to: &data)
        for id in regionIds {
            append(UInt32(id), to: &data)
        }
        return data
    }

    public static func decode(_ data: Data, expectedWidth: Int, expectedHeight: Int) throws -> [Int] {
        guard expectedWidth >= 0, expectedHeight >= 0,
              expectedWidth <= Int(UInt32.max), expectedHeight <= Int(UInt32.max),
              expectedWidth.multipliedReportingOverflow(by: expectedHeight).overflow == false,
              data.count >= headerSize,
              Array(data.prefix(4)) == magic,
              readUInt32(data, offset: 4) == UInt32(expectedWidth),
              readUInt32(data, offset: 8) == UInt32(expectedHeight)
        else { throw CodingError.invalidData }

        let count = expectedWidth * expectedHeight
        guard data.count == headerSize + count * MemoryLayout<UInt32>.size else {
            throw CodingError.invalidData
        }
        return (0..<count).map {
            Int(readUInt32(data, offset: headerSize + $0 * MemoryLayout<UInt32>.size))
        }
    }

    public static func regionId(
        atX x: Int,
        y: Int,
        regionIds: [Int],
        width: Int,
        height: Int
    ) -> Int? {
        guard x >= 0, x < width, y >= 0, y < height,
              regionIds.count == width * height else { return nil }
        return regionIds[y * width + x]
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        data.withUnsafeBytes { bytes in
            let value = bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            return UInt32(littleEndian: value)
        }
    }
}
