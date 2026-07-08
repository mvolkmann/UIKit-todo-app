import UIKit
import UserNotifications

final class ViewController: UIViewController {
    @IBOutlet var tableView: UITableView!

    // Toolbar button used to remove every task that is marked complete.
    private lazy var deleteCompletedButton = UIBarButtonItem(
        title: "Delete All Completed",
        style: .plain,
        target: self,
        action: #selector(deleteAllCompleted)
    )

    private let store = Model.TodoStore()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    // These are used to send task data as a local notification.
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notifiedTaskIdentifiersKey = "notifiedDueTaskIdentifiers"

    // The table view is driven by this array.
    // Any change is immediately saved,
    // reflected in the navigation title and toolbar,
    // and checked for due alerts.
    private var tasks: [Model.TodoTask] = [] {
        didSet {
            do {
                try store.saveTasks(tasks)
            } catch {
                showSaveTasksErrorAlert(error)
            }

            updateRemainingTodosTitle()
            updateDeleteCompletedButtonState()
            notifyForDueTasks()
        }
    }

    // Keeps the table view's editing mode and
    // the navigation button title in sync.
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
        loadTasks()
    }

    // Loads saved tasks when the app opens.
    // If reading the saved tasks fails, an error dialog is displayed.
    private func loadTasks() {
        do {
            tasks = try store.loadTasks()
        } catch {
            showLoadTasksErrorAlert(error)
            tasks = []
        }
    }

    // This is called by storyboard action wiring, not directly from code.
    @objc func toggleEditing() {
        isEditing.toggle()
    }

    // Presents a task editor with no existing task
    // and inserts the saved task into the table.
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

    // Removes all completed items and refreshes the task table.
    @objc func deleteAllCompleted() {
        guard tasks.contains(where: { $0.isComplete }) else { return }
        tasks.removeAll { $0.isComplete }
        tableView.reloadData()
    }

    // Builds the bottom toolbar with the delete-completed button centered.
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

    // Updates whether the "Delete All Completed" button is enabled.
    private func updateDeleteCompletedButtonState() {
        deleteCompletedButton.isEnabled = tasks.contains { $0.isComplete }
    }

    // Shows progress in the navigation bar as completed tasks are toggled.
    private func updateRemainingTodosTitle() {
        let remainingCount = tasks.filter { !$0.isComplete }.count
        navigationItem
            .title = "\(remainingCount) of \(tasks.count) todos remaining"
    }

    // Finds incomplete tasks due today or earlier
    // and schedules one local notification per task.
    // UserDefaults tracks which due tasks already triggered
    // so updates do not repeat alerts.
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
            !stillRelevantNotifiedIdentifiers
                .contains(notificationIdentifier(for: $0))
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

    // A task notification should be generated only when
    // it is unfinished and its due date is not in the future.
    private func shouldNotify(for task: Model.TodoTask) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDay = calendar.startOfDay(for: task.dueDate)
        return !task.isComplete && dueDay <= today
    }

    // Checks the current notification permission
    // and asks the user only if needed.
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

    // Creates an immediate local notification describing which task is due.
    private func scheduleDueNotification(
        for task: Model.TodoTask,
        identifier: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Task Due"
        content
            .body =
            "\"\(task.description)\" is due \(dueStatusText(for: task))."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        notificationCenter.add(request)
    }

    private func dueStatusText(for task: Model.TodoTask) -> String {
        Calendar.current.isDateInToday(task.dueDate) ? "today" : "in the past"
    }

    // Builds a stable notification ID from task fields so the same due task is
    // not notified twice.
    private func notificationIdentifier(for task: Model.TodoTask) -> String {
        let rawIdentifier =
            "\(task.description)|\(task.dueDate.timeIntervalSince1970)|\(task.priority.rawValue)"
        let encodedIdentifier = Data(rawIdentifier.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "due-task-\(encodedIdentifier)"
    }

    // Opens the storyboard-based editor for either a new task or an existing
    // task.
    private func presentTaskEditor(
        title: String,
        task: Model.TodoTask?,
        completion: @escaping (Model.TodoTask) -> Void
    ) {
        let editor = storyboard?.instantiateViewController(
            withIdentifier: "TaskEditorViewController"
        ) as? TaskEditorViewController

        guard let editor else { return }
        editor.title = title
        editor.task = task
        editor.onSave = completion

        let navigationController =
            UINavigationController(rootViewController: editor)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true)
    }

    // Deletes the selected task from both the model array and the table view.
    private func deleteTask(at indexPath: IndexPath) {
        tasks.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    // Toggles the checkmark state for a task when the user taps its row outside
    // edit mode.
    private func toggleCompletion(at indexPath: IndexPath) {
        tasks[indexPath.row].isComplete.toggle()
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }

    // Reuses the editor with the selected task's current values and writes back
    // the result.
    private func editTask(at indexPath: IndexPath) {
        presentTaskEditor(
            title: "Edit Task",
            task: tasks[indexPath.row]
        ) { [weak self] updatedTask in
            guard let self,
                  tasks.indices.contains(indexPath.row) else { return }
            tasks[indexPath.row] = updatedTask
            tableView.reloadRows(at: [indexPath], with: .automatic)
        }
    }

    // Presents the iOS share sheet with a plain-text summary of the selected
    // task.
    private func shareTask(at indexPath: IndexPath, from sourceView: UIView) {
        guard tasks.indices.contains(indexPath.row) else { return }

        let task = tasks[indexPath.row]
        let shareText =
            "\(task.description)\nDue \(dateFormatter.string(from: task.dueDate))\nPriority: \(task.priority.rawValue)"
        let activityController = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        activityController.popoverPresentationController?
            .sourceView = sourceView
        present(activityController, animated: true)
    }

    // Formats each table row with task text, due date, priority color, and
    // completion checkmark.
    private func configure(_ cell: UITableViewCell, with task: Model.TodoTask) {
        var content = UIListContentConfiguration.subtitleCell()
        content.text = task.description
        content.secondaryText =
            "Due \(dateFormatter.string(from: task.dueDate)) • \(task.priority.rawValue) priority"
        content.textProperties.color = task
            .isComplete ? .secondaryLabel : .label
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

    private func color(for priority: Model.Priority) -> UIColor {
        switch priority {
        case .low:
            return .systemBlue
        case .medium:
            return .systemOrange
        case .high:
            return .systemRed
        }
    }

    private func showLoadTasksErrorAlert(_ error: Error) {
        let alert = UIAlertController(
            title: "Unable to Load Tasks",
            message: "Your saved tasks could not be loaded. \(error.localizedDescription)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func showSaveTasksErrorAlert(_ error: Error) {
        let alert = UIAlertController(
            title: "Unable to Save Tasks",
            message: "Your tasks could not be saved. \(error.localizedDescription)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// Supplies rows to the table view from the tasks array.
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

// Handles row taps and swipe actions for editing, sharing, deleting, and
// completion toggles.
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
            title: nil
        ) { [weak self] _, _, completion in
            self?.editTask(at: indexPath)
            completion(true)
        }
        editAction.backgroundColor = .systemBlue
        editAction.image = UIImage(systemName: "pencil")

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

// Allows due-task notifications to appear even while the app is open.
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

// Modal screen used for creating a new task or editing an existing one.
final class TaskEditorViewController: UIViewController {
    @IBOutlet var descriptionField: UITextField!
    @IBOutlet var dueDatePicker: UIDatePicker!
    @IBOutlet var priorityControl: UISegmentedControl!

    // Existing task is nil when creating a new todo; onSave passes the finished
    // value back.
    var task: Model.TodoTask?
    var onSave: ((Model.TodoTask) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        descriptionField.delegate = self
        dueDatePicker.preferredDatePickerStyle = .compact
        populateFields()
    }

    // Pre-fills the form when the user is editing an existing task.
    private func populateFields() {
        guard let task else { return }
        descriptionField.text = task.description
        dueDatePicker.date = task.dueDate
        priorityControl.selectedSegmentIndex = Model.Priority.allCases
            .firstIndex(of: task.priority) ?? 0
    }

    @objc func cancel() {
        dismiss(animated: true)
    }

    // Validates the form, builds a TodoTask, and returns it to the presenting
    // controller.
    @objc func save() {
        let trimmedDescription = descriptionField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedDescription.isEmpty else {
            showMissingDescriptionAlert()
            return
        }

        let priority = Model.Priority
            .allCases[priorityControl.selectedSegmentIndex]
        let savedTask = Model.TodoTask(
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

// Dismisses the keyboard when the user taps Return in the description field.
extension TaskEditorViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
