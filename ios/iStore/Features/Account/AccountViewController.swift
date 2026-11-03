import SafariServices
import UIKit

/// Шит «Аккаунт»: план, статус, срок, «Продлить», отслеживаемые приложения, устройство, версия, «Выйти».
final class AccountViewController: UITableViewController {
    private enum Row {
        case summary
        case plan
        case status
        case expires
        case renew
        case following
        case device
        case installId
        case appVersion
        case signOut
    }

    private let clientService: ClientServicing
    private let configuration: AppConfiguration
    private let device: DeviceInfo
    private let makeFollowingList: () -> UIViewController?
    private let onSignOut: () -> Void

    private var profile: ClientProfile?
    private var loadError: APIError?
    private var isLoading = false
    private var sections: [[Row]] = []

    init(
        clientService: ClientServicing,
        configuration: AppConfiguration,
        device: DeviceInfo,
        makeFollowingList: @escaping () -> UIViewController?,
        onSignOut: @escaping () -> Void
    ) {
        self.clientService = clientService
        self.configuration = configuration
        self.device = device
        self.makeFollowingList = makeFollowingList
        self.onSignOut = onSignOut
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.tr("account.title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        rebuildSections()
        load()
    }

    private func load() {
        guard !isLoading else { return }
        isLoading = true
        let service = clientService
        Task { [weak self] in
            do {
                let profile = try await service.profile()
                self?.profile = profile
                self?.loadError = nil
            } catch {
                self?.loadError = APIError.wrap(error)
            }
            self?.isLoading = false
            self?.rebuildSections()
        }
    }

    private func rebuildSections() {
        var accountRows: [Row] = [.summary, .plan, .status]
        if profile?.account.expiresAt != nil {
            accountRows.append(.expires)
        }
        var result: [[Row]] = [accountRows]
        if profile?.account.renewUrl != nil {
            result.append([.renew])
        }
        result.append([.following])
        result.append([.device, .installId, .appVersion])
        result.append([.signOut])
        sections = result
        tableView.reloadData()
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let first = sections[section].first else { return nil }
        switch first {
        case .summary: return L10n.tr("account.section.subscription")
        case .device: return L10n.tr("account.section.device")
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard sections[section].first == .summary, let error = loadError else { return nil }
        return error.userMessage
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let row = sections[indexPath.section][indexPath.row]
        cell.accessoryType = .none
        cell.selectionStyle = .none
        let account = profile?.account

        switch row {
        case .summary:
            var content = UIListContentConfiguration.subtitleCell()
            content.text = account?.displayName ?? L10n.tr("account.default_name")
            content.secondaryText = isLoading && profile == nil ? L10n.tr("common.loading") : account.map { _ in device.model }
            content.textProperties.font = Typography.font(.headline, weight: .semibold)
            content.image = UIImage(systemName: "person.crop.circle.fill")
            content.imageProperties.tintColor = Palette.accent
            content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40)
            cell.contentConfiguration = content
        case .plan:
            cell.contentConfiguration = valueContent(L10n.tr("account.plan"), account?.plan?.name ?? L10n.tr("common.none"))
        case .status:
            cell.contentConfiguration = valueContent(L10n.tr("account.status"), statusText(account?.status), valueColor: statusColor(account?.status))
        case .expires:
            let value = account?.expiresAt.map { Formatters.date($0) } ?? L10n.tr("common.none")
            cell.contentConfiguration = valueContent(L10n.tr("account.expires"), value)
        case .renew:
            var content = UIListContentConfiguration.cell()
            content.text = L10n.tr("account.renew")
            content.textProperties.color = Palette.accent
            content.image = UIImage(systemName: "arrow.clockwise.circle.fill")
            content.imageProperties.tintColor = Palette.accent
            cell.contentConfiguration = content
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        case .following:
            var content = UIListContentConfiguration.cell()
            content.text = L10n.tr("account.following")
            content.image = UIImage(systemName: "bell.fill")
            content.imageProperties.tintColor = Palette.accent
            cell.contentConfiguration = content
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        case .device:
            let model = profile?.device?.model ?? device.model
            let os = profile?.device?.osVersion ?? device.osVersion
            cell.contentConfiguration = valueContent(L10n.tr("account.device"), L10n.tr("account.device_format", model, os))
        case .installId:
            let suffix = profile?.device?.installIdLast4 ?? String(device.installId.suffix(4))
            cell.contentConfiguration = valueContent(L10n.tr("account.install_id"), L10n.tr("account.install_id_format", suffix))
        case .appVersion:
            cell.contentConfiguration = valueContent(
                L10n.tr("account.app_version"),
                L10n.tr("account.app_version_format", configuration.version, configuration.build)
            )
        case .signOut:
            var content = UIListContentConfiguration.cell()
            content.text = L10n.tr("account.sign_out")
            content.textProperties.color = Palette.destructive
            content.textProperties.alignment = .center
            cell.contentConfiguration = content
            cell.selectionStyle = .default
        }
        return cell
    }

    private func valueContent(_ title: String, _ value: String, valueColor: UIColor = Palette.textSecondary) -> UIListContentConfiguration {
        var content = UIListContentConfiguration.valueCell()
        content.text = title
        content.secondaryText = value
        content.secondaryTextProperties.color = valueColor
        return content
    }

    private func statusText(_ status: AccountStatus?) -> String {
        switch status {
        case .some(.active): return L10n.tr("account.status.active")
        case .some(.expired): return L10n.tr("account.status.expired")
        case .some(.suspended): return L10n.tr("account.status.suspended")
        default: return L10n.tr("common.none")
        }
    }

    private func statusColor(_ status: AccountStatus?) -> UIColor {
        switch status {
        case .some(.active): return Palette.success
        case .some(.expired), .some(.suspended): return Palette.destructive
        default: return Palette.textSecondary
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section][indexPath.row] {
        case .renew:
            guard let url = profile?.account.renewUrl else { return }
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = Palette.accent
            present(safari, animated: true)
        case .following:
            guard let controller = makeFollowingList() else { return }
            navigationController?.pushViewController(controller, animated: true)
        case .signOut:
            confirmSignOut()
        default:
            break
        }
    }

    private func confirmSignOut() {
        let alert = UIAlertController(
            title: L10n.tr("account.sign_out.confirm_title"),
            message: L10n.tr("account.sign_out.confirm_message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.tr("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.tr("account.sign_out"), style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            let onSignOut = self.onSignOut
            self.dismiss(animated: true) {
                onSignOut()
            }
        })
        present(alert, animated: true)
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}
