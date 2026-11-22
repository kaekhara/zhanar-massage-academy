import SwiftUI
import Combine
import StoreKit
import Supabase
import AVKit
import Network

private enum AppTab: String, CaseIterable {
    case home = "Басты бет"
    case courses = "Курстар"
    case profile = "Кабинет"

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .courses: "play.rectangle.fill"
        case .profile: "person.crop.circle"
        }
    }
}

private enum LegalLinks {
    private static let values: [String: String] = {
        guard let url = Bundle.main.url(forResource: "LegalLinks", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] else {
            return [:]
        }
        return propertyList
    }()

    static func url(for key: String) -> URL? {
        guard let value = values[key],
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false else { return nil }
        return components.url
    }
}

private enum AppScreen: Equatable {
    case root
    case coursePreview
    case course
    case lesson
    case paywall
}

private struct CourseSection: Identifiable {
    let key: String
    let sourceID: String?
    var id: String { sourceID ?? key }
    let title: String
    let lessons: Int
    let symbol: String

    init(key: String, title: String, lessons: Int, symbol: String, sourceID: String? = nil) {
        self.key = key
        self.title = title
        self.lessons = lessons
        self.symbol = symbol
        self.sourceID = sourceID
    }
}

@MainActor
private final class PlaybackCheckpointObserver: ObservableObject {
    private weak var player: AVPlayer?
    private var token: Any?

    func observe(_ player: AVPlayer, onCheckpoint: @escaping (Double) -> Void) {
        stop()
        self.player = player
        token = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 15, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard time.seconds.isFinite, time.seconds > 0 else { return }
            onCheckpoint(time.seconds)
        }
    }

    func stop() {
        if let player, let token { player.removeTimeObserver(token) }
        token = nil
        player = nil
    }

    deinit {
        if let player, let token { player.removeTimeObserver(token) }
    }
}

@MainActor
private final class LessonPlaybackState: ObservableObject {
    @Published var failed = false
    private var statusObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?

    func observe(_ item: AVPlayerItem) {
        failed = false
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in self?.failed = true }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.failed = true }
        }
    }

    func reset() {
        statusObservation = nil
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }
        failed = false
    }

    deinit {
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    }
}

@MainActor
private final class NetworkPathObserver: ObservableObject {
    @Published private(set) var isConnected = false
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.kaekhara.MassageApp.network-path")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in self?.isConnected = connected }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

struct ContentView: View {
    private static let debugPreviewAccountToken = UUID(uuid: (
        0x4A, 0x41, 0x52, 0x47, 0x59, 0x4E, 0x00, 0x01,
        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
    ))

    @StateObject private var auth = AuthManager()
    @StateObject private var purchases = PurchaseManager()
    @StateObject private var lessonPlayback = LessonPlaybackState()
    @StateObject private var playbackCheckpointObserver = PlaybackCheckpointObserver()
    @StateObject private var networkPath = NetworkPathObserver()
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var languageSettings: LanguageSettings
    @State private var selectedTab: AppTab = .home
    @State private var screen: AppScreen = .root
    @State private var selectedSection = "Анатомия"
    @State private var selectedSectionID = "anatomy"
    @State private var selectedLessonNumber = 1
    @State private var selectedProductID = PurchaseManager.standardCourseID
    @State private var courseSearchText = ""
    @State private var selectedCatalogCategory: String?
    @State private var displayName = "Оқушы"
    @State private var phoneNumber = ""
    @State private var showingProfileEditor = false
    @State private var showingAdminDashboard = false
    @State private var showingMessageAlert = false
    @State private var isSavingProfile = false
    @State private var profileSaveError: String?
    @State private var showingHelp = false
    @State private var showingPrivacy = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var previewMode = false
    @State private var progressRevision = 0
    @State private var profileDraftName = ""
    @State private var isRefreshingCatalog = false
    @State private var catalogRefreshTask: Task<Void, Never>?
    @State private var catalogRefreshUserID: UUID?
    @State private var lessonVideoURL: URL?
    @State private var lessonPlayer: AVPlayer?
    @State private var loadedVideoLessonID: String?
    @State private var loadedPlaybackUserID: UUID?
    @State private var resumeCheckpoints: [String: LocalResumeCheckpoint] = [:]
    @State private var resumeUploadTask: Task<Void, Never>?
    @State private var resumeRetryTask: Task<Void, Never>?
    @State private var resumeRetryAttempts = 0
    @State private var lessonVideoRequestID: UUID?
    @State private var isLoadingLessonVideo = false
    @State private var lessonVideoLoadFailed = false
    @State private var progressRetryTask: Task<Void, Never>?
    @State private var progressRetryAttempts = 0
    @State private var pendingSignInDestination: AppScreen?

    private let cream = Color(red: 0.98, green: 0.93, blue: 0.88)
    private let brown = Color(red: 0.48, green: 0.20, blue: 0.06)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.11)
    private var privacyPolicyURL: URL? { LegalLinks.url(for: "PrivacyPolicyURL") }
    private var supportURL: URL? { LegalLinks.url(for: "SupportURL") }
    private var termsOfUseURL: URL? { LegalLinks.url(for: "TermsOfUseURL") }
    private let appleStandardEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private let sections = [
        CourseSection(key: "anatomy", title: "Анатомия", lessons: 3, symbol: "figure.cooldown"),
        CourseSection(key: "diagnostics", title: "Диагностика жасау", lessons: 3, symbol: "heart.text.square"),
        CourseSection(key: "therapeutic", title: "Емдік массаж", lessons: 4, symbol: "hands.sparkles"),
        CourseSection(key: "cupping", title: "Банка қою", lessons: 2, symbol: "circle.dotted"),
        CourseSection(key: "fire", title: "От массаж", lessons: 3, symbol: "flame"),
        CourseSection(key: "vacuum", title: "Вакуум массаж", lessons: 2, symbol: "wind"),
        CourseSection(key: "lymphatic", title: "Лимфодренажный массаж", lessons: 3, symbol: "drop"),
        CourseSection(key: "honey", title: "Бал массаж", lessons: 2, symbol: "leaf"),
        CourseSection(key: "conclusion", title: "Қорытынды", lessons: 2, symbol: "checkmark.seal")
    ]

    private let selfMassageSections = [
        CourseSection(key: "preparation", title: "Массажға дайындық", lessons: 3, symbol: "sparkles"),
        CourseSection(key: "face", title: "Бет массажы", lessons: 5, symbol: "face.smiling"),
        CourseSection(key: "neck_shoulders", title: "Мойын және иық", lessons: 4, symbol: "figure.mind.and.body"),
        CourseSection(key: "hands", title: "Қол массажы", lessons: 4, symbol: "hand.raised"),
        CourseSection(key: "legs", title: "Аяқ массажы", lessons: 5, symbol: "figure.walk"),
        CourseSection(key: "aftercare", title: "Қайталау және күтім", lessons: 4, symbol: "heart.text.square"),
        CourseSection(key: "conclusion", title: "Қорытынды", lessons: 5, symbol: "checkmark.seal")
    ]

    private var completedLessonIDs: Set<String> {
        _ = progressRevision
        let data = Data(completedLessonIDsRaw.utf8)
        return Set((try? JSONDecoder().decode([String].self, from: data)) ?? [])
    }

    private var completedLessonIDsRaw: String {
        UserDefaults.standard.string(forKey: "learning.completedLessonIDs.\(auth.user?.id.uuidString ?? "preview")") ?? "[]"
    }

    private var latestResumeDestination: (course: AccessibleCourse, section: PublishedSection, lesson: PublishedLesson, lessonNumber: Int)? {
        for (lessonID, _) in resumeCheckpoints.sorted(by: { $0.value.updatedAt > $1.value.updatedAt }) {
            guard !completedLessonIDs.contains(lessonID) else { continue }
            for course in auth.accessibleCourses {
                for section in course.sections {
                    guard let index = section.lessons.firstIndex(where: { $0.id == lessonID }) else { continue }
                    let lesson = section.lessons[index]
                    if CourseAccessPolicy.canOpenLesson(
                        courseIsPublished: course.isPublished,
                        lessonIsPreview: lesson.isPreview,
                        hasVerifiedCourseEntitlement: hasCourseAccess(course.productID)
                    ) {
                        return (course, section, lesson, index + 1)
                    }
                }
            }
        }
        return nil
    }

    private var currentSectionKey: String { courseSections.first(where: { $0.id == selectedSectionID })?.key ?? "unknown" }
    private var currentPublishedLesson: PublishedLesson? {
        publishedLesson(at: selectedLessonNumber)
    }
    private func publishedLesson(at number: Int) -> PublishedLesson? {
        guard let section = auth.accessibleCourse(for: selectedProductID)?.sections.first(where: { $0.id == selectedSectionID }),
              section.lessons.indices.contains(number - 1) else { return nil }
        return section.lessons[number - 1]
    }
    private var currentLessonID: String { currentPublishedLesson?.id ?? "\(selectedProductID).\(currentSectionKey).\(String(format: "%02d", selectedLessonNumber))" }
    private var isCurrentLessonComplete: Bool { completedLessonIDs.contains(currentLessonID) }
    private var canTrackCurrentLesson: Bool {
        // Preview lessons are available to explore without an entitlement, but
        // completion is account progress and must belong to a course owner.
        return hasCourseAccess(selectedProductID)
    }
    private var canSyncCurrentLessonProgress: Bool {
        auth.user != nil && auth.verifiedCourseProductIDs.contains(selectedProductID)
    }
    private var completedLessonCount: Int { completedLessonIDs.count }
    private var currentCourseLessonCount: Int {
        auth.accessibleCourse(for: selectedProductID)?.sections.reduce(0) { $0 + $1.lessons.count }
            ?? courseSections.reduce(0) { $0 + $1.lessons }
    }
    private var currentSectionLessonCount: Int {
        auth.accessibleCourse(for: selectedProductID)?.sections.first(where: { $0.id == selectedSectionID })?.lessons.count
            ?? courseSections.first(where: { $0.id == selectedSectionID })?.lessons
            ?? 0
    }
    private var courseSections: [CourseSection] {
        if let remoteSections = auth.accessibleCourse(for: selectedProductID)?.sections {
            return remoteSections.map { section in
                let key = section.id.split(separator: ".").last.map(String.init) ?? section.id
                return CourseSection(key: key, title: section.title, lessons: section.lessons.count, symbol: sectionSymbol(for: key), sourceID: section.id)
            }
        }
        #if DEBUG
        return selectedProductID == PurchaseManager.selfMassageCourseID ? selfMassageSections : sections
        #else
        return []
        #endif
    }

    private var catalogProductIDs: [String] {
        #if DEBUG
        return Array(Set(auth.accessibleCourseProductIDs).union(PurchaseManager.productIDs)).sorted { lhs, rhs in
            let leftOrder = auth.accessibleCourse(for: lhs)?.sortOrder ?? PurchaseManager.productIDs.firstIndex(of: lhs) ?? Int.max
            let rightOrder = auth.accessibleCourse(for: rhs)?.sortOrder ?? PurchaseManager.productIDs.firstIndex(of: rhs) ?? Int.max
            return leftOrder < rightOrder
        }
        #else
        return auth.accessibleCourses.sorted { $0.sortOrder < $1.sortOrder }.map(\.productID)
        #endif
    }

    private func categoryKey(for productID: String) -> String {
        let category = auth.accessibleCourse(for: productID)?.category?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let category, !category.isEmpty else { return "" }
        return category.localizedLowercase
    }

    private var catalogCategoryKeys: [String] {
        Array(Set(catalogProductIDs.map(categoryKey(for:)))).sorted()
    }

    private func categoryLabel(for key: String) -> String {
        guard !key.isEmpty, let course = auth.accessibleCourses.first(where: { categoryKey(for: $0.productID) == key }) else {
            return languageSettings.language == .russian ? "Другое" : "Басқа"
        }
        return localizedOptionalCopy(kazakh: course.category, russian: course.categoryRu) ?? key
    }

    private var searchedCatalogProductIDs: [String] {
        let query = courseSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return catalogProductIDs }
        return catalogProductIDs.filter { productID in
            let course = auth.accessibleCourse(for: productID)
            let fallback = fallbackCourseTitle(for: productID)
            return [course?.title, course?.subtitle, course?.description, course?.titleRu, course?.subtitleRu, course?.descriptionRu, course?.category, course?.categoryRu, fallback]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var filteredCatalogProductIDs: [String] {
        guard let selectedCatalogCategory, catalogCategoryKeys.contains(selectedCatalogCategory) else { return searchedCatalogProductIDs }
        return searchedCatalogProductIDs.filter { categoryKey(for: $0) == selectedCatalogCategory }
    }

    private func fallbackCourseTitle(for productID: String) -> String {
        switch productID {
        case PurchaseManager.standardCourseID: "Классикалық массаж курсы"
        case PurchaseManager.selfMassageCourseID: "Өзіне-өзі массаж"
        default: "ZHANAR Massage курсы"
        }
    }

    private var selectedCourseTitle: String {
        guard let course = auth.accessibleCourse(for: selectedProductID) else { return fallbackCourseTitle(for: selectedProductID) }
        return localizedCopy(course.title, russian: course.titleRu)
    }

    private var selectedCourseDescription: String {
        guard let course = auth.accessibleCourse(for: selectedProductID) else { return "ZHANAR Massage мектебінің массаж бойынша онлайн курсы." }
        return localizedCopy(course.description, russian: course.descriptionRu)
    }

    private func localizedCopy(_ kazakh: String, russian: String?) -> String {
        guard languageSettings.language == .russian,
              let russian, !russian.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return kazakh }
        return russian
    }

    private func localizedOptionalCopy(kazakh: String?, russian: String?) -> String? {
        let kazakh = kazakh?.trimmingCharacters(in: .whitespacesAndNewlines)
        let russian = russian?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = languageSettings.language == .russian ? russian : kazakh
        let fallback = languageSettings.language == .russian ? kazakh : russian
        if let preferred, !preferred.isEmpty { return preferred }
        if let fallback, !fallback.isEmpty { return fallback }
        return nil
    }

    private func localizedSectionTitle(_ kazakh: String, sourceID: String? = nil) -> String {
        let russian = auth.accessibleCourse(for: selectedProductID)?.sections.first(where: {
            sourceID == nil ? $0.title == kazakh : $0.id == sourceID
        })?.titleRu
        return localizedCopy(kazakh, russian: russian)
    }

    private func localizedLessonTitle(_ lesson: PublishedLesson) -> String {
        localizedCopy(lesson.title, russian: lesson.titleRu)
    }

    private func courseCard(_ productID: String) -> some View {
        let course = auth.accessibleCourse(for: productID)
        let isOwned = hasCourseAccess(productID)
        let title = course.map { localizedCopy($0.title, russian: $0.titleRu) } ?? fallbackCourseTitle(for: productID)
        let subtitle = course.map { localizedCopy($0.subtitle, russian: $0.subtitleRu) } ?? "Массаж курсы · ZHANAR Massage"
        return Button { openProduct(productID) } label: {
            HStack(spacing: 14) {
                courseArtwork(course: course, productID: productID, cornerRadius: 15)
                    .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey(title)).font(.system(size: 15, weight: .bold)).foregroundStyle(ink).lineLimit(2)
                    Text(LocalizedStringKey(subtitle)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    #if DEBUG
                    if course == nil {
                        Text("Сынақ үлгісі · жарияланбаған")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(brown)
                    }
                    #endif
                    if isOwned {
                        Label("Оқуды жалғастыру (\(completedCount(for: productID)))", systemImage: "play.fill")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(brown)
                    } else if let product = purchases.product(for: productID) {
                        Label(product.displayPrice, systemImage: "lock.fill")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(brown)
                    } else {
                        Label("Курс туралы", systemImage: "lock.fill")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(brown)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(ink.opacity(0.05), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func courseArtwork(course: AccessibleCourse?, productID: String, cornerRadius: CGFloat) -> some View {
        if let coverURL = course?.coverURL {
            AsyncImage(url: coverURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    courseArtworkPlaceholder(productID: productID)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityLabel(course?.title ?? "ZHANAR массаж курсы")
        } else {
            courseArtworkPlaceholder(productID: productID)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    private func courseArtworkPlaceholder(productID: String) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.96, green: 0.72, blue: 0.53), Color(red: 0.72, green: 0.43, blue: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                Image(systemName: productID == PurchaseManager.selfMassageCourseID ? "figure.mind.and.body" : "hands.sparkles")
                    .font(.system(size: 36, weight: .medium)).foregroundStyle(.white)
                Text("ZHANAR MASSAGE")
                    .font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private func sectionSymbol(for key: String) -> String {
        switch key {
        case "anatomy": "figure.cooldown"
        case "diagnostics": "heart.text.square"
        case "therapeutic": "hands.sparkles"
        case "cupping": "circle.dotted"
        case "fire": "flame"
        case "vacuum": "wind"
        case "lymphatic": "drop"
        case "honey": "leaf"
        case "preparation": "sparkles"
        case "face": "face.smiling"
        case "neck_shoulders": "figure.mind.and.body"
        case "hands": "hand.raised"
        case "legs": "figure.walk"
        case "aftercare": "heart.text.square"
        case "conclusion": "checkmark.seal"
        default: "play.rectangle"
        }
    }

    private func completedCount(for productID: String) -> Int {
        if let course = auth.accessibleCourse(for: productID) {
            let lessonIDs = Set(course.sections.flatMap { $0.lessons.map(\.id) })
            return lessonIDs.intersection(completedLessonIDs).count
        }
        return completedLessonIDs.filter { $0.hasPrefix("\(productID).") }.count
    }

    private func completedCount(for section: CourseSection) -> Int {
        if let course = auth.accessibleCourse(for: selectedProductID),
           let publishedSection = course.sections.first(where: { $0.id == section.sourceID }) {
            let lessonIDs = Set(publishedSection.lessons.map(\.id))
            return lessonIDs.intersection(completedLessonIDs).count
        }
        return completedLessonIDs.filter {
            $0.hasPrefix("\(selectedProductID).\(section.key).")
        }.count
    }

    var body: some View {
        ZStack {
            Color(red: 0.975, green: 0.965, blue: 0.95).ignoresSafeArea()
            VStack(spacing: 0) {
                if !auth.isReady && !previewMode {
                    launchLoadingContent
                } else if auth.user == nil && !previewMode {
                    SignInView(
                        auth: auth,
                        onPreview: { previewMode = true },
                        onPrivacy: { showingPrivacy = true }
                    )
                } else if screen == .root {
                    rootContent
                } else if screen == .coursePreview {
                    coursePreviewContent
                } else if screen == .course {
                    courseStructure
                } else if screen == .lesson {
                    lessonContent
                } else {
                    paywallContent
                }

                if (auth.user != nil || previewMode) && screen == .root { tabBar }
            }
        }
        .preferredColorScheme(.light)
        .task {
            purchases.setServerVerificationHandler { signedTransactionInfo, appAccountToken in
                try await auth.verifyStoreKitTransaction(signedTransactionInfo, appAccountToken: appAccountToken)
            }
            await purchases.refreshEntitlements()
            await purchases.loadProducts()
            await refreshCatalog()
        }
        .task(id: auth.user?.id) {
            guard let userID = auth.user?.id else { return }
            purchases.setServerVerificationHandler { signedTransactionInfo, appAccountToken in
                try await auth.verifyStoreKitTransaction(signedTransactionInfo, appAccountToken: appAccountToken)
            }
            await purchases.processUnfinishedTransactions()
            try? await auth.refreshVerifiedPurchases()
            await refreshCatalog()
            await syncProgress(for: userID)
            await syncLessonResume(for: userID)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                saveLoadedPlaybackPosition()
                playbackCheckpointObserver.stop()
                lessonPlayer?.pause()
                return
            }
            Task {
                if let lessonPlayer, let loadedVideoLessonID {
                    startCheckpointObserver(for: lessonPlayer, lessonID: loadedVideoLessonID, userID: loadedPlaybackUserID)
                }
                purchases.setServerVerificationHandler { signedTransactionInfo, appAccountToken in
                    try await auth.verifyStoreKitTransaction(signedTransactionInfo, appAccountToken: appAccountToken)
                }
                await purchases.refreshEntitlements()
                if auth.user != nil {
                    try? await auth.refreshVerifiedPurchases()
                    await purchases.processUnfinishedTransactions()
                }
                await refreshCatalog()
                if let userID = auth.user?.id {
                    await syncProgress(for: userID)
                    await syncLessonResume(for: userID)
                }
            }
        }
        .onChange(of: networkPath.isConnected) { _, connected in
            guard connected else { return }
            Task {
                if auth.user != nil {
                    purchases.setServerVerificationHandler { signedTransactionInfo, appAccountToken in
                        try await auth.verifyStoreKitTransaction(signedTransactionInfo, appAccountToken: appAccountToken)
                    }
                    await purchases.processUnfinishedTransactions()
                    try? await auth.refreshVerifiedPurchases()
                }
                await refreshCatalog()
                if let userID = auth.user?.id {
                    await syncProgress(for: userID)
                    await syncLessonResume(for: userID)
                }
            }
        }
        .onChange(of: purchases.purchasedProductIDs) { _, _ in
            reconcileSelectedCourseAccess()
        }
        .onChange(of: auth.verifiedCourseProductIDs) { _, _ in
            reconcileSelectedCourseAccess()
        }
        .onChange(of: auth.displayName) { _, name in
            displayName = name.isEmpty ? "Оқушы" : name
        }
        .onChange(of: auth.user?.id) { _, userID in
            // Names and phone numbers belong to one account; never carry them into another session.
            saveLoadedPlaybackPosition()
            playbackCheckpointObserver.stop()
            lessonPlayer?.pause()
            lessonPlayer = nil
            lessonVideoURL = nil
            loadedVideoLessonID = nil
            loadedPlaybackUserID = nil
            resumeCheckpoints = [:]
            lessonVideoRequestID = nil
            isLoadingLessonVideo = false
            lessonPlayback.reset()
            resumeUploadTask?.cancel()
            resumeUploadTask = nil
            progressRetryTask?.cancel()
            progressRetryTask = nil
            progressRetryAttempts = 0
            resumeRetryTask?.cancel()
            resumeRetryTask = nil
            resumeRetryAttempts = 0
            displayName = auth.user == nil ? "Оқушы" : (auth.displayName.isEmpty ? "Оқушы" : auth.displayName)
            phoneNumber = ""
            if userID == nil {
                pendingSignInDestination = nil
            } else if let destination = pendingSignInDestination {
                pendingSignInDestination = nil
                screen = destination
            }
        }
        .onChange(of: screen) { _, nextScreen in
            if nextScreen != .lesson {
                saveLoadedPlaybackPosition()
                playbackCheckpointObserver.stop()
                lessonPlayer?.pause()
                lessonPlayer = nil
                lessonVideoURL = nil
                loadedVideoLessonID = nil
                lessonVideoRequestID = nil
                isLoadingLessonVideo = false
                lessonPlayback.reset()
            }
        }
        .onChange(of: purchases.message != nil || auth.message != nil, initial: true) { _, hasMessage in
            showingMessageAlert = hasMessage
        }
        .onOpenURL { url in Task { await auth.handleAuthCallback(url) } }
        .sheet(isPresented: Binding(
            get: { auth.isPasswordRecovery },
            set: { if !$0 { auth.dismissPasswordRecovery() } }
        )) {
            PasswordRecoveryView(auth: auth)
        }
        .alert("Хабарлама", isPresented: $showingMessageAlert) {
            Button("Жақсы", role: .cancel) { purchases.message = nil; auth.message = nil }
        } message: {
            Text(LocalizedStringKey(purchases.message ?? auth.message ?? ""))
        }
        .sheet(isPresented: $showingProfileEditor) {
            profileEditor
        }
        .sheet(isPresented: $showingAdminDashboard) {
            AdminDashboardView(auth: auth)
        }
        .sheet(isPresented: $showingHelp) {
            helpSheet
        }
        .sheet(isPresented: $showingPrivacy) {
            privacySheet
        }
        .confirmationDialog(
            "Аккаунтты біржола жою керек пе?",
            isPresented: $showingDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button("Аккаунтты жою", role: .destructive) {
                guard !isDeletingAccount else { return }
                isDeletingAccount = true
                let deletedUserID = auth.user?.id
                Task {
                    defer { isDeletingAccount = false }
                    do {
                        try await auth.deleteAccount()
                        if let deletedUserID {
                            UserDefaults.standard.removeObject(forKey: "learning.completedLessonIDs.\(deletedUserID.uuidString)")
                            UserDefaults.standard.removeObject(forKey: "learning.resumeState.\(deletedUserID.uuidString)")
                            progressRevision += 1
                        }
                    }
                    catch { auth.message = "Аккаунтты жою расталмады. Аккаунт әлі қолжетімді болса, қайта кіріп, жоюды қайталаңыз." }
                }
            }
            .disabled(isDeletingAccount)
            Button("Болдырмау", role: .cancel) {}
        } message: {
            Text("Аккаунт пен оқу прогресі жойылады. App Store сатып алуы автоматты қайтарылмайды. Жойылған аккаунттағы курсқа қолжетімділікті жаңа ZHANAR аккаунтында қалпына келтіру мүмкін емес.")
        }
    }

    @ViewBuilder
    private var launchLoadingContent: some View {
        VStack(spacing: 16) {
            Image("ZhanarMark")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
            Text("ZHANAR")
                .font(.system(size: 13, weight: .bold))
                .tracking(2)
                .foregroundStyle(brown)
            ProgressView().tint(brown)
                .padding(.top, 4)
            Text("Аккаунт жүктелуде…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rootContent: some View {
        switch selectedTab {
        case .home: homeContent
        case .courses: coursesContent
        case .profile: profileContent
        }
    }

    private var homeContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                cachedCatalogNotice
                if let destination = latestResumeDestination {
                    Button { resumeLesson(destination) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(brown, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Оқуды жалғастыру")
                                    .font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
                            HStack(spacing: 4) {
                                Text(LocalizedStringKey(localizedCopy(destination.course.title, russian: destination.course.titleRu)))
                                Text("·")
                                Text(LocalizedStringKey(localizedLessonTitle(destination.lesson)))
                            }
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .padding(15)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Курс іздеу", text: $courseSearchText)
                        .font(.system(size: 14))
                        .textInputAutocapitalization(.never)
                    if !courseSearchText.isEmpty {
                        Button { courseSearchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(15)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("Менің курстарым", action: "Барлығы") { selectedTab = .courses }
                    let ownedIDs = searchedCatalogProductIDs.filter { hasCourseAccess($0) }
                    if !ownedIDs.isEmpty {
                        ForEach(ownedIDs, id: \.self) { courseCard($0) }
                    } else {
                        noPurchasedCoursesState
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("Ұсынамыз", action: "") {}
                    let recommendedIDs = searchedCatalogProductIDs.filter { !hasCourseAccess($0) }
                    if !recommendedIDs.isEmpty {
                        ForEach(recommendedIDs, id: \.self) { courseCard($0) }
                    } else if searchedCatalogProductIDs.isEmpty {
                        catalogStatusView
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(cream).frame(width: 48, height: 48)
                Image(systemName: "sparkles").font(.system(size: 21, weight: .medium)).foregroundStyle(brown)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Сәлем, \(localizedDisplayName(displayName).split(separator: " ").first.map(String.init) ?? "дос") 👋")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Оқуды жалғастырайық").font(.system(size: 19, weight: .bold)).foregroundStyle(ink)
            }
            Spacer()
            Button { showingHelp = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 21))
                    .foregroundStyle(ink)
                    .padding(12)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Көмек")
            catalogRefreshButton
        }
    }

    private var coursesContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    pageTitle("Курстар", subtitle: "Өзіңе лайық курсты таңда")
                    Spacer(minLength: 0)
                    catalogRefreshButton
                }
                cachedCatalogNotice
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Курс іздеу", text: $courseSearchText).font(.system(size: 14))
                    if !courseSearchText.isEmpty {
                        Button { courseSearchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 16))
                if !catalogCategoryKeys.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            categoryChip(title: languageSettings.language == .russian ? "Все" : "Барлығы", key: nil)
                            ForEach(catalogCategoryKeys, id: \.self) { key in
                                categoryChip(title: categoryLabel(for: key), key: key)
                            }
                        }
                    }
                }
                Text("Барлық курстар").font(.system(size: 18, weight: .bold)).foregroundStyle(ink)
                if !filteredCatalogProductIDs.isEmpty {
                    ForEach(filteredCatalogProductIDs, id: \.self) { courseCard($0) }
                } else {
                    catalogStatusView
                }
            }.padding(20)
        }
    }

    private func categoryChip(title: String, key: String?) -> some View {
        let selected = selectedCatalogCategory == key
        return Button { selectedCatalogCategory = key } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .white : ink)
                .padding(.horizontal, 15).padding(.vertical, 10)
                .background(selected ? brown : .white, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var courseStructure: some View {
        return VStack(spacing: 0) {
            topBar(title: "Курс құрылымы") { screen = .root }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(selectedCourseTitle)).font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(brown)
                        Text(LocalizedStringKey(selectedCourseTitle))
                            .font(.system(size: 26, weight: .bold)).foregroundStyle(ink)
                        Text("Курсты бөлімдер бойынша өтіңіз").font(.system(size: 13)).foregroundStyle(.secondary)
                    }.padding(.top, 10)

                    sectionTimeline(currentSectionID: selectedSectionID)

                    if courseSections.isEmpty {
                        unavailableCourseProgramNotice
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(courseSections.enumerated()), id: \.offset) { index, section in
                            Button {
                                selectedSection = section.title
                                selectedSectionID = section.id
                                selectedLessonNumber = 1
                                screen = .lesson
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(index == 0 ? Color(red: 0.98, green: 0.78, blue: 0.23) : Color(red: 0.27, green: 0.82, blue: 0.58)).frame(width: 30, height: 30)
                                        Circle().stroke(ink, lineWidth: 1.5).frame(width: 30, height: 30)
                                        Image(systemName: section.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(LocalizedStringKey(localizedSectionTitle(section.title, sourceID: section.sourceID))).font(.system(size: 14, weight: .bold)).foregroundStyle(ink)
                                        Text("\(completedCount(for: section))/\(section.lessons) \(lessonCountNoun(section.lessons))")
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                        ProgressView(value: Double(completedCount(for: section)), total: Double(max(section.lessons, 1)))
                                            .tint(brown)
                                            .frame(maxWidth: 150)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < courseSections.count - 1 { Divider().padding(.leading, 58) }
                        }
                    }
                    .background(.white, in: RoundedRectangle(cornerRadius: 18))

                }.padding(20).padding(.bottom, 20)
            }
        }
    }

    private var coursePreviewContent: some View {
        let course = auth.accessibleCourse(for: selectedProductID)
        let sections = courseSections
        return VStack(spacing: 0) {
            topBar(title: "Курс туралы") { screen = .root }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    courseArtwork(course: course, productID: selectedProductID, cornerRadius: 24)
                    .frame(height: 170)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(selectedCourseTitle))
                            .font(.system(size: 25, weight: .bold)).foregroundStyle(ink)
                        if let subtitle = course?.subtitle, !subtitle.isEmpty {
                            Text(LocalizedStringKey(localizedCopy(subtitle, russian: course?.subtitleRu))).font(.system(size: 13, weight: .semibold)).foregroundStyle(brown)
                        }
                        Text(LocalizedStringKey(selectedCourseDescription))
                            .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(4)
                    }

                    if let instructorName = course?.instructorName?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !instructorName.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Оқытушы")
                                .font(.system(size: 18, weight: .bold)).foregroundStyle(ink)
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 38)).foregroundStyle(brown.opacity(0.85))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(instructorName).font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
                                    if let title = localizedOptionalCopy(kazakh: course?.instructorTitle, russian: course?.instructorTitleRu) {
                                        Text(title)
                                            .font(.system(size: 12, weight: .medium)).foregroundStyle(brown)
                                    }
                                    if let bio = localizedOptionalCopy(kazakh: course?.instructorBio, russian: course?.instructorBioRu) {
                                        Text(bio)
                                            .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(3)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        }
                    }

                    HStack(spacing: 12) {
                        courseFact(value: "\(sections.count)", label: sectionCountNoun(sections.count), symbol: "square.stack.3d.up")
                        courseFact(value: "\(sections.reduce(0) { $0 + $1.lessons })", label: lessonCountNoun(sections.reduce(0) { $0 + $1.lessons }), symbol: "play.rectangle")
                        if let duration = totalCourseDurationSeconds(for: course) {
                            courseFact(value: formattedCourseDuration(duration), label: "Ұзақтығы", symbol: "clock")
                        } else {
                            courseFact(value: "Видео", label: "Формат", symbol: "video")
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Курс бағдарламасы").font(.system(size: 19, weight: .bold)).foregroundStyle(ink)
                        if sections.isEmpty {
                            unavailableCourseProgramNotice
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                                DisclosureGroup {
                                    if let publishedSections = course?.sections,
                                       publishedSections.indices.contains(index),
                                       !publishedSections[index].lessons.isEmpty {
                                        ForEach(publishedSections[index].lessons) { lesson in
                                            Group {
                                                if CourseAccessPolicy.canOpenLesson(
                                                    courseIsPublished: course?.isPublished ?? false,
                                                    lessonIsPreview: lesson.isPreview,
                                                    hasVerifiedCourseEntitlement: hasCourseAccess(selectedProductID)
                                                ) {
                                                    Button {
                                                        selectedSection = section.title
                                                        selectedSectionID = publishedSections[index].id
                                                        guard let lessonIndex = publishedSections[index].lessons.firstIndex(where: { $0.id == lesson.id }) else { return }
                                                        selectedLessonNumber = lessonIndex + 1
                                                        guard auth.user != nil else {
                                                            returnToSignIn(resumeAt: .lesson)
                                                            return
                                                        }
                                                        screen = .lesson
                                                    } label: {
                                                        coursePreviewLessonRow(lesson, isUnlocked: true)
                                                    }
                                                    .buttonStyle(.plain)
                                                } else {
                                                    coursePreviewLessonRow(lesson, isUnlocked: false)
                                                }
                                            }
                                        }
                                    } else {
                                        Text("\(section.lessons) \(lessonCountNoun(section.lessons))")
                                            .font(.system(size: 13)).foregroundStyle(.secondary)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: section.symbol).foregroundStyle(brown).frame(width: 22)
                                        Text(LocalizedStringKey(localizedSectionTitle(section.title, sourceID: section.sourceID))).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                                        Spacer()
                                        Text("\(section.lessons)").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 9)
                                }
                                if index < sections.count - 1 { Divider() }
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(20)
                .padding(.bottom, 16)
            }
            .safeAreaInset(edge: .bottom) {
                if !sections.isEmpty {
                    Button {
                        guard auth.user != nil || previewMode else {
                            returnToSignIn(resumeAt: .paywall)
                            return
                        }
                        screen = hasCourseAccess(selectedProductID) ? .course : .paywall
                    } label: {
                        HStack {
                            Text(auth.user == nil && !previewMode ? "Сатып алу үшін кіру" : hasCourseAccess(selectedProductID) ? "Оқуды бастау" : "Курсқа қол жеткізу")
                            Spacer()
                            if let product = purchases.product(for: selectedProductID) {
                                Text(product.displayPrice)
                            }
                        }
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 16)
                        .background(brown, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .disabled(purchases.isWorking)
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
                    .background(.ultraThinMaterial)
                }
            }
        }
    }

    private var unavailableCourseProgramNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Курс бағдарламасы қазір қолжетімсіз. Каталогты жаңартып көріңіз.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
            Button("Каталогты жаңарту") {
                Task { await refreshCatalog() }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(brown)
            .disabled(isRefreshingCatalog)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func courseFact(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(brown)
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
            Text(LocalizedStringKey(label)).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
    }

    private func sectionCountNoun(_ count: Int) -> String {
        russianCountNoun(count, kazakh: "Бөлім", one: "Раздел", few: "Раздела", many: "Разделов")
    }

    private func lessonCountNoun(_ count: Int) -> String {
        russianCountNoun(count, kazakh: "сабақ", one: "урок", few: "урока", many: "уроков")
    }

    private func russianCountNoun(_ count: Int, kazakh: String, one: String, few: String, many: String) -> String {
        guard languageSettings.language == .russian else { return kazakh }
        let lastTwo = abs(count) % 100
        if (11...14).contains(lastTwo) { return many }
        switch abs(count) % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }

    private func totalCourseDurationSeconds(for course: AccessibleCourse?) -> Int? {
        guard let course else { return nil }
        let lessons = course.sections.flatMap(\.lessons)
        guard !lessons.isEmpty,
              lessons.allSatisfy({ ($0.durationSeconds ?? 0) > 0 }) else { return nil }
        return lessons.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
    }

    private func formattedCourseDuration(_ seconds: Int) -> String {
        let totalMinutes = max(1, (seconds + 59) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if languageSettings.language == .russian {
            return hours > 0 ? "\(hours) ч \(minutes) мин" : "\(totalMinutes) мин"
        }
        return hours > 0 ? "\(hours) сағ \(minutes) мин" : "\(totalMinutes) мин"
    }

    private func coursePreviewLessonRow(_ lesson: PublishedLesson, isUnlocked: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isUnlocked ? "play.circle" : "lock.fill")
                .font(.system(size: 13)).foregroundStyle(brown)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(localizedLessonTitle(lesson))).font(.system(size: 13, weight: .medium)).foregroundStyle(ink)
                if isUnlocked && auth.user == nil {
                    Text("Көру үшін аккаунтқа кіріңіз.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let duration = lesson.durationSeconds, duration > 0 {
                    Text("\(duration / 60) мин").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if isUnlocked {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 7)
    }

    private var paywallContent: some View {
        VStack(spacing: 0) {
            topBar(title: "Курсқа қол жеткізу") { screen = .coursePreview }
            ScrollView {
                VStack(spacing: 22) {
                    courseArtwork(course: auth.accessibleCourse(for: selectedProductID), productID: selectedProductID, cornerRadius: 28)
                        .frame(height: 190)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(LocalizedStringKey(selectedCourseTitle))
                            .font(.system(size: 25, weight: .bold)).foregroundStyle(ink)
                        Text(LocalizedStringKey(selectedCourseDescription))
                            .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(4)
                        Text(isLocalStoreKitDemo
                             ? "Бұл — жергілікті StoreKit сынағы. Сатып алу тек Debug нұсқасында тексеріледі және ZHANAR аккаунтына сақталмайды."
                             : "Сатып алғаннан кейін курс ZHANAR аккаунтыңызға байланып, осы және басқа құрылғыларда сол аккаунтпен кіргенде қолжетімді болады.")
                            .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                        Label("Видео сабақтар мен бөлімдер", systemImage: "play.rectangle")
                        Label("Оқу прогресін сақтау", systemImage: "chart.bar")
                        Label("Сатып алуды қалпына келтіру", systemImage: "arrow.clockwise")
                    }
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(ink).frame(maxWidth: .infinity, alignment: .leading)

                    if courseSections.isEmpty {
                        unavailableCourseProgramNotice
                    } else if auth.user == nil && !previewMode {
                        Button("Сатып алу үшін ZHANAR аккаунтына кіріңіз") {
                            returnToSignIn()
                        }
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(brown, in: RoundedRectangle(cornerRadius: 15))
                    } else if let product = purchases.product(for: selectedProductID),
                              let purchaseAccountToken {
                        Button {
                            Task { await purchases.purchase(productID: selectedProductID, appAccountToken: purchaseAccountToken) }
                        } label: {
                            HStack {
                                if purchases.isWorking { ProgressView().tint(.white) }
                                if purchases.isWorking {
                                    Text("Өңделуде…")
                                } else {
                                    Text("Сатып алу · \(product.displayPrice)")
                                }
                            }
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(brown, in: RoundedRectangle(cornerRadius: 15))
                        }
                        .disabled(purchases.isWorking)
                    } else {
                        VStack(spacing: 10) {
                            if purchases.isLoadingProducts {
                                ProgressView()
                                Text("App Store бағасы жүктелуде").font(.system(size: 13)).foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
                                Text(purchases.unavailableProductIDs.contains(selectedProductID)
                                     ? "Бұл курстың App Store өнімі әлі бапталмаған немесе қолжетімсіз."
                                     : purchases.productLoadFailed
                                         ? "App Store-мен байланыс орнатылмады. Интернетті тексеріп, қайталап көріңіз."
                                         : "App Store бағасы қазір қолжетімсіз. Қайталап жүктеңіз.")
                                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button("Қайта жүктеу") { Task { await refreshCatalog() } }
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(brown)
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 18)
                    }

                    Button {
                        restorePurchasesOrRequestSignIn()
                    } label: {
                        Text("Бұрынғы сатып алуды қалпына келтіру")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(brown)
                    }
                    .disabled(purchases.isWorking)
                    if !isLocalStoreKitDemo {
                        Text("Төлем Apple аккаунтыңыз арқылы алынады. Курс осы ZHANAR аккаунтына тіркеледі. Баға сатып алуды растау алдында көрсетіледі.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }.padding(20)
            }
        }
    }

    private var isLocalStoreKitDemo: Bool {
        #if DEBUG
        return previewMode || auth.accessibleCourse(for: selectedProductID) == nil
        #else
        return false
        #endif
    }

    private var lessonContent: some View {
        let lessonDescription = currentPublishedLesson.map { localizedCopy($0.description, russian: $0.descriptionRu) } ?? "Массаж негіздері және қауіпсіздік ережелері. Сабақты көріп болған соң, оны аяқталған деп белгілеңіз."
        let sectionTitle = localizedSectionTitle(selectedSection, sourceID: selectedSectionID)
        return VStack(spacing: 0) {
            topBar(title: sectionTitle) { screen = .course }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    sectionTimeline(currentSectionID: selectedSectionID)

                    Text(LocalizedStringKey(sectionTitle)).font(.system(size: 25, weight: .bold)).foregroundStyle(ink)
                    Group {
                        if let lessonPlayer, !lessonPlayback.failed {
                            VideoPlayer(player: lessonPlayer)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20).fill(LinearGradient(colors: [Color(red: 0.87, green: 0.78, blue: 0.70), Color(red: 0.53, green: 0.38, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                VStack(spacing: 12) {
                                    if isLoadingLessonVideo {
                                        ProgressView().tint(.white)
                                    } else if lessonVideoLoadFailed || lessonPlayback.failed {
                                        Image(systemName: "wifi.exclamationmark").font(.system(size: 36, weight: .light)).foregroundStyle(.white)
                                    } else {
                                        Image(systemName: "video.slash").font(.system(size: 40, weight: .light)).foregroundStyle(.white)
                                    }
                                    Text(isLoadingLessonVideo ? "ВИДЕО ЖҮКТЕЛУДЕ" : (lessonVideoLoadFailed || lessonPlayback.failed) ? "ВИДЕО ЖҮКТЕЛМЕДІ" : "ВИДЕО САБАҚ")
                                        .font(.system(size: 11, weight: .bold)).tracking(1.4).foregroundStyle(.white)
                                    if lessonVideoLoadFailed || lessonPlayback.failed {
                                        Text("Интернетті тексеріп, қайталап көріңіз.")
                                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                                        Button("Қайталап жүктеу") {
                                            Task { await loadCurrentLessonVideo() }
                                        }
                                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(.white.opacity(0.2), in: Capsule())
                                        .disabled(isLoadingLessonVideo)
                                    } else if !isLoadingLessonVideo {
                                        Text("Видео материал жақында қосылады")
                                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 245)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 8) {
                        if let currentPublishedLesson {
                            Text(LocalizedStringKey(localizedLessonTitle(currentPublishedLesson)))
                                .font(.system(size: 19, weight: .bold)).foregroundStyle(ink)
                        } else {
                            Text("Кіріспе сабақ №\(selectedLessonNumber)")
                                .font(.system(size: 19, weight: .bold)).foregroundStyle(ink)
                        }
                        Text(LocalizedStringKey(lessonDescription.isEmpty ? "Сабақты көріп болған соң, оны аяқталған деп белгілеңіз." : lessonDescription))
                            .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                    }

                    if canTrackCurrentLesson {
                        Button {
                            setCurrentLessonComplete()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isCurrentLessonComplete ? "checkmark.circle.fill" : "checkmark.circle")
                                Text(isCurrentLessonComplete ? "САБАҚ ӨТІЛДІ · 1 БАЛЛ" : "САБАҚТЫ ӨТІЛДІ ДЕП БЕЛГІЛЕУ · 1 БАЛЛ")
                            }
                            .font(.system(size: 12, weight: .bold)).tracking(0.3)
                            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(isCurrentLessonComplete ? Color(red: 0.22, green: 0.59, blue: 0.39) : .black, in: RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(.plain).disabled(isCurrentLessonComplete)
                    } else if currentPublishedLesson?.isPreview == true {
                        Button { screen = .paywall } label: {
                            Label("Толық курсты ашу", systemImage: "lock.open")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(brown, in: RoundedRectangle(cornerRadius: 13))
                        }.buttonStyle(.plain)
                    }

                    HStack {
                        Button {
                            if selectedLessonNumber > 1 {
                                selectedLessonNumber -= 1
                            }
                        } label: {
                            Label("Алдыңғы сабақ", systemImage: "arrow.left").foregroundStyle(selectedLessonNumber > 1 ? brown : .secondary)
                        }.buttonStyle(.plain).disabled(selectedLessonNumber == 1)
                        Spacer()
                        Button {
                            if selectedLessonNumber < currentSectionLessonCount,
                               hasCourseAccess(selectedProductID) || publishedLesson(at: selectedLessonNumber + 1)?.isPreview == true {
                                selectedLessonNumber += 1
                            }
                        } label: {
                            Label(selectedLessonNumber < currentSectionLessonCount ? "Келесі сабақ" : "Бөлім аяқталды", systemImage: "arrow.right").labelStyle(.titleAndIcon).foregroundStyle(brown)
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedLessonNumber >= currentSectionLessonCount || (!hasCourseAccess(selectedProductID) && publishedLesson(at: selectedLessonNumber + 1)?.isPreview != true))
                    }.font(.system(size: 12, weight: .semibold)).padding(.vertical, 4)
                }.padding(20).padding(.bottom, 24)
            }
        }
        .task(id: currentLessonID) { await loadCurrentLessonVideo() }
    }

    private var profileContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageTitle("Жеке кабинет", subtitle: "Оқу барысыңыз бен баптаулар")
                    HStack(spacing: 14) {
                    ZStack { Circle().fill(cream); Image(systemName: "person.fill").foregroundStyle(brown) }.frame(width: 62, height: 62)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localizedDisplayName(auth.user == nil ? displayName : (auth.displayName.isEmpty ? "Оқушы" : auth.displayName)))
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(ink)
                        Text(LocalizedStringKey(accountSubtitle))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        profileDraftName = auth.user == nil ? displayName : auth.displayName
                        showingProfileEditor = true
                    } label: { Image(systemName: "pencil").foregroundStyle(brown) }
                }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    .disabled(isDeletingAccount)
                if isDeletingAccount {
                    HStack(spacing: 10) {
                        ProgressView().tint(brown)
                        Text("Аккаунт жойылып жатыр…")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Аккаунт жойылып жатыр. Күте тұрыңыз.")
                }
                HStack(spacing: 12) {
                    statCard(value: "\(completedLessonCount)", label: "Өтілген сабақ", symbol: "checkmark.circle")
                    statCard(value: "\(completedLessonCount)", label: "Жиналған балл", symbol: "star")
                }
                VStack(spacing: 0) {
                    AppLanguagePicker().padding(.vertical, 12)
                    Divider()
                    profileRow("Менің курстарым", symbol: "play.rectangle") { selectedTab = .courses }
                    if auth.isCourseAdmin {
                        Divider()
                        profileRow("Әкімші панелі", symbol: "slider.horizontal.3") { showingAdminDashboard = true }
                    }
                    Divider()
                    if purchases.isWorking {
                        HStack(spacing: 12) {
                            ProgressView().tint(brown).frame(width: 24)
                            Text("App Store операциясы орындалып жатыр…")
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 15)
                        .accessibilityLabel("App Store операциясы орындалып жатыр. Күте тұрыңыз.")
                    } else {
                        profileRow("Сатып алуды қалпына келтіру", symbol: "arrow.clockwise") {
                            restorePurchasesOrRequestSignIn()
                        }
                    }
                    Divider()
                    profileRow("Деректер мен құпиялылық", symbol: "hand.raised") { showingPrivacy = true }
                    Divider()
                    profileRow("Көмек", symbol: "questionmark.circle") { showingHelp = true }
                    Divider()
                    if auth.user != nil {
                        Divider()
                        profileRow("Аккаунттан шығу", symbol: "rectangle.portrait.and.arrow.right") {
                            Task {
                                do { try await auth.signOut() }
                                catch { auth.message = AuthManager.userFacingMessage(for: error, context: .signOut) }
                            }
                        }
                        Divider()
                        profileRow("Аккаунтты жою", symbol: "person.crop.circle.badge.minus") {
                            showingDeleteAccountConfirmation = true
                        }
                    }
                }.padding(.horizontal, 14).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    .disabled(isDeletingAccount)
            }.padding(20)
        }
    }

    private var profileEditor: some View {
        NavigationStack {
            Form {
                TextField("Аты-жөніңіз", text: $profileDraftName)
                    .textInputAutocapitalization(.words)
                LabeledContent("Расталған телефон", value: auth.user?.phone ?? phoneNumber)
            }
            .navigationTitle("Профильді өңдеу")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Дайын") {
                        let savedName = profileDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !savedName.isEmpty else { return }
                        Task {
                            isSavingProfile = true
                            defer { isSavingProfile = false }
                            do {
                                if auth.user != nil {
                                    try await auth.updateDisplayName(savedName)
                                } else {
                                    displayName = savedName
                                }
                                showingProfileEditor = false
                            } catch {
                                profileSaveError = AuthManager.userFacingMessage(for: error, context: .profileSave)
                            }
                        }
                    }
                    .disabled(isSavingProfile || profileDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Болдырмау") { showingProfileEditor = false }
                }
            }
        }
        .alert("Аты сақталмады", isPresented: Binding(
            get: { profileSaveError != nil },
            set: { if !$0 { profileSaveError = nil } }
        )) {
            Button("Жақсы", role: .cancel) { profileSaveError = nil }
        } message: {
                        Text(LocalizedStringKey(profileSaveError ?? "Қайталап көріңіз."))
        }
        .presentationDetents([.medium])
    }

    private var helpSheet: some View {
        NavigationStack {
            List {
                Section("Аккаунт") {
                    DisclosureGroup("Қосымшаға қалай кіремін?") {
                        Text("Email мен құпиясөз арқылы аккаунт ашыңыз немесе кіріңіз. Email-ді растау керек болса, поштадағы сілтемені ашыңыз. Телефон арқылы кірсеңіз, +7 нөмірін енгізіп, SMS-кодты растаңыз. Құпиясөзді ұмытсаңыз, кіру бетінде қалпына келтіру сілтемесін сұратыңыз.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Курстар мен төлем") {
                    DisclosureGroup("Неліктен каталогта курс көрінбейді?") {
                        Text("Каталогта мектеп жариялаған курстар ғана көрсетіледі. Курс жариялануы үшін оның сабақтары мен видео материалдары дайын болуы керек.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Сатып алған курсымды қалай қалпына келтіремін?") {
                        Text("Қосымшадағы “Сатып алуды қалпына келтіру” тармағын таңдаңыз. Бұрын сатып алған Apple аккаунтымен және сол кезде пайдаланған ZHANAR аккаунтымен кіріңіз. ZHANAR аккаунтын жойғаннан кейін сатып алуды жаңа ZHANAR аккаунтына көшіру мүмкін емес. Қажет болса, мектептің қолдау қызметіне жүгініңіз.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Оқу барысы") {
                    DisclosureGroup("Сабақтарым мен прогресім сақтала ма?") {
                        Text("Сабақты аяқталған деп белгілегенде прогресс құрылғыда сақталады және интернет қолжетімді болғанда аккаунтыңызбен синхрондалады.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Неліктен видеоны көре алмаймын?") {
                        Text("Толық сабақтарға жарамды сатып алу құқығы бар аккаунттан кіруге болады. Кейбір курстарда сатып алусыз көруге болатын алдын ала қарау сабағы бар. Видео ашылмаса, интернетті тексеріп, сабақты қайта жүктеп көріңіз. Мәселе шешілмесе, мектептің қолдау қызметіне жүгініңіз.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if let supportURL {
                    Section("Байланыс") {
                        Link(destination: supportURL) {
                            Label("Мектептің қолдау қызметі", systemImage: "questionmark.circle")
                        }
                    }
                } else {
                    Section("Байланыс") {
                        Text("Мектептің ресми қолдау сілтемесі әзірге қосылмаған.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Көмек")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Дайын") { showingHelp = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var privacySheet: some View {
        NavigationStack {
            List {
                Section("Қандай деректер пайдаланылады?") {
                    Text("Email мен құпиясөз аккаунт ашу және оған кіру үшін пайдаланылады. Телефон арқылы кіруді таңдасаңыз, телефон нөмірі мен SMS-код та өңделеді. Аты-жөніңізді профильге қалауыңызша қосуға болады. Аккаунт идентификаторы, аяқталған сабақтар және курсқа қолжетімділік оқу прогресін сақтау және синхрондау үшін өңделеді. Прогрестің көшірмесі құрылғыда аккаунт бойынша сақталады: шығу оны өшірмейді, аккаунтты жою сәтті аяқталғанда өшіріледі.")
                    Text("App Store сатып алуы курсты ашу және қалпына келтіру үшін тексеріледі. Қосымша банк картасының нөмірін алмайды; төлемді Apple өңдейді.")
                }
                Section("Қызметтер") {
                    Text("Supabase аккаунтты, профильді, оқу прогресін және жеке курс видеоларына қолжетімділікті басқарады. Email растау хаттарын қосылған SMTP провайдері жеткізеді. Телефон арқылы кіру қосылса, SMS-кодтарды SMS провайдері жібереді.")
                    Text("Қауіпсіздік пен диагностика үшін Supabase сұрау журналдарында IP-мекенжай, сұрау уақыты және техникалық желі деректері болуы мүмкін. IP-мекенжайдан шамамен қала немесе ел анықталуы ықтимал. Бұл деректер жарнама үшін қолданылмайды.")
                    Text("Apple App Store төлемді өңдейді және сатып алуды растауға қажет қолтаңбалы транзакцияны береді. Бұл нұсқада жарнамаға арналған трекинг қолданылмайды.")
                }
                Section("Аккаунтты жою және сатып алу") {
                    Text("Профильдегі “Аккаунтты жою” пәрмені аккаунтты, оның email немесе телефон нөмірін, профильді және сервердегі оқу прогресін жояды. Apple транзакциясын тексеру және қайтару күйін сақтау үшін аккаунттан бөлек техникалық жазба қалуы мүмкін: транзакция идентификаторлары, курс өнімі, сатып алу/қайтару уақыты және App Store хабарландыруының техникалық деректері. Онда email, телефон нөмірі немесе профиль аты болмайды. Қауіпсіздік үшін бұл жазба бұрынғы ZHANAR аккаунтына байланып қалады; сатып алуды жаңа ZHANAR аккаунтына көшіру қолдау көрсетілмейді. Сақтау мерзімін ұйым жарияламас бұрын көрсетуі керек.")
                }
                if privacyPolicyURL == nil || supportURL == nil {
                    Section("Маңызды") {
                        Text("Мектептің ресми құпиялық саясаты немесе қолдау сілтемесі әзірге қосылмаған.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Құқықтық құжаттар") {
                    if let privacyPolicyURL {
                        Link(destination: privacyPolicyURL) {
                            Label("Мектептің құпиялық саясаты", systemImage: "hand.raised")
                        }
                    }
                    Link(destination: termsOfUseURL ?? appleStandardEULAURL) {
                        Label(termsOfUseURL == nil ? "Apple стандартты лицензиясы (EULA)" : "Пайдалану шарттары", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("Деректер мен құпиялылық")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Дайын") { showingPrivacy = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon).font(.system(size: 18, weight: .semibold))
                        Text(LocalizedStringKey(tab.rawValue)).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? brown : .gray)
                    .frame(maxWidth: .infinity).padding(.top, 11).padding(.bottom, 6)
                }.buttonStyle(.plain)
            }
        }
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.07)).frame(height: 1) }
    }

    private var catalogEmptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical").font(.system(size: 22)).foregroundStyle(brown)
            Text("Жаңа курстар дайындалып жатыр. Жақында оралыңыз.")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var cachedCatalogNotice: some View {
        if !auth.accessibleCourses.isEmpty && (auth.isLoadingCourses || auth.courseLoadMessage != nil) {
            Label("Соңғы сақталған каталог көрсетіліп тұр. Интернетке қосылып, жаңартыңыз.", systemImage: "wifi.exclamationmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("Офлайн режим. Соңғы сақталған каталог көрсетіліп тұр.")
        }
    }

    private var catalogRefreshButton: some View {
        Button {
            Task { await refreshCatalog() }
        } label: {
            Group {
                if isRefreshingCatalog {
                    ProgressView().tint(brown)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ink)
                }
            }
            .frame(width: 44, height: 44)
            .background(.white, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshingCatalog)
        .accessibilityLabel("Каталогты жаңарту")
    }

    @ViewBuilder
    private var catalogStatusView: some View {
        if auth.isLoadingCourses {
            HStack(spacing: 12) {
                ProgressView().tint(brown)
                Text("Каталог жүктелуде…").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
        } else if let message = auth.courseLoadMessage {
            VStack(alignment: .leading, spacing: 12) {
                Label(LocalizedStringKey(message), systemImage: "wifi.exclamationmark").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Button {
                    Task { await refreshCatalog() }
                } label: {
                    Label("Қайта жүктеу", systemImage: "arrow.clockwise").font(.system(size: 13, weight: .bold)).foregroundStyle(brown)
                }.buttonStyle(.plain)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
        } else if !courseSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCatalogCategory != nil {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(brown)
                Text("Сұрауыңыз бойынша курс табылмады.").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
        } else {
            catalogEmptyState
        }
    }

    private var noPurchasedCoursesState: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle").font(.system(size: 22)).foregroundStyle(brown)
            Text("Курстарыңызды осы жерден көресіз. Каталогтан курс таңдаңыз.")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func pageTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title)).font(.system(size: 27, weight: .bold)).foregroundStyle(ink)
            Text(LocalizedStringKey(subtitle)).font(.system(size: 13)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
    }

    private func sectionHeading(_ title: String, action: String, onTap: @escaping () -> Void) -> some View {
        HStack {
            Text(LocalizedStringKey(title)).font(.system(size: 18, weight: .bold)).foregroundStyle(ink)
            Spacer()
            if !action.isEmpty {
                Button(action: onTap) {
                    Text(LocalizedStringKey(action))
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(brown)
            }
        }
    }

    private func localizedDisplayName(_ name: String) -> String {
        name == "Оқушы" ? languageSettings.language.localized("Оқушы") : name
    }

    private func topBar(title: String, back: @escaping () -> Void) -> some View {
        HStack {
            Button(action: back) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(ink).frame(width: 38, height: 38).background(.white, in: Circle()) }
            Spacer()
            Text(LocalizedStringKey(title)).font(.system(size: 17, weight: .bold)).foregroundStyle(ink).lineLimit(1)
            Spacer()
            Menu {
                Button { showingHelp = true } label: {
                    Label("Көмек", systemImage: "questionmark.circle")
                }
                Button { showingPrivacy = true } label: {
                    Label("Деректер мен құпиялылық", systemImage: "hand.raised")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ink)
                    .frame(width: 38, height: 38)
                    .background(.white, in: Circle())
            }
            .accessibilityLabel("Қосымша әрекеттер")
        }.padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func statCard(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(brown)
            Text(value).font(.system(size: 24, weight: .bold)).foregroundStyle(ink)
            Text(LocalizedStringKey(label)).font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func sectionTimeline(currentSectionID: String) -> some View {
        let currentIndex = courseSections.firstIndex(where: { $0.id == currentSectionID }) ?? 0
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Image(systemName: "house.fill").foregroundStyle(brown)
                ForEach(Array(courseSections.enumerated()), id: \.offset) { index, section in
                    if index > 0 { Rectangle().fill(ink.opacity(0.18)).frame(width: 12, height: 1) }
                    ZStack {
                        Circle().fill(index < currentIndex ? Color(red: 0.25, green: 0.82, blue: 0.57) : index == currentIndex ? Color(red: 0.98, green: 0.78, blue: 0.23) : cream)
                        Circle().stroke(ink.opacity(0.65), lineWidth: 1.2)
                        Text("\(index + 1)").font(.system(size: 12, weight: .bold)).foregroundStyle(ink)
                    }
                    .frame(width: 32, height: 32)
                    .accessibilityLabel("\(section.title), бөлім \(index + 1)")
                }
            }.padding(14)
        }.background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func profileRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(brown).frame(width: 24)
                Text(LocalizedStringKey(title)).font(.system(size: 14, weight: .medium)).foregroundStyle(ink)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }.padding(.vertical, 15)
        }.buttonStyle(.plain)
    }

    private func setCurrentLessonComplete() {
        guard canTrackCurrentLesson else { return }
        var ids = completedLessonIDs
        let lessonID = currentLessonID
        guard ids.insert(lessonID).inserted else { return }
        let sortedIDs = ids.sorted()
        guard let data = try? JSONEncoder().encode(sortedIDs),
              let encoded = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(encoded, forKey: "learning.completedLessonIDs.\(auth.user?.id.uuidString ?? "preview")")
        progressRevision += 1
        if canSyncCurrentLessonProgress, let userID = auth.user?.id {
            Task {
                do {
                    try await auth.markLessonComplete(lessonID, for: userID)
                    progressRetryAttempts = 0
                } catch {
                    guard auth.user?.id == userID else { return }
                    auth.message = "Прогресс құрылғыда сақталды, бірақ серверге жіберілмеді. Қайталап көреміз."
                    scheduleProgressRetry(for: userID)
                }
            }
        }
    }

    private func returnToSignIn(resumeAt destination: AppScreen? = nil) {
        pendingSignInDestination = destination ?? (screen == .coursePreview || screen == .paywall ? screen : nil)
        previewMode = false
        screen = .root
        auth.message = "Оқу, сатып алу және прогресті сақтау үшін телефон нөміріңізбен кіріңіз."
    }

    private func restorePurchasesOrRequestSignIn() {
        let localPreview = auth.user == nil && previewMode
        let requestedUserID = auth.user?.id
        guard auth.user != nil || localPreview else {
            returnToSignIn()
            return
        }
        Task {
            let restored = await purchases.restorePurchases()
            guard auth.user?.id == requestedUserID else { return }
            if localPreview {
                guard previewMode else { return }
                if restored {
                    let hasLocalAccess = purchases.localTestingProductIDs.contains {
                        purchases.hasLocalTestingAccess(to: $0, userID: purchaseAccountToken)
                    }
                    purchases.message = hasLocalAccess
                        ? "Сатып алуларыңыз қалпына келтірілді."
                        : "Қалпына келтірілетін сатып алулар табылмады."
                }
                return
            }
            do {
                try await auth.refreshVerifiedPurchases()
                guard auth.user?.id == requestedUserID else { return }
                await refreshCatalog()
                guard auth.user?.id == requestedUserID else { return }
                if restored {
                    purchases.message = auth.verifiedCourseProductIDs.isEmpty
                        ? "Қалпына келтірілетін сатып алулар табылмады."
                        : "Сатып алуларыңыз қалпына келтірілді."
                }
            } catch {
                guard auth.user?.id == requestedUserID else { return }
                auth.message = "Сатып алуды серверден тексеру мүмкін болмады. Интернетті тексеріп, қайталап көріңіз."
            }
        }
    }

    private func loadCurrentLessonVideo() async {
        saveLoadedPlaybackPosition()
        let requestID = UUID()
        lessonVideoRequestID = requestID
        let lessonID = currentLessonID
        let userID = auth.user?.id
        lessonPlayer?.pause()
        lessonPlayer = nil
        lessonVideoURL = nil
        lessonVideoLoadFailed = false
        lessonPlayback.reset()
        guard userID != nil else {
            if lessonVideoRequestID == requestID {
                lessonVideoRequestID = nil
                isLoadingLessonVideo = false
            }
            return
        }
        isLoadingLessonVideo = true
        defer {
            if lessonVideoRequestID == requestID {
                lessonVideoRequestID = nil
                isLoadingLessonVideo = false
            }
        }
        do {
            let url = try await auth.lessonVideoURL(for: lessonID)
            guard !Task.isCancelled, lessonVideoRequestID == requestID,
                  auth.user?.id == userID, currentLessonID == lessonID else { return }
            lessonVideoURL = url
            if let lessonVideoURL {
                let item = AVPlayerItem(url: lessonVideoURL)
                lessonPlayback.observe(item)
                let player = AVPlayer(playerItem: item)
                lessonPlayer = player
                loadedVideoLessonID = lessonID
                loadedPlaybackUserID = userID
                let resumeSeconds = resumeCheckpoints[lessonID]?.positionSeconds ?? 0
                if resumeSeconds.isFinite, resumeSeconds > 0 {
                    await player.seek(to: CMTime(seconds: resumeSeconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
                startCheckpointObserver(for: player, lessonID: lessonID, userID: userID)
            }
        } catch {
            guard !Task.isCancelled, lessonVideoRequestID == requestID,
                  auth.user?.id == userID, currentLessonID == lessonID else { return }
            lessonVideoURL = nil
            lessonVideoLoadFailed = true
        }
    }

    private func syncProgress(for userID: UUID) async {
        guard auth.user?.id == userID else { return }
        let key = "learning.completedLessonIDs.\(userID.uuidString)"

        do {
            let serverIDs = try await auth.fetchCompletedLessonIDs()
            guard auth.user?.id == userID else { return }
            // A lesson may be completed while the server request is suspended.
            // Read the latest device copy immediately before the merge/write.
            let localIDs = completedLessonIDs
            let mergedIDs = localIDs.union(serverIDs)
            if let data = try? JSONEncoder().encode(mergedIDs.sorted()), let text = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(text, forKey: key)
                progressRevision += 1
            }

            let ownedProductIDs = auth.verifiedCourseProductIDs
            let ownedLessonIDs = Set(auth.accessibleCourses
                .filter { ownedProductIDs.contains($0.productID) }
                .flatMap { $0.sections.flatMap(\.lessons).map(\.id) })
            var uploadFailed = false
            var uploadedIDs: Set<String> = []
            for lessonID in localIDs.subtracting(serverIDs) where ownedLessonIDs.contains(lessonID) {
                guard auth.user?.id == userID else { return }
                do {
                    try await auth.markLessonComplete(lessonID, for: userID)
                    uploadedIDs.insert(lessonID)
                } catch {
                    // One stale lesson must not prevent other authorized progress from syncing.
                    uploadFailed = true
                }
            }
            guard auth.user?.id == userID else { return }
            let pendingIDs = completedLessonIDs
                .subtracting(serverIDs.union(uploadedIDs))
                .intersection(ownedLessonIDs)
            if uploadFailed || !pendingIDs.isEmpty {
                if progressRetryAttempts == 0 {
                    auth.message = "Прогресс құрылғыда сақталды, бірақ кейбір белгілер жіберілмеді. Қайталап көреміз."
                }
                scheduleProgressRetry(for: userID)
            } else {
                progressRetryTask?.cancel()
                progressRetryTask = nil
                progressRetryAttempts = 0
            }
        } catch {
            if progressRetryAttempts == 0 {
                auth.message = "Прогресс әзірге тек осы құрылғыда сақталды. Қосылым қалпына келгенде қайта синхрондаймыз."
            }
            scheduleProgressRetry(for: userID)
        }
    }

    private func syncLessonResume(for userID: UUID) async {
        guard auth.user?.id == userID else { return }
        if let resumeUploadTask { await resumeUploadTask.value }
        guard auth.user?.id == userID else { return }
        let key = "learning.resumeState.\(userID.uuidString)"
        var local: [String: LocalResumeCheckpoint] = [:]
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: LocalResumeCheckpoint].self, from: data) {
            local = saved
        }

        do {
            let serverRecords = try await auth.fetchLessonResumeRecords()
            guard auth.user?.id == userID else { return }
            var server: [String: LocalResumeCheckpoint] = [:]
            for record in serverRecords {
                guard record.positionSeconds.isFinite, record.positionSeconds >= 0,
                      let updatedAt = parseResumeDate(record.updatedAt) else { continue }
                server[record.lessonID] = LocalResumeCheckpoint(positionSeconds: record.positionSeconds, updatedAt: updatedAt)
            }

            local = ResumeCheckpointPolicy.merge(local: local, server: server)
            var uploadFailed = false
            for (lessonID, checkpoint) in ResumeCheckpointPolicy.checkpointsToUpload(local: local, server: server)
                .sorted(by: { $0.key < $1.key }) {
                guard auth.user?.id == userID else { return }
                do {
                    try await auth.saveLessonResumePosition(
                        checkpoint.positionSeconds,
                        lessonID: lessonID,
                        for: userID,
                        updatedAt: checkpoint.updatedAt
                    )
                    server[lessonID] = checkpoint
                } catch {
                    uploadFailed = true
                    break
                }
            }

            guard auth.user?.id == userID else { return }

            // A playback callback may have saved a newer position while server requests
            // were suspended. Preserve it before writing the merged device copy.
            if let latestData = UserDefaults.standard.data(forKey: key),
               let latestLocal = try? JSONDecoder().decode([String: LocalResumeCheckpoint].self, from: latestData) {
                local = ResumeCheckpointPolicy.merge(local: latestLocal, server: local)
            }
            if let data = try? JSONEncoder().encode(local) {
                UserDefaults.standard.set(data, forKey: key)
            }
            resumeCheckpoints = local
            if uploadFailed || !ResumeCheckpointPolicy.checkpointsToUpload(local: local, server: server).isEmpty {
                scheduleResumeRetry(for: userID)
            } else {
                resumeRetryTask?.cancel()
                resumeRetryTask = nil
                resumeRetryAttempts = 0
            }
        } catch {
            // Keep any position saved while the network request was suspended.
            if let latestData = UserDefaults.standard.data(forKey: key),
               let latestLocal = try? JSONDecoder().decode([String: LocalResumeCheckpoint].self, from: latestData) {
                local = ResumeCheckpointPolicy.merge(local: latestLocal, server: local)
            }
            if auth.user?.id == userID {
                resumeCheckpoints = local
                scheduleResumeRetry(for: userID)
            }
        }
    }

    private func saveLoadedPlaybackPosition() {
        guard let lessonID = loadedVideoLessonID,
              let player = lessonPlayer else { return }
        let time = player.currentTime()
        guard time.isValid, !time.isIndefinite, time.seconds.isFinite, time.seconds > 0 else { return }
        let duration = player.currentItem?.duration.seconds
        let position = duration.map { $0.isFinite && $0 > 0 ? min(time.seconds, $0) : time.seconds } ?? time.seconds
        saveResumeCheckpoint(lessonID: lessonID, positionSeconds: position, userID: loadedPlaybackUserID)
    }

    private func startCheckpointObserver(for player: AVPlayer, lessonID: String, userID: UUID?) {
        playbackCheckpointObserver.observe(player) { seconds in
            saveResumeCheckpoint(lessonID: lessonID, positionSeconds: seconds, userID: userID)
        }
    }

    private func saveResumeCheckpoint(lessonID: String, positionSeconds: Double, userID: UUID?) {
        guard positionSeconds.isFinite, positionSeconds > 0 else { return }
        let checkpoint = LocalResumeCheckpoint(positionSeconds: positionSeconds, updatedAt: Date())
        let key = "learning.resumeState.\(userID?.uuidString ?? "preview")"
        var saved: [String: LocalResumeCheckpoint] = [:]
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: LocalResumeCheckpoint].self, from: data) {
            saved = decoded
        }
        saved[lessonID] = checkpoint
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: key)
        }
        if let userID, auth.user?.id == userID {
            resumeCheckpoints[lessonID] = checkpoint
            let previousUpload = resumeUploadTask
            resumeUploadTask = Task { @MainActor in
                if let previousUpload { await previousUpload.value }
                guard !Task.isCancelled, auth.user?.id == userID else { return }
                do {
                    try await auth.saveLessonResumePosition(
                        positionSeconds,
                        lessonID: lessonID,
                        for: userID,
                        updatedAt: checkpoint.updatedAt
                    )
                } catch {
                    if auth.user?.id == userID { scheduleResumeRetry(for: userID) }
                }
            }
        } else if userID == nil {
            resumeCheckpoints[lessonID] = checkpoint
        }
    }

    private func parseResumeDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private func scheduleProgressRetry(for userID: UUID) {
        guard progressRetryTask == nil else { return }
        let delay = min(5 * pow(2, Double(min(progressRetryAttempts, 6))), 300)
        progressRetryAttempts += 1
        progressRetryTask = Task {
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            progressRetryTask = nil
            guard auth.user?.id == userID, networkPath.isConnected else { return }
            await syncProgress(for: userID)
        }
    }

    private func scheduleResumeRetry(for userID: UUID) {
        guard resumeRetryTask == nil else { return }
        let delay = min(5 * pow(2, Double(min(resumeRetryAttempts, 6))), 300)
        resumeRetryAttempts += 1
        resumeRetryTask = Task {
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            resumeRetryTask = nil
            guard auth.user?.id == userID, networkPath.isConnected else { return }
            await syncLessonResume(for: userID)
        }
    }

    private func refreshCatalog() async {
        if let catalogRefreshTask {
            let refreshUserID = catalogRefreshUserID
            await catalogRefreshTask.value
            if auth.user?.id != refreshUserID {
                await refreshCatalog()
            }
            return
        }
        isRefreshingCatalog = true
        let refreshUserID = auth.user?.id
        let refreshTask = Task { @MainActor in
            do {
                try await auth.fetchPublishedCourses()
                let productIDs = Set(PurchaseManager.productIDs + auth.accessibleCourses.map(\.productID))
                await purchases.loadProducts(productIDs: Array(productIDs))
            } catch {
                // AuthManager retains a user-facing retry state for catalog errors.
            }
        }
        catalogRefreshTask = refreshTask
        catalogRefreshUserID = refreshUserID
        await refreshTask.value
        catalogRefreshTask = nil
        catalogRefreshUserID = nil
        isRefreshingCatalog = false
        if auth.user?.id != refreshUserID {
            await refreshCatalog()
        }
    }

    private var accountSubtitle: String {
        let phone = auth.user?.phone ?? phoneNumber
        return phone.isEmpty ? "Оқушы · ZHANAR Massage" : phone
    }

    private func openProduct(_ productID: String) {
        guard courseIsAvailable(productID) else {
            auth.message = "Бұл курс әзірге жарияланбаған. Кейінірек қайталап көріңіз."
            return
        }
        selectedProductID = productID
        if let firstSection = auth.accessibleCourse(for: productID)?.sections.first {
            selectedSection = firstSection.title
            selectedSectionID = firstSection.id
        } else {
            #if DEBUG
            let fallbackSection = productID == PurchaseManager.selfMassageCourseID ? selfMassageSections[0] : sections[0]
            selectedSection = fallbackSection.title
            selectedSectionID = fallbackSection.id
            #else
            selectedSection = ""
            selectedSectionID = ""
            #endif
        }
        selectedLessonNumber = 1
        screen = hasCourseAccess(productID) ? .course : .coursePreview
    }

    private func resumeLesson(_ destination: (course: AccessibleCourse, section: PublishedSection, lesson: PublishedLesson, lessonNumber: Int)) {
        selectedProductID = destination.course.productID
        selectedSection = destination.section.title
        selectedSectionID = destination.section.id
        selectedLessonNumber = destination.lessonNumber
        screen = .lesson
    }

    private func reconcileSelectedCourseAccess() {
        let hasAccess = hasCourseAccess(selectedProductID)
        if screen == .paywall, hasAccess {
            screen = .course
            return
        }

        guard !hasAccess else { return }
        if screen == .course {
            clearLessonPlayback()
            screen = courseIsAvailable(selectedProductID) ? .coursePreview : .root
        } else if screen == .lesson, currentPublishedLesson?.isPreview != true {
            clearLessonPlayback()
            screen = courseIsAvailable(selectedProductID) ? .coursePreview : .root
        }
    }

    private func clearLessonPlayback() {
        lessonPlayer?.pause()
        lessonPlayer = nil
        lessonVideoURL = nil
        loadedVideoLessonID = nil
        lessonVideoRequestID = nil
        isLoadingLessonVideo = false
        lessonVideoLoadFailed = false
        lessonPlayback.reset()
    }

    private func hasCourseAccess(_ productID: String) -> Bool {
        #if DEBUG
        return auth.verifiedCourseProductIDs.contains(productID)
            || purchases.hasLocalTestingAccess(to: productID, userID: purchaseAccountToken)
        #else
        return auth.verifiedCourseProductIDs.contains(productID)
        #endif
    }

    private var purchaseAccountToken: UUID? {
        if let userID = auth.user?.id { return userID }
        #if DEBUG
        return previewMode ? Self.debugPreviewAccountToken : nil
        #else
        return nil
        #endif
    }

    private func courseIsAvailable(_ productID: String) -> Bool {
        #if DEBUG
        return true
        #else
        return auth.accessibleCourseProductIDs.contains(productID)
        #endif
    }
}

#Preview {
    ContentView()
}
