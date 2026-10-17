#if canImport(NeoBiliData)
import NeoBiliData
#endif
#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

// Production convenience initializers live at the composition boundary.
// Data initializers accept the same dependencies explicitly.

extension APIClient {
    init(session: URLSession = AppNetwork.session,
         appEncoder: any AppRequestEncoding = AppRequestEncoder(),
         authentication: @escaping @Sendable () async -> DeviceIdentity.AuthenticatedRequestSnapshot = {
             await DeviceIdentity.shared.authenticatedRequestSnapshot()
         },
         appAuthentication: @escaping @Sendable () async -> DeviceIdentity.AppRequestAccount = {
             await DeviceIdentity.shared.appAccount()
         },
         appHeaders: @escaping @Sendable (UUID) async throws -> [String: String] = { session in
             guard !AppNetwork.isRegression else { return [:] }
             return try await DeviceIdentity.shared.appRequestHeaders(expectedSessionID: session)
         },
         transport: HTTPTransport? = nil,
         signWebParameters: @escaping @Sendable ([String: String]) async throws -> [String: String] = {
             try await WBISigner.shared.sign(params: $0)
         }) {
        self.init(transport: transport ?? HTTPTransport(session: session), appEncoder: appEncoder,
                  authentication: authentication, appAuthentication: appAuthentication,
                  appHeaders: appHeaders, signWebParameters: signWebParameters)
    }
}

extension HTTPTransport {
    init(session: URLSession, diagnostics: RecommendationDiagnostics = .shared) {
        self.init(session: session, diagnostics: diagnostics, observeResponse: {
            await DeviceIdentity.shared.observeAppResponse($0, request: $1)
        })
    }
}

extension WBISigner {
    init(session: URLSession = AppNetwork.session, defaults: UserDefaults = .standard) {
        self.init(session: session, defaults: defaults, cookieHeader: { await DeviceIdentity.shared.cookieHeader() })
    }
}

extension DeviceIdentity {
    init(defaults: UserDefaults = .standard,
         randomBuvidExperiment: Bool = false,
         customBuvid: String? = nil,
         credentials: CredentialStorage = AppNetwork.isRegression ? .memory() : .keychain,
         allowsNetwork: Bool = !AppNetwork.isRegression,
         eventSerialDefaults: UserDefaults? = nil,
         vendorIdentifier: @escaping @Sendable () async -> String? = { await AppBuvid.vendorIdentifier() },
         deviceRegistration: AppDeviceRegistration? = nil,
         guestRegistration: AppGuestRegistration? = nil,
         ticketService: AppTicketService? = nil,
         rawTransport: @escaping SMSPassport.Transport = { try await AppNetwork.session.data(for: $0) },
         purgeCookies: @escaping @Sendable () -> Void = { DeviceIdentity.purgeSharedCookieJar() }) {
        self.init(defaults: defaults, randomBuvidExperiment: randomBuvidExperiment, customBuvid: customBuvid,
                  credentials: credentials, allowsNetwork: allowsNetwork, eventSerialDefaults: eventSerialDefaults,
                  vendorIdentifier: vendorIdentifier, deviceRegistration: deviceRegistration,
                  guestRegistration: guestRegistration, ticketService: ticketService, rawTransport: rawTransport,
                  networkSnapshot: { AppNetworkMetadata.shared.snapshot() }, purgeCookies: purgeCookies)
    }
}
