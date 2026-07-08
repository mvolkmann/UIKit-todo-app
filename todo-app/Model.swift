import Foundation

// Groups the app's shared data types under one namespace.
enum Model {
    // Represents the priority choices shown in the task editor.
    // Conforming to CaseIterable enables using Priority.allCases
    // to access the priorities like an array.
    enum Priority: String, Codable, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
    }

    struct TodoTask: Codable, Equatable {
        var description: String
        var dueDate: Date
        var priority: Priority
        var isComplete: Bool
    }

    // Handles saving and loading tasks from
    // a JSON file in the app's Documents directory.
    class TodoStore {
        private let fileURL: URL

        // Sets the fileURL property.
        init(fileManager: FileManager = .default) {
            let documentsDirectory = fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]
            fileURL = documentsDirectory.appendingPathComponent("tasks.json")
        }

        // Reads JSON from fileURL and decodes into a TodoTask array.
        func loadTasks() throws -> [TodoTask] {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([TodoTask].self, from: data)
        }

        // Encodes a TodoTask array as JSON and writes it to the fileURL.
        // Doing this atomically avoids partial saves.
        func saveTasks(_ tasks: [TodoTask]) throws {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: fileURL, options: [.atomic])
        }
    }
}
