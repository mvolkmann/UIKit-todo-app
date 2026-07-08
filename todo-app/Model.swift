import Foundation

enum Model {
    struct TodoTask: Codable, Equatable {
        // Making this CaseIterable enables using Priority.allCases.
        enum Priority: String, Codable, CaseIterable {
            case low = "Low"
            case medium = "Medium"
            case high = "High"
        }

        var description: String
        var dueDate: Date
        var priority: Priority
        var isComplete: Bool
    }

    final class TodoStore {
        private let fileURL: URL

        init(fileManager: FileManager = .default) {
            let documentsDirectory = fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]
            fileURL = documentsDirectory.appendingPathComponent("tasks.json")
        }

        func loadTasks() throws -> [TodoTask] {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([TodoTask].self, from: data)
        }

        func saveTasks(_ tasks: [TodoTask]) throws {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: fileURL, options: [.atomic])
        }
    }
}
