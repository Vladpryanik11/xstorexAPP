import UIKit

/// «Менеджер» этапа 1: активные установки из `InstallService` и пустое состояние.
/// Импорт своих IPA появится на этапе 2.
final class ManagerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let installService: InstallService
    private weak var router: AppRouting?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let stateView = StateView()
    private var activities: [InstallService.Activity] = []

    init(installService: InstallService, router: AppRouting) {
        self.installService = installService
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.groupedBackground
        navigationItem.rightBarButtonItem = makeAccountBarButton(target: self, action: #selector(openAccount))

        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "install")
        tableView.backgroundView = stateView
        view.addSubview(tableView)

        installService.addObserver(self) { [weak self] _, _ in
            self?.reload()
        }
        reload()
    }

    private func reload() {
        activities = installService.activeInstalls
        tableView.reloadData()
        stateView.isHidden = !activities.isEmpty
        if activities.isEmpty {
            stateView.show(.message(
                symbol: "arrow.down.circle",
                title: L10n.tr("manager.empty.title"),
                message: L10n.tr("manager.empty.message"),
                actionTitle: nil
            ))
        }
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        activities.isEmpty ? 0 : 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        activities.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        L10n.tr("manager.section.downloads")
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "install", for: indexPath)
        let activity = activities[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = activity.app.name
        content.secondaryText = InstallStatusText.text(for: activity.state)
        content.secondaryTextProperties.color = {
            if case .failed = activity.state {
                return Palette.destructive
            }
            return Palette.textSecondary
        }()
        content.image = UIImage(systemName: symbol(for: activity.state))
        content.imageProperties.tintColor = Palette.tint(light: activity.app.tintLight, dark: activity.app.tintDark)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func symbol(for state: InstallState) -> String {
        switch state {
        case .failed: return "exclamationmark.circle.fill"
        case .installing: return "checkmark.circle.fill"
        default: return "arrow.down.circle.fill"
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let activity = activities[indexPath.row]
        router?.showAppDetail(appId: activity.app.id, summary: activity.app, from: self)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let activity = activities[indexPath.row]
        let isActive = activity.state.isActive
        let title = isActive ? L10n.tr("install.cancel.confirm") : L10n.tr("manager.remove")
        let action = UIContextualAction(style: .destructive, title: title) { [weak self] _, _, completion in
            guard let self = self else {
                completion(false)
                return
            }
            if isActive {
                self.installService.cancel(appId: activity.app.id)
            } else {
                self.installService.dismiss(appId: activity.app.id)
            }
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    @objc private func openAccount() {
        router?.showAccount(from: self)
    }
}
