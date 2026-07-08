import UIKit

struct TodoTask: Codable, Equatable {
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

    func loadTasks() -> [TodoTask] {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([TodoTask].self, from: data)
        } catch {
            return []
        }
    }

    func saveTasks(_ tasks: [TodoTask]) {
        do {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure(
                "Unable to save tasks: \(error.localizedDescription)"
            )
        }
    }
}

final class ViewController: UIViewController {
    @IBOutlet weak var tableView: UITableView!

    private let store = TodoStore()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var tasks: [TodoTask] = [] {
        didSet {
            store.saveTasks(tasks)
        }
    }

    override var isEditing: Bool {
        didSet {
            tableView.setEditing(isEditing, animated: true)
            navigationItem.leftBarButtonItem?
                .title = isEditing ? "Done" : "Edit"
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tasks = store.loadTasks()
    }

    @objc func toggleEditing() {
        isEditing.toggle()
    }

    @objc func addTask() {
        presentTaskEditor(title: "New Task", task: nil) { [weak self] task in
            guard let self else { return }
            tasks.append(task)
            tableView.insertRows(
                at: [IndexPath(row: tasks.count - 1, section: 0)],
                with: .automatic
            )
        }
    }

    private func presentTaskEditor(
        title: String,
        task: TodoTask?,
        completion: @escaping (TodoTask) -> Void
    ) {
        let editor = storyboard?.instantiateViewController(
            withIdentifier: "TaskEditorViewController"
        ) as? TaskEditorViewController

        guard let editor else { return }
        editor.title = title
        editor.task = task
        editor.onSave = completion

        let navigationController = UINavigationController(rootViewController: editor)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true)
    }

    private func confirmDeleteTask(at indexPath: IndexPath) {
        let task = tasks[indexPath.row]
        let alert = UIAlertController(
            title: "Delete Task?",
            message: "Delete \"\(task.description)\"?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(
            title: "Delete",
            style: .destructive
        ) { [weak self] _ in
            self?.deleteTask(at: indexPath)
        })
        present(alert, animated: true)
    }

    private func deleteTask(at indexPath: IndexPath) {
        tasks.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    private func toggleCompletion(at indexPath: IndexPath) {
        tasks[indexPath.row].isComplete.toggle()
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }

    private func editTask(at indexPath: IndexPath) {
        presentTaskEditor(
            title: "Edit Task",
            task: tasks[indexPath.row]
        ) { [weak self] updatedTask in
            self?.tasks[indexPath.row] = updatedTask
            self?.tableView.reloadRows(at: [indexPath], with: .automatic)
        }
    }

    private func configure(_ cell: UITableViewCell, with task: TodoTask) {
        var content = UIListContentConfiguration.subtitleCell()
        content.text = task.description
        content.secondaryText =
            "Due \(dateFormatter.string(from: task.dueDate)) • \(task.priority.rawValue) priority"
        content.textProperties.color = task.isComplete ? .secondaryLabel : .label
        content.secondaryTextProperties.color = color(for: task.priority)
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 8,
            trailing: 16
        )
        cell.contentConfiguration = content
        cell.accessoryType = task.isComplete ? .checkmark : .none
        cell.selectionStyle = .default
    }

    private func color(for priority: TodoTask.Priority) -> UIColor {
        switch priority {
        case .low:
            return .systemGreen
        case .medium:
            return .systemOrange
        case .high:
            return .systemRed
        }
    }
}

extension ViewController: UITableViewDataSource {
    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        tasks.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "TaskCell",
            for: indexPath
        )
        configure(cell, with: tasks[indexPath.row])
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        canEditRowAt indexPath: IndexPath
    ) -> Bool {
        true
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        if editingStyle == .delete {
            confirmDeleteTask(at: indexPath)
        }
    }
}

extension ViewController: UITableViewDelegate {
    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)

        if isEditing {
            editTask(at: indexPath)
        } else {
            toggleCompletion(at: indexPath)
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(
            style: .destructive,
            title: nil
        ) { [weak self] _, _, completion in
            self?.confirmDeleteTask(at: indexPath)
            completion(false)
        }
        deleteAction.image = UIImage(systemName: "trash")

        let cancelAction = UIContextualAction(
            style: .normal,
            title: "Cancel"
        ) { _, _, completion in
            completion(false)
        }
        cancelAction.backgroundColor = .systemGray

        return UISwipeActionsConfiguration(actions: [
            deleteAction,
            cancelAction
        ])
    }
}

final class TaskEditorViewController: UIViewController {
    @IBOutlet weak var descriptionField: UITextField!
    @IBOutlet weak var dueDatePicker: UIDatePicker!
    @IBOutlet weak var priorityControl: UISegmentedControl!

    var task: TodoTask?
    var onSave: ((TodoTask) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        descriptionField.delegate = self
        dueDatePicker.preferredDatePickerStyle = .compact
        populateFields()
    }

    private func populateFields() {
        guard let task else { return }
        descriptionField.text = task.description
        dueDatePicker.date = task.dueDate
        priorityControl.selectedSegmentIndex = TodoTask.Priority.allCases
            .firstIndex(of: task.priority) ?? 0
    }

    @objc func cancel() {
        dismiss(animated: true)
    }

    @objc func save() {
        let trimmedDescription = descriptionField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedDescription.isEmpty else {
            showMissingDescriptionAlert()
            return
        }

        let priority = TodoTask.Priority
            .allCases[priorityControl.selectedSegmentIndex]
        let savedTask = TodoTask(
            description: trimmedDescription,
            dueDate: dueDatePicker.date,
            priority: priority,
            isComplete: task?.isComplete ?? false
        )
        onSave?(savedTask)
        dismiss(animated: true)
    }

    private func showMissingDescriptionAlert() {
        let alert = UIAlertController(
            title: "Description Required",
            message: "Enter a task description before saving.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension TaskEditorViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
