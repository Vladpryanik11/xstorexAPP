import Foundation

protocol AuthServicing: Sendable {
    func isSignedIn() async -> Bool
    func activate(code: String) async throws -> Account
    func signOut() async
}

/// Вход по коду активации и выход.
struct AuthService: AuthServicing {
    let api: APIClientProtocol
    let tokenStore: TokenStoring
    let device: DeviceInfo

    func isSignedIn() async -> Bool {
        await tokenStore.token() != nil
    }

    /// `POST /app/activate`. Код можно передать в любом виде: он нормализуется и форматируется.
    func activate(code: String) async throws -> Account {
        let request = ActivateRequest(
            activationCode: ActivationCode.format(code),
            device: ActivationDevice(
                installId: device.installId,
                model: device.model,
                osVersion: device.osVersion,
                locale: device.locale
            )
        )
        let endpoint = Endpoint<ActivateResponse>.json(path: "/app/activate", body: request, requiresAuth: false)
        let response = try await api.send(endpoint)
        await tokenStore.save(response.token)
        return response.account
    }

    /// `POST /app/sign-out`. Локальный токен удаляется в любом случае, даже без сети.
    func signOut() async {
        _ = try? await api.send(Endpoint<EmptyResponse>(path: "/app/sign-out", method: .post))
        await tokenStore.clear()
    }
}
