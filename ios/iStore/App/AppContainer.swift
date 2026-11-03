import UIKit

/// Composition root: создаёт сервисы один раз и раздаёт их по протоколам.
@MainActor
final class AppContainer {
    let configuration: AppConfiguration
    let keychain: KeychainStore
    let installId: String
    let device: DeviceInfo
    let defaults: UserDefaults

    let tokenStore: TokenStoring
    let apiClient: APIClient
    let authService: AuthServicing
    let clientService: ClientServicing
    let catalogService: CatalogServicing
    let clientUpdate: ClientUpdateChecking
    let liveSync: CatalogLiveSync
    let telemetry: TelemetryRecorder
    let installService: InstallService
    let imagePipeline: ImagePipeline

    var api: APIClientProtocol { apiClient }

    private(set) lazy var featureFactory = FeatureFactory(container: self)

    init(configuration: AppConfiguration = .load(), defaults: UserDefaults = .standard) {
        self.configuration = configuration
        self.defaults = defaults

        let keychain = KeychainStore(service: "com.istore.app")
        self.keychain = keychain
        let installId = InstallID.load(from: keychain)
        self.installId = installId
        let device = DeviceInfo.current(installId: installId)
        self.device = device

        let tokenStore = KeychainTokenStore(keychain: keychain)
        self.tokenStore = tokenStore

        let identity = ClientIdentity(
            baseURL: configuration.baseURL,
            language: L10n.apiLanguage,
            build: configuration.build,
            installId: installId
        )
        let apiClient = APIClient(identity: identity, tokenStore: tokenStore)
        self.apiClient = apiClient

        authService = AuthService(api: apiClient, tokenStore: tokenStore, device: device)
        clientService = ClientService(api: apiClient)
        let catalogService = CatalogService(api: apiClient)
        self.catalogService = catalogService
        clientUpdate = ClientUpdateService(api: apiClient)
        liveSync = CatalogLiveSync(api: apiClient, catalog: catalogService)
        let telemetry = TelemetryRecorder(api: apiClient, tokenStore: tokenStore)
        self.telemetry = telemetry
        installService = InstallService(
            api: apiClient,
            opener: SystemURLOpener(),
            device: SystemDeviceCapacity(osVersion: device.osVersion),
            telemetry: telemetry
        )
        imagePipeline = ImagePipeline.shared
    }
}
