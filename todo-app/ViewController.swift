import UIKit
import UserNotifications

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

    private lazy var deleteCompletedButton = UIBarButtonItem(
        title: "Delete All Completed",
        style: .plain,
        target: self,
        action: #selector(deleteAllCompleted)
    )

    private let store = TodoStore()
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notifiedTaskIdentifiersKey = "notifiedDueTaskIdentifiers"
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var tasks: [TodoTask] = [] {
        didSet {
            store.saveTasks(tasks)
            updateRemainingTodosTitle()
            updateDeleteCompletedButtonState()
            notifyForDueTasks()
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
        notificationCenter.delegate = self
        configureToolbar()
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

    @objc func deleteAllCompleted() {
        guard tasks.contains(where: { $0.isComplete }) else { return }
        tasks.removeAll { $0.isComplete }
        tableView.reloadData()
    }

    private func configureToolbar() {
        let flexibleSpace = UIBarButtonItem(
            barButtonSystemItem: .flexibleSpace,
            target: nil,
            action: nil
        )
        toolbarItems = [flexibleSpace, deleteCompletedButton, flexibleSpace]
        navigationController?.setToolbarHidden(false, animated: false)
        updateDeleteCompletedButtonState()
    }

    private func updateDeleteCompletedButtonState() {
        deleteCompletedButton.isEnabled = tasks.contains { $0.isComplete }
    }

    private func updateRemainingTodosTitle() {
        let remainingCount = tasks.filter { !$0.isComplete }.count
        navigationItem.title = "\(remainingCount) of \(tasks.count) todos remaining"
    }

    private func notifyForDueTasks() {
        let dueTasks = tasks.filter { shouldNotify(for: $0) }
        let dueTaskIdentifiers = Set(dueTasks.map(notificationIdentifier(for:)))
        let defaults = UserDefaults.standard
        let notifiedIdentifiers = Set(
            defaults.stringArray(forKey: notifiedTaskIdentifiersKey) ?? []
        )
        let stillRelevantNotifiedIdentifiers = notifiedIdentifiers
            .intersection(dueTaskIdentifiers)
        let tasksToNotify = dueTasks.filter {
            !stillRelevantNotifiedIdentifiers.contains(notificationIdentifier(for: $0))
        }

        defaults.set(
            Array(stillRelevantNotifiedIdentifiers),
            forKey: notifiedTaskIdentifiersKey
        )

        guard !tasksToNotify.isEmpty else { return }

        requestNotificationAuthorizationIfNeeded { [weak self] isAuthorized in
            guard let self, isAuthorized else { return }

            var updatedIdentifiers = stillRelevantNotifiedIdentifiers
            for task in tasksToNotify {
                let identifier = notificationIdentifier(for: task)
                scheduleDueNotification(for: task, identifier: identifier)
                updatedIdentifiers.insert(identifier)
            }

            defaults.set(
                Array(updatedIdentifiers),
                forKey: notifiedTaskIdentifiersKey
            )
        }
    }

    private func shouldNotify(for task: TodoTask) -> Bool {
        !task.isComplete && Calendar.current.compare(
            task.dueDate,
            to: Date(),
            toGranularity: .day
        ) != .orderedDescending
    }

    private func requestNotificationAuthorizationIfNeeded(
        completion: @escaping (Bool) -> Void
    ) {
        notificationCenter.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .notDetermined:
                self?.notificationCenter.requestAuthorization(
                    options: [.alert, .sound]
                ) { isGranted, _ in
                    completion(isGranted)
                }
            case .denied:
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }

    private func scheduleDueNotification(
        for task: TodoTask,
        identifier: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Task Due"
        content.body = "\"\(task.description)\" is due \(dueStatusText(for: task))."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        notificationCenter.add(request)
    }

    private func dueStatusText(for task: TodoTask) -> String {
        Calendar.current.isDateInToday(task.dueDate) ? "today" : "in the past"
    }

    private func notificationIdentifier(for task: TodoTask) -> String {
        let rawIdentifier = "\(task.description)|\(task.dueDate.timeIntervalSince1970)|\(task.priority.rawValue)"
        let encodedIdentifier = Data(rawIdentifier.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "due-task-\(encodedIdentifier)"
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
            guard let self, tasks.indices.contains(indexPath.row) else { return }
            tasks[indexPath.row] = updatedTask
            tableView.reloadRows(at: [indexPath], with: .automatic)
        }
    }

    private func shareTask(at indexPath: IndexPath, from sourceView: UIView) {
        guard tasks.indices.contains(indexPath.row) else { return }

        let task = tasks[indexPath.row]
        let shareText = "\(task.description)\nDue \(dateFormatter.string(from: task.dueDate))\nPriority: \(task.priority.rawValue)"
        let activityController = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        activityController.popoverPresentationController?.sourceView = sourceView
        present(activityController, animated: true)
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
            return .systemBlue
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
            deleteTask(at: indexPath)
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
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let editAction = UIContextualAction(
            style: .normal,
            title: "Edit"
        ) { [weak self] _, _, completion in
            self?.editTask(at: indexPath)
            completion(true)
        }
        editAction.backgroundColor = .systemBlue

        let shareAction = UIContextualAction(
            style: .normal,
            title: nil
        ) { [weak self] _, sourceView, completion in
            self?.shareTask(at: indexPath, from: sourceView)
            completion(true)
        }
        shareAction.backgroundColor = .systemGreen
        shareAction.image = UIImage(systemName: "square.and.arrow.up")

        return UISwipeActionsConfiguration(actions: [editAction, shareAction])
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(
            style: .destructive,
            title: nil
        ) { [weak self] _, _, completion in
            self?.deleteTask(at: indexPath)
            completion(false)
        }
        deleteAction.image = UIImage(systemName: "trash")

        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

extension ViewController: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        completionHandler([.banner, .sound])
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
