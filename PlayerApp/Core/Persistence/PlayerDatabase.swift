import Foundation
import GRDB

final class PlayerDatabase: @unchecked Sendable {
    private let queue: DatabaseQueue

    init(queue: DatabaseQueue) throws {
        self.queue = queue
        try DatabaseMigrations.makeMigrator().migrate(queue)
    }

    static func inMemory() throws -> PlayerDatabase {
        try PlayerDatabase(queue: DatabaseQueue())
    }

    static func open(at path: String) throws -> PlayerDatabase {
        try PlayerDatabase(queue: DatabaseQueue(path: path))
    }

    func read<Value>(_ block: (Database) throws -> Value) throws -> Value {
        try queue.read(block)
    }

    func write<Value>(_ block: (Database) throws -> Value) throws -> Value {
        try queue.write(block)
    }
}
