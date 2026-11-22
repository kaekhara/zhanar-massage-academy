import StoreKit
import SwiftUI
import Combine

@MainActor
final class PurchaseManager: ObservableObject {
    private struct PendingServerVerification {
        let signedTransactionInfo: String
        let appAccountToken: UUID?
    }

    static let standardCourseID = "com.zhanar.course.standard"
    static let selfMassageCourseID = "com.zhanar.course.selfmassage"
    static let productIDs = [standardCourseID, selfMassageCourseID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var localTestingProductIDs: Set<String> = []
    @Published private(set) var purchaseAccountTokens: [String: UUID] = [:]
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var unavailableProductIDs: Set<String> = []
    @Published private(set) var productLoadFailed = false
    @Published var message: String?
    @Published var isWorking = false

    private var updatesTask: Task<Void, Never>?
    private var unfinishedRetryTask: Task<Void, Never>?
    private var unfinishedRetryAttempt = 0
    private var pendingServerVerifications: [UInt64: PendingServerVerification] = [:]
    private var verificationRetryMessageTransactionID: UInt64?
    private var serverVerificationHandler: ((String, UUID?) async throws -> Bool)?
    private var processingTransactionIDs: Set<UInt64> = []

    init() {
        updatesTask = Task { [weak self] in
            guard let self else { return }
            await self.observeTransactions()
        }
    }

    deinit {
        updatesTask?.cancel()
        unfinishedRetryTask?.cancel()
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    func setServerVerificationHandler(_ handler: @escaping (String, UUID?) async throws -> Bool) {
        serverVerificationHandler = handler
    }

    func processUnfinishedTransactions() async {
        var unfinishedIDs: Set<UInt64> = []
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result {
                unfinishedIDs.insert(transaction.id)
            }
            await processUpdatedTransaction(result)
        }

        guard let serverVerificationHandler else { return }
        for (transactionID, pending) in Array(pendingServerVerifications)
            where !unfinishedIDs.contains(transactionID) {
            guard !processingTransactionIDs.contains(transactionID) else { continue }
            processingTransactionIDs.insert(transactionID)
            defer { processingTransactionIDs.remove(transactionID) }
            do {
                _ = try await serverVerificationHandler(pending.signedTransactionInfo, pending.appAccountToken)
                pendingServerVerifications.removeValue(forKey: transactionID)
                clearVerificationRetryState(for: transactionID)
                await refreshEntitlements()
            } catch is CancellationError {
                continue
            } catch {
                scheduleUnfinishedRetry()
            }
        }
    }

    func hasAccess(to productID: String, userID: UUID? = nil) -> Bool {
        CourseAccessPolicy.accountOwnsEntitlement(
            isEntitled: purchasedProductIDs.contains(productID),
            entitlementAccountToken: purchaseAccountTokens[productID],
            currentAccountID: userID
        )
    }

    func hasLocalTestingAccess(to productID: String, userID: UUID? = nil) -> Bool {
        localTestingProductIDs.contains(productID) && hasAccess(to: productID, userID: userID)
    }

    func loadProducts() async {
        await loadProducts(productIDs: Self.productIDs)
    }

    func loadProducts(productIDs: [String]) async {
        let requestedIDs = Set(productIDs)
        guard !requestedIDs.isEmpty else {
            products = []
            unavailableProductIDs = []
            productLoadFailed = false
            return
        }
        isLoadingProducts = true
        productLoadFailed = false
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: Array(requestedIDs))
            unavailableProductIDs = requestedIDs.subtracting(products.map(\.id))
            productLoadFailed = false
        } catch {
            // StoreKit can throw for transient system/network failures. It only
            // identifies missing product IDs when the request itself succeeds.
            unavailableProductIDs = []
            productLoadFailed = true
        }
    }

    func refreshEntitlements() async {
        var activeIDs: Set<String> = []
        var localIDs: Set<String> = []
        var accountTokens: [String: UUID] = [:]
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true else { continue }
            activeIDs.insert(transaction.productID)
            if transaction.environment == .xcode { localIDs.insert(transaction.productID) }
            if let token = transaction.appAccountToken {
                accountTokens[transaction.productID] = token
            }
        }
        purchasedProductIDs = activeIDs
        localTestingProductIDs = localIDs
        purchaseAccountTokens = accountTokens
    }

    func purchase(productID: String, appAccountToken: UUID?) async {
        guard !isWorking else { return }
        guard let appAccountToken else {
            message = "Сатып алу үшін алдымен ZHANAR аккаунтына кіріңіз."
            return
        }
        guard let product = product(for: productID) else {
            message = "Бұл курс қазір сатылымда жоқ. Кейінірек қайталап көріңіз."
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            var options: Set<Product.PurchaseOption> = []
            options.insert(.appAccountToken(appAccountToken))
            switch try await product.purchase(options: options) {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = "Сатып алуды App Store растаған жоқ. Қолдау қызметіне хабарласыңыз."
                    return
                }

                #if DEBUG
                if transaction.environment == .xcode {
                    await transaction.finish()
                    await refreshEntitlements()
                    message = hasLocalTestingAccess(to: productID, userID: appAccountToken)
                        ? "Курс сізге ашылды. Жақсы оқу!"
                        : "Бұл сатып алу басқа аккаунтқа тіркелген. Қазіргі аккаунтта қалпына келтіру мүмкін емес."
                    return
                }
                #endif
                guard let serverVerificationHandler else {
                    pendingServerVerifications[transaction.id] = PendingServerVerification(
                        signedTransactionInfo: verification.jwsRepresentation,
                        appAccountToken: transaction.appAccountToken
                    )
                    message = "Apple төлемді қабылдады, бірақ серверлік тексеру қолжетімсіз. Қолдау қызметіне хабарласыңыз."
                    return
                }
                do {
                    let serverGrantedAccess = try await serverVerificationHandler(
                        verification.jwsRepresentation,
                        transaction.appAccountToken
                    )
                    clearVerificationRetryState(for: transaction.id)
                    await transaction.finish()
                    await refreshEntitlements()
                    message = serverGrantedAccess
                        ? "Курс сізге ашылды. Жақсы оқу!"
                        : "Бұл сатып алу қайтарылған немесе кері қайтарылған. Курсқа қолжетімділік берілмеді."
                } catch is CancellationError {
                    message = "Сатып алуды аяқтау үшін оны бастаған ZHANAR аккаунтына қайта кіріңіз."
                    return
                } catch {
                    await refreshEntitlements()
                    recordVerificationFailure(transaction, signedTransactionInfo: verification.jwsRepresentation)
                    verificationRetryMessageTransactionID = transaction.id
                    message = "Apple төлемді қабылдады, бірақ курсқа қолжетімділік серверде расталмады. Қайталап көріңіз."
                    return
                }
            case .pending:
                message = "Сатып алу мақұлдауды күтіп тұр. Расталған соң курс ашылады."
            case .userCancelled:
                break
            @unknown default:
                message = "Сатып алудың күйін анықтау мүмкін болмады."
            }
        } catch {
            message = "Сатып алу аяқталмады. Қайталап көріңіз."
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            var verificationFailed = false
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result,
                      transaction.revocationDate == nil,
                      transaction.expirationDate.map({ $0 > Date() }) ?? true else { continue }
                #if DEBUG
                if transaction.environment == .xcode { continue }
                #endif
                guard let verificationHandler = serverVerificationHandler else {
                    message = "Сатып алуды тексеру қызметі қазір қолжетімсіз. Интернетті тексеріп, қайталап көріңіз."
                    return false
                }
                do {
                    _ = try await verificationHandler(result.jwsRepresentation, transaction.appAccountToken)
                    clearVerificationRetryState(for: transaction.id)
                    await transaction.finish()
                } catch is CancellationError {
                    continue
                } catch {
                    verificationFailed = true
                    recordVerificationFailure(transaction, signedTransactionInfo: result.jwsRepresentation)
                    verificationRetryMessageTransactionID = transaction.id
                    message = "Сатып алуларды қалпына келтіру мүмкін болмады. Қайталап көріңіз."
                }
            }
            await refreshEntitlements()
            return !verificationFailed
        } catch {
            message = "Сатып алуларды қалпына келтіру мүмкін болмады. Қайталап көріңіз."
            return false
        }
    }

    private func observeTransactions() async {
        for await result in Transaction.updates {
            await processUpdatedTransaction(result)
        }
    }

    private func processUpdatedTransaction(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result,
              !processingTransactionIDs.contains(transaction.id) else { return }
        processingTransactionIDs.insert(transaction.id)
        defer { processingTransactionIDs.remove(transaction.id) }

        #if DEBUG
        if transaction.environment == .xcode {
            await transaction.finish()
            await refreshEntitlements()
            return
        }
        #endif
        guard transaction.appAccountToken != nil,
              let serverVerificationHandler else { return }
        do {
            _ = try await serverVerificationHandler(result.jwsRepresentation, transaction.appAccountToken)
            clearVerificationRetryState(for: transaction.id)
            await transaction.finish()
        } catch is CancellationError {
            return
        } catch {
            recordVerificationFailure(transaction, signedTransactionInfo: result.jwsRepresentation)
            return
        }
        await refreshEntitlements()
    }

    private func scheduleUnfinishedRetry() {
        guard unfinishedRetryTask == nil else { return }
        let delays: [UInt64] = [5, 10, 20, 40, 80, 160, 300]
        let delay = delays[min(unfinishedRetryAttempt, delays.count - 1)]
        unfinishedRetryAttempt = min(unfinishedRetryAttempt + 1, delays.count - 1)
        unfinishedRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self else { return }
            self.unfinishedRetryTask = nil
            await self.processUnfinishedTransactions()
        }
    }

    private func recordVerificationFailure(
        _ transaction: StoreKit.Transaction,
        signedTransactionInfo: String
    ) {
        pendingServerVerifications[transaction.id] = PendingServerVerification(
            signedTransactionInfo: signedTransactionInfo,
            appAccountToken: transaction.appAccountToken
        )
        scheduleUnfinishedRetry()
    }

    private func clearVerificationRetryState(for transactionID: UInt64) {
        pendingServerVerifications.removeValue(forKey: transactionID)
        unfinishedRetryAttempt = 0
        if verificationRetryMessageTransactionID == transactionID {
            verificationRetryMessageTransactionID = nil
            message = nil
        }
    }
}
