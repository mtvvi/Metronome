import XCTest
@testable import PlayerApp

final class RealtimePCMBufferTests: XCTestCase {
    func testSPSCRingWrapsAndPreservesFIFOOrder() throws {
        let buffer = try XCTUnwrap(RealtimePCMBufferCreate(4))
        defer { RealtimePCMBufferDestroy(buffer) }
        var first = [Float](arrayLiteral: 1, 2, 3)
        let firstWritten = first.withUnsafeBufferPointer {
            RealtimePCMBufferWrite(buffer, $0.baseAddress, $0.count)
        }
        XCTAssertEqual(firstWritten, 3)
        var output = [Float](repeating: 0, count: 2)
        let firstRead = output.withUnsafeMutableBufferPointer {
            RealtimePCMBufferRead(buffer, $0.baseAddress, $0.count)
        }
        XCTAssertEqual(firstRead, 2)
        XCTAssertEqual(output, [1, 2])

        var second = [Float](arrayLiteral: 4, 5, 6)
        let secondWritten = second.withUnsafeBufferPointer {
            RealtimePCMBufferWrite(buffer, $0.baseAddress, $0.count)
        }
        XCTAssertEqual(secondWritten, 3)
        output = [Float](repeating: 0, count: 4)
        let secondRead = output.withUnsafeMutableBufferPointer {
            RealtimePCMBufferRead(buffer, $0.baseAddress, $0.count)
        }
        XCTAssertEqual(secondRead, 4)
        XCTAssertEqual(output, [3, 4, 5, 6])
    }

    func testOverflowDropsNewestSamplesWithoutOverwritingUnreadAudio() throws {
        let buffer = try XCTUnwrap(RealtimePCMBufferCreate(3))
        defer { RealtimePCMBufferDestroy(buffer) }
        var samples = [Float](arrayLiteral: 1, 2, 3, 4, 5)

        let written = samples.withUnsafeBufferPointer {
            RealtimePCMBufferWrite(buffer, $0.baseAddress, $0.count)
        }
        XCTAssertEqual(written, 3)
        XCTAssertEqual(RealtimePCMBufferAvailableToRead(buffer), 3)
        var output = [Float](repeating: 0, count: 3)
        let read = output.withUnsafeMutableBufferPointer {
            RealtimePCMBufferRead(buffer, $0.baseAddress, $0.count)
        }
        XCTAssertEqual(read, 3)
        XCTAssertEqual(output, [1, 2, 3])
    }

    func testResetAndDestroyAreDeterministic() throws {
        let buffer = try XCTUnwrap(RealtimePCMBufferCreate(8))
        var samples = [Float](repeating: 0.5, count: 8)
        _ = samples.withUnsafeBufferPointer {
            RealtimePCMBufferWrite(buffer, $0.baseAddress, $0.count)
        }
        RealtimePCMBufferReset(buffer)
        XCTAssertEqual(RealtimePCMBufferAvailableToRead(buffer), 0)
        RealtimePCMBufferDestroy(buffer)
    }
}
