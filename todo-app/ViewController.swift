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
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
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
        configureView()
        configureTableView()
    }

    private func configureView() {
        title = "TODO"
        view.backgroundColor = .systemBackground

        if navigationController == nil {
            addEmbeddedNavigationBar()
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Edit",
            style: .plain,
            target: self,
            action: #selector(toggleEditing)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addTask)
        )
    }

    private func addEmbeddedNavigationBar() {
        let navigationBar = UINavigationBar()
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        navigationBar.items = [navigationItem]
        view.addSubview(navigationBar)

        NSLayoutConstraint.activate([
            navigationBar.topAnchor
                .constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor
                .constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(
            UITableViewCell.self,
            forCellReuseIdentifier: "TaskCell"
        )
        view.addSubview(tableView)

        let topAnchor = view.subviews.compactMap { $0 as? UINavigationBar }
            .first?.bottomAnchor ?? view.safeAreaLayoutGuide.topAnchor
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func toggleEditing() {
        isEditing.toggle()
    }

    @objc private func addTask() {
        presentTaskEditor(title: "New Task", task: nil) { [weak self] task in
            self?.tasks.append(task)
            self?.tableView.insertRows(
                at: [IndexPath(row: (self?.tasks.count ?? 1) - 1, section: 0)],
                with: .automatic
            )
        }
    }

    private func presentTaskEditor(
        title: String,
        task: TodoTask?,
        completion: @escaping (TodoTask) -> Void
    ) {
        let editor = TaskEditorViewController(task: task)
        editor.title = title
        editor.onSave = completion

        let navigationController =
            UINavigationController(rootViewController: editor)
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
        alert
            .addAction(UIAlertAction(
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
        var content = cell.defaultContentConfiguration()
        content.text = task.description
        content
            .secondaryText =
            "Due \(dateFormatter.string(from: task.dueDate)) • \(task.priority.rawValue) priority"
        content.textProperties.color = task
            .isComplete ? .secondaryLabel : .label
        content.secondaryTextProperties.color = color(for: task.priority)
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
            title: "Delete"
        ) { [weak self] _, _, completion in
            self?.confirmDeleteTask(at: indexPath)
            completion(false)
        }

        let completeTitle = tasks[indexPath.row].isComplete ? "Open" : "Done"
        let completeAction = UIContextualAction(
            style: .normal,
            title: completeTitle
        ) { [weak self] _, _, completion in
            self?.toggleCompletion(at: indexPath)
            completion(true)
        }
        completeAction.backgroundColor = .systemGreen

        return UISwipeActionsConfiguration(actions: [
            deleteAction,
            completeAction
        ])
    }
}

final class TaskEditorViewController: UIViewController {
    var onSave: ((TodoTask) -> Void)?

    private let descriptionField = UITextField()
    private let dueDatePicker = UIDatePicker()
    private let priorityControl = UISegmentedControl(
        items: TodoTask.Priority
            .allCases.map(\.rawValue)
    )
    private let task: TodoTask?

    init(task: TodoTask?) {
        self.task = task
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        task = nil
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        populateFields()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(save)
        )

        descriptionField.borderStyle = .roundedRect
        descriptionField.placeholder = "Task description"
        descriptionField.clearButtonMode = .whileEditing
        descriptionField.returnKeyType = .done
        descriptionField.delegate = self

        dueDatePicker.datePickerMode = .date
        dueDatePicker.preferredDatePickerStyle = .inline

        priorityControl.selectedSegmentIndex = TodoTask.Priority.allCases
            .firstIndex(of: .medium) ?? 0

        let descriptionLabel = makeLabel(text: "Description")
        let dueDateLabel = makeLabel(text: "Due Date")
        let priorityLabel = makeLabel(text: "Priority")

        let stackView = UIStackView(arrangedSubviews: [
            descriptionLabel,
            descriptionField,
            dueDateLabel,
            dueDatePicker,
            priorityLabel,
            priorityControl
        ])
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 20
            ),
            stackView.leadingAnchor
                .constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor
                .constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func makeLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }

    private func populateFields() {
        guard let task else { return }
        descriptionField.text = task.description
        dueDatePicker.date = task.dueDate
        priorityControl.selectedSegmentIndex = TodoTask.Priority.allCases
            .firstIndex(of: task.priority) ?? 0
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func save() {
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
