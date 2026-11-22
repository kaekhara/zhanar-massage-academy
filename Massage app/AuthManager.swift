import Combine
import Foundation
import Supabase

private struct ProfileUpsert: Encodable {
    let id: UUID
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

private struct LessonProgressUpsert: Encodable {
    let userID: UUID
    let lessonID: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case lessonID = "lesson_id"
    }
}

private struct LessonResumeUpsert: Encodable {
    let userID: UUID
    let lessonID: String
    let positionSeconds: Double
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case lessonID = "lesson_id"
        case positionSeconds = "position_seconds"
        case updatedAt = "updated_at"
    }
}

struct LessonResumeRecord: Decodable {
    let lessonID: String
    let positionSeconds: Double
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case lessonID = "lesson_id"
        case positionSeconds = "position_seconds"
        case updatedAt = "updated_at"
    }
}

private struct StoreKitVerificationRequest: Encodable {
    let signedTransactionInfo: String
}

private struct AdminAssetUploadRequest: Encodable {
    let assetType: String
    let lessonID: String?
    let courseID: String?
    let fileExtension: String
    let contentType: String
    let fileSize: Int
}

private struct AdminVideoUploadTicket: Decodable {
    let path: String
    let token: String
}

private struct AdminLessonVideoUpdate: Encodable {
    let videoPath: String

    enum CodingKeys: String, CodingKey { case videoPath = "video_path" }
}

private struct AdminCourseCoverUpdate: Encodable {
    let coverPath: String
    enum CodingKeys: String, CodingKey { case coverPath = "cover_path" }
}

private struct CourseAdminRole: Decodable {
    let userID: UUID

    enum CodingKeys: String, CodingKey { case userID = "user_id" }
}

private struct AdminMutationID: Decodable {
    let id: String
}

struct AdminCourse: Identifiable, Decodable {
    let id: String
    let productID: String
    var title: String
    var subtitle: String
    var description: String
    var titleRu: String?
    var subtitleRu: String?
    var descriptionRu: String?
    var category: String?
    var categoryRu: String?
    var instructorName: String?
    var instructorTitle: String?
    var instructorTitleRu: String?
    var instructorBio: String?
    var instructorBioRu: String?
    var sortOrder: Int
    var isPublished: Bool
    var coverPath: String?
    var sections: [AdminSection]

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, description
        case titleRu = "title_ru"
        case subtitleRu = "subtitle_ru"
        case descriptionRu = "description_ru"
        case category
        case categoryRu = "category_ru"
        case instructorName = "instructor_name"
        case instructorTitle = "instructor_title"
        case instructorTitleRu = "instructor_title_ru"
        case instructorBio = "instructor_bio"
        case instructorBioRu = "instructor_bio_ru"
        case sections = "course_sections"
        case productID = "store_product_id"
        case sortOrder = "sort_order"
        case isPublished = "is_published"
        case coverPath = "cover_path"
    }
}

struct AdminSection: Identifiable, Decodable {
    let id: String
    var title: String
    var description: String
    var titleRu: String?
    var descriptionRu: String?
    var sortOrder: Int
    var lessons: [AdminLesson]

    enum CodingKeys: String, CodingKey { case id, title, description, lessons; case titleRu = "title_ru"; case descriptionRu = "description_ru"; case sortOrder = "sort_order" }
}

struct AdminLesson: Identifiable, Decodable {
    let id: String
    var title: String
    var description: String
    var titleRu: String?
    var descriptionRu: String?
    var durationSeconds: Int?
    var sortOrder: Int
    var isPreview: Bool
    var videoPath: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case titleRu = "title_ru"
        case descriptionRu = "description_ru"
        case durationSeconds = "duration_seconds"
        case sortOrder = "sort_order"
        case isPreview = "is_preview"
        case videoPath = "video_path"
    }
}

private struct AdminCourseUpdate: Encodable {
    let title: String
    let subtitle: String
    let description: String
    let titleRu: String?
    let subtitleRu: String?
    let descriptionRu: String?
    let category: String?
    let categoryRu: String?
    let instructorName: String?
    let instructorTitle: String?
    let instructorTitleRu: String?
    let instructorBio: String?
    let instructorBioRu: String?
    let sortOrder: Int
    let isPublished: Bool?

    enum CodingKeys: String, CodingKey {
        case title, subtitle, description
        case titleRu = "title_ru"
        case subtitleRu = "subtitle_ru"
        case descriptionRu = "description_ru"
        case category
        case categoryRu = "category_ru"
        case instructorName = "instructor_name"
        case instructorTitle = "instructor_title"
        case instructorTitleRu = "instructor_title_ru"
        case instructorBio = "instructor_bio"
        case instructorBioRu = "instructor_bio_ru"
        case sortOrder = "sort_order"
        case isPublished = "is_published"
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(title, forKey: .title)
        try values.encode(subtitle, forKey: .subtitle)
        try values.encode(description, forKey: .description)
        try values.encodeNullable(titleRu, forKey: .titleRu)
        try values.encodeNullable(subtitleRu, forKey: .subtitleRu)
        try values.encodeNullable(descriptionRu, forKey: .descriptionRu)
        try values.encodeNullable(category, forKey: .category)
        try values.encodeNullable(categoryRu, forKey: .categoryRu)
        try values.encodeNullable(instructorName, forKey: .instructorName)
        try values.encodeNullable(instructorTitle, forKey: .instructorTitle)
        try values.encodeNullable(instructorTitleRu, forKey: .instructorTitleRu)
        try values.encodeNullable(instructorBio, forKey: .instructorBio)
        try values.encodeNullable(instructorBioRu, forKey: .instructorBioRu)
        try values.encode(sortOrder, forKey: .sortOrder)
        try values.encodeIfPresent(isPublished, forKey: .isPublished)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNullable<Value: Encodable>(_ value: Value?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

private struct AdminCourseInsert: Encodable {
    let id: String
    let storeProductID: String
    let title: String
    let subtitle: String
    let description: String
    let titleRu: String?
    let subtitleRu: String?
    let descriptionRu: String?
    let category: String?
    let categoryRu: String?
    let instructorName: String?
    let instructorTitle: String?
    let instructorTitleRu: String?
    let instructorBio: String?
    let instructorBioRu: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, description
        case titleRu = "title_ru"
        case subtitleRu = "subtitle_ru"
        case descriptionRu = "description_ru"
        case category
        case categoryRu = "category_ru"
        case instructorName = "instructor_name"
        case instructorTitle = "instructor_title"
        case instructorTitleRu = "instructor_title_ru"
        case instructorBio = "instructor_bio"
        case instructorBioRu = "instructor_bio_ru"
        case storeProductID = "store_product_id"
        case sortOrder = "sort_order"
    }
}

private struct AdminSectionInsert: Encodable {
    let id: String
    let courseID: String
    let title: String
    let description: String
    let titleRu: String?
    let descriptionRu: String?
    let sortOrder: Int
    enum CodingKeys: String, CodingKey { case id, title, description; case titleRu = "title_ru"; case descriptionRu = "description_ru"; case courseID = "course_id"; case sortOrder = "sort_order" }
}

private struct AdminSectionUpdate: Encodable {
    let title: String
    let description: String
    let titleRu: String?
    let descriptionRu: String?
    let sortOrder: Int
    enum CodingKeys: String, CodingKey { case title, description; case titleRu = "title_ru"; case descriptionRu = "description_ru"; case sortOrder = "sort_order" }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(title, forKey: .title)
        try values.encode(description, forKey: .description)
        try values.encodeNullable(titleRu, forKey: .titleRu)
        try values.encodeNullable(descriptionRu, forKey: .descriptionRu)
        try values.encode(sortOrder, forKey: .sortOrder)
    }
}

private struct AdminLessonInsert: Encodable {
    let id: String
    let sectionID: String
    let title: String
    let titleRu: String?
    let sortOrder: Int
    enum CodingKeys: String, CodingKey { case id, title; case titleRu = "title_ru"; case sectionID = "section_id"; case sortOrder = "sort_order" }
}

private struct AdminLessonUpdate: Encodable {
    let title: String
    let description: String
    let titleRu: String?
    let descriptionRu: String?
    let durationSeconds: Int?
    let sortOrder: Int
    let isPreview: Bool
    enum CodingKeys: String, CodingKey {
        case title, description
        case titleRu = "title_ru"
        case descriptionRu = "description_ru"
        case durationSeconds = "duration_seconds"
        case sortOrder = "sort_order"
        case isPreview = "is_preview"
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(title, forKey: .title)
        try values.encode(description, forKey: .description)
        try values.encodeNullable(titleRu, forKey: .titleRu)
        try values.encodeNullable(descriptionRu, forKey: .descriptionRu)
        try values.encodeNullable(durationSeconds, forKey: .durationSeconds)
        try values.encode(sortOrder, forKey: .sortOrder)
        try values.encode(isPreview, forKey: .isPreview)
    }
}

struct PublishedLesson: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let titleRu: String?
    let descriptionRu: String?
    let sortOrder: Int
    let durationSeconds: Int?
    let isPreview: Bool
}

struct PublishedSection: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let titleRu: String?
    let descriptionRu: String?
    let sortOrder: Int
    let lessons: [PublishedLesson]
}

struct AccessibleCourse: Identifiable, Codable {
    let id: String
    let productID: String
    let title: String
    let subtitle: String
    let titleRu: String?
    let subtitleRu: String?
    let sortOrder: Int
    let isPublished: Bool
    let description: String
    let descriptionRu: String?
    let category: String?
    let categoryRu: String?
    let instructorName: String?
    let instructorTitle: String?
    let instructorTitleRu: String?
    let instructorBio: String?
    let instructorBioRu: String?
    let coverURL: URL?
    let sections: [PublishedSection]
}

private extension String {
    var nilIfBlank: String? {
        let clean = trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}

@MainActor
final class AuthManager: ObservableObject {
    private static let publishedCourseCacheKey = "catalog.publishedCourses.v1"
    private static let supabaseURL = URL(string: "https://ocbmqllnugshdqtylzpu.supabase.co")!
    private static let publishableKey = "sb_publishable_SMYwWJb4kn6bqFJS41Ka5A_Qn8wKX7k"
    @Published private(set) var user: User?
    @Published private(set) var displayName = ""
    @Published private(set) var accessibleCourses: [AccessibleCourse] = []
    @Published private(set) var isLoadingCourses = false
    @Published private(set) var courseLoadMessage: String?
    @Published private(set) var verifiedCourseProductIDs: Set<String> = []
    @Published private(set) var isCourseAdmin = false
    @Published private(set) var adminVideoUploadProgress: Double?
    var accessibleCourseProductIDs: Set<String> { Set(accessibleCourses.map(\.productID)) }
    @Published private(set) var isReady = false
    @Published private(set) var isWorking = false
    @Published var message: String?
    @Published private(set) var isPasswordRecovery = false

    private let client: SupabaseClient?
    private var authListener: Task<Void, Never>?

    init() {
        let client = Self.makeClient()
        self.client = client
        if let cachedData = UserDefaults.standard.data(forKey: Self.publishedCourseCacheKey),
           let cachedCourses = try? JSONDecoder().decode([AccessibleCourse].self, from: cachedData) {
            accessibleCourses = cachedCourses.filter(\.isPublished).sorted(by: Self.courseOrder)
        }
        guard let client else {
            isReady = true
            return
        }

        authListener = Task { @MainActor [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                guard let self else { return }
                if event == .passwordRecovery {
                    self.isPasswordRecovery = true
                }
                if self.user?.id != session?.user.id {
                    self.verifiedCourseProductIDs = []
                    self.isCourseAdmin = false
                    self.accessibleCourses = self.accessibleCourses.filter(\.isPublished)
                    self.displayName = ""
                }
                // The SDK emits an expired local session before refreshing it. Keep its identity
                // until refresh succeeds or the SDK emits signedOut; server requests still validate the token.
                self.user = session?.user
                self.isReady = true
                if let user = session?.user {
                    let name = try? await self.fetchDisplayName(userID: user.id)
                    guard self.user?.id == user.id else { continue }
                    self.displayName = name ?? self.displayName
                    try? await self.refreshCourseAdminStatus()
                } else {
                    self.displayName = ""
                    self.isCourseAdmin = false
                }
            }
        }
    }

    deinit {
        authListener?.cancel()
    }

    func sendOTP(to phone: String) async throws {
        guard let client else { throw AuthManagerError.notConfigured }
        isWorking = true
        defer { isWorking = false }
        try await client.auth.signInWithOTP(phone: phone)
    }

    func verifyOTP(phone: String, code: String, displayName: String) async throws {
        guard let client else { throw AuthManagerError.notConfigured }
        let cleanDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        isWorking = true
        defer { isWorking = false }

        let response = try await client.auth.verifyOTP(phone: phone, token: code, type: .sms)
        do {
            let storedDisplayName = try await fetchDisplayName(userID: response.user.id)
            if storedDisplayName.isEmpty {
                let profile = ProfileUpsert(id: response.user.id, displayName: cleanDisplayName)
                try await client.from("profiles").upsert(profile).execute()
                self.displayName = cleanDisplayName
            } else {
                self.displayName = storedDisplayName
            }
        } catch {
            // The OTP has already created a valid session. Sign it out locally so a
            // transient profile-read/write failure cannot leave the learner half-registered.
            try? await client.auth.signOut(scope: .local)
            user = nil
            self.displayName = ""
            throw error
        }
        user = response.user
        isReady = true
    }

    func signInWithEmail(email: String, password: String) async throws {
        guard let client else { throw AuthManagerError.notConfigured }
        isWorking = true
        defer { isWorking = false }
        let session = try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        do {
            self.displayName = try await fetchDisplayName(userID: session.user.id)
            user = session.user
            isReady = true
        } catch {
            // Keep auth state and profile state in sync if the profile request fails after sign-in.
            try? await client.auth.signOut(scope: .local)
            user = nil
            self.displayName = ""
            throw error
        }
    }

    @discardableResult
    func signUpWithEmail(email: String, password: String, displayName: String) async throws -> Bool {
        guard let client else { throw AuthManagerError.notConfigured }
        isWorking = true
        defer { isWorking = false }
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata: [String: AnyJSON]? = cleanName.isEmpty ? nil : ["display_name": .string(cleanName)]
        let response = try await client.auth.signUp(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            data: metadata
        )
        guard let session = response.session else { return false }
        do {
            try await client.from("profiles").upsert(ProfileUpsert(id: session.user.id, displayName: cleanName)).execute()
            user = session.user
            self.displayName = cleanName
            isReady = true
            return true
        } catch {
            try? await client.auth.signOut(scope: .local)
            user = nil
            self.displayName = ""
            throw error
        }
    }

    func sendPasswordReset(to email: String) async throws {
        guard let client else { throw AuthManagerError.notConfigured }
        isWorking = true
        defer { isWorking = false }
        try await client.auth.resetPasswordForEmail(email.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func handleAuthCallback(_ url: URL) async {
        guard url.scheme == "zhanarmassage", let client else { return }
        do {
            let session = try await client.auth.session(from: url)
            user = session.user
            do {
                let currentName = try await fetchDisplayName(userID: session.user.id)
                guard user?.id == session.user.id else { return }
                if currentName.isEmpty {
                    let confirmedName: String
                    if case let .string(value)? = session.user.userMetadata["display_name"] { confirmedName = value }
                    else { confirmedName = "" }
                    try await client.from("profiles").upsert(ProfileUpsert(id: session.user.id, displayName: confirmedName)).execute()
                    guard user?.id == session.user.id else { return }
                    displayName = confirmedName
                } else {
                    displayName = currentName
                }
                isReady = true
            } catch {
                guard user?.id == session.user.id else { return }
                try? await client.auth.signOut(scope: .local)
                clearAccountState()
                message = "Профильді жүктеу мүмкін болмады. Интернетті тексеріп, сілтемені қайта ашыңыз."
            }
        } catch {
            message = "Қалпына келтіру сілтемесі жарамсыз немесе мерзімі аяқталған. Жаңа сілтеме сұратыңыз."
        }
    }

    func updatePasswordAfterRecovery(_ password: String) async throws {
        guard let client, isPasswordRecovery else { throw AuthManagerError.notConfigured }
        isWorking = true
        defer { isWorking = false }
        _ = try await client.auth.update(user: UserAttributes(password: password))
        isPasswordRecovery = false
    }

    func dismissPasswordRecovery() { isPasswordRecovery = false }

    func updateDisplayName(_ name: String) async throws {
        guard let client, let user else { throw AuthManagerError.notConfigured }
        let cleanDisplayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDisplayName.isEmpty else { throw AuthManagerError.missingDisplayName }
        let profile = ProfileUpsert(id: user.id, displayName: cleanDisplayName)
        try await client.from("profiles").upsert(profile).execute()
        displayName = profile.displayName
    }

    func refreshCourseAdminStatus() async throws {
        guard let client, let user else {
            isCourseAdmin = false
            return
        }
        let response = try await client.from("course_admins")
            .select("user_id")
            .eq("user_id", value: user.id.uuidString)
            .limit(1)
            .execute()
        let roles = try JSONDecoder().decode([CourseAdminRole].self, from: response.data)
        guard self.user?.id == user.id else { return }
        isCourseAdmin = roles.contains { $0.userID == user.id }
    }

    func fetchAdminCourses() async throws -> [AdminCourse] {
        guard let client, isCourseAdmin else { throw AuthManagerError.adminAccessRequired }
        let response = try await client.from("courses")
            .select("id,store_product_id,title,subtitle,description,title_ru,subtitle_ru,description_ru,category,category_ru,instructor_name,instructor_title,instructor_title_ru,instructor_bio,instructor_bio_ru,cover_path,sort_order,is_published,course_sections(id,title,description,title_ru,description_ru,sort_order,lessons(id,title,description,title_ru,description_ru,duration_seconds,sort_order,is_preview,video_path))")
            .order("sort_order")
            .execute()
        return try JSONDecoder().decode([AdminCourse].self, from: response.data)
            .map { course in
                var course = course
                course.sections.sort { $0.sortOrder < $1.sortOrder }
                for sectionIndex in course.sections.indices {
                    course.sections[sectionIndex].lessons.sort { $0.sortOrder < $1.sortOrder }
                }
                return course
            }
    }

    private func requireAdminMutation(_ data: Data, expectedID: String) throws {
        let rows = try JSONDecoder().decode([AdminMutationID].self, from: data)
        guard rows.contains(where: { $0.id == expectedID }) else {
            throw AuthManagerError.adminMutationNotApplied
        }
    }

    func createAdminCourse(title: String, subtitle: String, description: String, titleRu: String, subtitleRu: String, descriptionRu: String, category: String, categoryRu: String, instructorName: String, instructorTitle: String, instructorTitleRu: String, instructorBio: String, instructorBioRu: String, productID: String, sortOrder: Int) async throws {
        guard let client, isCourseAdmin else { throw AuthManagerError.adminAccessRequired }
        let cleanProductID = productID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanProductID.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{2,99}$"#, options: .regularExpression) != nil else {
            throw AuthManagerError.invalidProductID
        }
        // The package importer identifies an existing course by its stable
        // ID. Matching it to the App Store product ID lets an admin create a
        // draft here and then add its full structure and media from a package.
        let courseID = cleanProductID
        let row = AdminCourseInsert(
            id: courseID,
            storeProductID: cleanProductID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            titleRu: titleRu.nilIfBlank, subtitleRu: subtitleRu.nilIfBlank, descriptionRu: descriptionRu.nilIfBlank,
            category: category.nilIfBlank, categoryRu: categoryRu.nilIfBlank,
            instructorName: instructorName.nilIfBlank,
            instructorTitle: instructorTitle.nilIfBlank,
            instructorTitleRu: instructorTitleRu.nilIfBlank,
            instructorBio: instructorBio.nilIfBlank,
            instructorBioRu: instructorBioRu.nilIfBlank,
            sortOrder: sortOrder
        )
        let response = try await client.from("courses").insert(row).select("id").execute()
        try requireAdminMutation(response.data, expectedID: courseID)
    }

    func saveAdminCourse(_ course: AdminCourse) async throws {
        guard let client, isCourseAdmin else { throw AuthManagerError.adminAccessRequired }
        let update = AdminCourseUpdate(title: course.title, subtitle: course.subtitle, description: course.description, titleRu: course.titleRu?.nilIfBlank, subtitleRu: course.subtitleRu?.nilIfBlank, descriptionRu: course.descriptionRu?.nilIfBlank, category: course.category?.nilIfBlank, categoryRu: course.categoryRu?.nilIfBlank, instructorName: course.instructorName?.nilIfBlank, instructorTitle: course.instructorTitle?.nilIfBlank, instructorTitleRu: course.instructorTitleRu?.nilIfBlank, instructorBio: course.instructorBio?.nilIfBlank, instructorBioRu: course.instructorBioRu?.nilIfBlank, sortOrder: course.sortOrder, isPublished: nil)
        let response = try await client.from("courses").update(update).eq("id", value: course.id).select("id").execute()
        try requireAdminMutation(response.data, expectedID: course.id)
    }

    func deleteAdminEmptyDraftCourse(_ course: AdminCourse) async throws {
        guard let client, isCourseAdmin else { throw AuthManagerError.adminAccessRequired }
        guard !course.isPublished, course.sections.isEmpty, course.coverPath == nil else {
            throw AuthManagerError.adminMutationNotApplied
        }
        let response = try await client.from("courses")
            .delete()
            .eq("id", value: course.id)
            .eq("is_published", value: false)
            .select("id")
            .execute()
        try requireAdminMutation(response.data, expectedID: course.id)
    }

    func setAdminCoursePublished(_ course: AdminCourse, published: Bool) async throws {
        guard let client, isCourseAdmin else { throw AuthManagerError.adminAccessRequired }
        let update = AdminCourseUpdate(title: course.title, subtitle: course.subtitle, description: course.description, titleRu: course.titleRu?.nilIfBlank, subtitleRu: course.subtitleRu?.nilIfBlank, descriptionRu: course.descriptionRu?.nilIfBlank, category: course.category?.nilIfBlank, categoryRu: course.categoryRu?.nilIfBlank, instructorName: course.instructorName?.nilIfBlank, instructorTitle: course.instructorTitle?.nilIfBlank, instructorTitleRu: course.instructorTitleRu?.nilIfBlank, instructorBio: course.instructorBio?.nilIfBlank, instructorBioRu: course.instructorBioRu?.nilIfBlank, sortOrder: course.sortOrder, isPublished: published)
        let response = try await client.from("courses").update(update).eq("id", value: course.id).select("id").execute()
        try requireAdminMutation(response.data, expectedID: course.id)
    }

    func addAdminSection(course: AdminCourse, title: String, titleRu: String) async throws {
        guard let client, isCourseAdmin else { throw AuthManagerError.adminAccessRequired }
        let id = "\(course.id).section.\(UUID().uuidString.lowercased())"
        let nextOrder = (course.sections.map(\.sortOrder).max() ?? 0) + 1
        let row = AdminSectionInsert(id: id, courseID: course.id, title: title, description: "", titleRu: titleRu.nilIfBlank, descriptionRu: nil, sortOrder: nextOrder)
        let response = try await client.from("course_sections").insert(row).select("id").execute()
        try requireAdminMutation(response.data, expectedID: id)
    }

    func saveAdminSection(_ section: AdminSection) async throws {
        guard let client, isCourseAdmin else { throw AuthManagerError.adminAccessRequired }
        let response = try await client.from("course_sections").update(AdminSectionUpdate(title: section.title, description: section.description, titleRu: section.titleRu?.nilIfBlank, descriptionRu: section.descriptionRu?.nilIfBlank, sortOrder: section.sortOrder)).eq("id", value: section.id).select("id").execute()
        try requireAdminMutation(response.data, expectedID: section.id)
    }

    func deleteAdminSection(_ section: AdminSection) async throws {
        guard let client, isCourseAdmin else { throw AuthManagerError.adminAccessRequired }
        let response = try await client.from("course_sections").delete().eq("id", value: section.id).select("id").execute()
        try requireAdminMutation(response.data, expectedID: section.id)
    }

    func addAdminLesson(section: AdminSection, title: String, titleRu: String) async throws {
        guard let client, isCourseAdmin else { throw AuthManagerError.adminAccessRequired }
        let id = "\(section.id).lesson.\(UUID().uuidString.lowercased())"
        let nextOrder = (section.lessons.map(\.sortOrder).max() ?? 0) + 1
        let row = AdminLessonInsert(id: id, sectionID: section.id, title: title, titleRu: titleRu.nilIfBlank, sortOrder: nextOrder)
        let response = try await client.from("lessons").insert(row).select("id").execute()
        try requireAdminMutation(response.data, expectedID: id)
    }

    func saveAdminLesson(_ lesson: AdminLesson) async throws {
        guard let client, isCourseAdmin else { throw AuthManagerError.adminAccessRequired }
        let update = AdminLessonUpdate(title: lesson.title, description: lesson.description, titleRu: lesson.titleRu?.nilIfBlank, descriptionRu: lesson.descriptionRu?.nilIfBlank, durationSeconds: lesson.durationSeconds, sortOrder: lesson.sortOrder, isPreview: lesson.isPreview)
        let response = try await client.from("lessons").update(update).eq("id", value: lesson.id).select("id").execute()
        try requireAdminMutation(response.data, expectedID: lesson.id)
    }

    func deleteAdminLesson(_ lesson: AdminLesson) async throws {
        guard let client, isCourseAdmin else { throw AuthManagerError.adminAccessRequired }
        let response = try await client.from("lessons").delete().eq("id", value: lesson.id).select("id").execute()
        try requireAdminMutation(response.data, expectedID: lesson.id)
    }

    func uploadAdminLessonVideo(lessonID: String, fileURL: URL) async throws -> String {
        guard let client, isCourseAdmin, user != nil else { throw AuthManagerError.adminAccessRequired }
        let fileExtension = fileURL.pathExtension.lowercased()
        let contentType: String
        switch fileExtension {
        case "mp4": contentType = "video/mp4"
        case "mov": contentType = "video/quicktime"
        case "m4v": contentType = "video/x-m4v"
        default: throw AuthManagerError.unsupportedVideo
        }

        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize > 0, fileSize <= 50_000_000 else {
            throw AuthManagerError.videoSizeLimit
        }

        let ticket = try await createAdminAssetUploadTicket(request: AdminAssetUploadRequest(
            assetType: "video",
            lessonID: lessonID,
            courseID: nil,
            fileExtension: fileExtension,
            contentType: contentType,
            fileSize: fileSize
        ))

        let session = try await client.auth.session
        adminVideoUploadProgress = 0
        defer { adminVideoUploadProgress = nil }
        try await uploadVideoResumably(
            fileURL: fileURL,
            size: fileSize,
            contentType: contentType,
            path: ticket.path,
            token: ticket.token,
            accessToken: session.accessToken
        ) { [weak self] progress in
            self?.adminVideoUploadProgress = progress
        }

        do {
            let response = try await client.from("lessons")
                .update(AdminLessonVideoUpdate(videoPath: ticket.path))
                .eq("id", value: lessonID)
                .select("id")
                .execute()
            try requireAdminMutation(response.data, expectedID: lessonID)
            return ticket.path
        } catch {
            throw AuthManagerError.videoCatalogSaveFailed
        }
    }

    func uploadAdminCourseCover(courseID: String, fileURL: URL) async throws -> String {
        guard let client, isCourseAdmin, user != nil else { throw AuthManagerError.adminAccessRequired }
        let fileExtension = fileURL.pathExtension.lowercased()
        let contentType: String
        switch fileExtension {
        case "jpg", "jpeg": contentType = "image/jpeg"
        case "png": contentType = "image/png"
        case "webp": contentType = "image/webp"
        default: throw AuthManagerError.unsupportedCover
        }

        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize > 0, fileSize <= 5_000_000 else {
            throw AuthManagerError.coverSizeLimit
        }
        let ticket = try await createAdminAssetUploadTicket(request: AdminAssetUploadRequest(
            assetType: "cover",
            lessonID: nil,
            courseID: courseID,
            fileExtension: fileExtension,
            contentType: contentType,
            fileSize: fileSize
        ))
        let imageData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        do {
            try await client.storage.from("course-covers").uploadToSignedURL(
                ticket.path,
                token: ticket.token,
                data: imageData,
                options: FileOptions(contentType: contentType)
            )
        } catch {
            throw AuthManagerError.coverUploadFailed
        }

        do {
            let response = try await client.from("courses")
                .update(AdminCourseCoverUpdate(coverPath: ticket.path))
                .eq("id", value: courseID)
                .select("id")
                .execute()
            try requireAdminMutation(response.data, expectedID: courseID)
            return ticket.path
        } catch {
            throw AuthManagerError.coverCatalogSaveFailed
        }
    }

    private func createAdminAssetUploadTicket(request: AdminAssetUploadRequest) async throws -> AdminVideoUploadTicket {
        guard let client else { throw AuthManagerError.notConfigured }
        let functionName = request.assetType == "cover" ? "create-admin-cover-upload" : "create-admin-video-upload"
        return try await client.functions.invoke(
            functionName,
            options: .init(body: request),
            decode: { data, _ in try JSONDecoder().decode(AdminVideoUploadTicket.self, from: data) }
        )
    }

    private func uploadVideoResumably(
        fileURL: URL,
        size: Int,
        contentType: String,
        path: String,
        token: String,
        accessToken: String,
        onProgress: (Double) -> Void
    ) async throws {
        guard let projectHost = Self.supabaseURL.host else {
            throw AuthManagerError.invalidServerResponse
        }
        let storageHost = projectHost.replacingOccurrences(of: ".supabase.co", with: ".storage.supabase.co")
        guard let storageURL = URL(string: "https://\(storageHost)/storage/v1/upload/resumable/sign") else {
            throw AuthManagerError.invalidServerResponse
        }

        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }
        let chunkSize = 6 * 1024 * 1024
        let metadata: [(String, String)] = [
            ("bucketName", "course-videos"),
            ("objectName", path),
            ("contentType", contentType),
            ("cacheControl", "3600")
        ]
        let encodedMetadata = metadata.map { key, value in
            "\(key) \(Data(value.utf8).base64EncodedString())"
        }.joined(separator: ",")

        var createRequest = URLRequest(url: storageURL)
        createRequest.httpMethod = "POST"
        createRequest.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        createRequest.setValue(String(size), forHTTPHeaderField: "Upload-Length")
        createRequest.setValue(encodedMetadata, forHTTPHeaderField: "Upload-Metadata")
        createRequest.setValue(token, forHTTPHeaderField: "x-signature")
        createRequest.setValue(Self.publishableKey, forHTTPHeaderField: "apikey")
        createRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (_, createResponse) = try await URLSession.shared.data(for: createRequest)
        guard let response = createResponse as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let location = response.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location, relativeTo: storageURL)?.absoluteURL else {
            throw AuthManagerError.videoUploadFailed
        }

        var offset = Int64(response.value(forHTTPHeaderField: "Upload-Offset") ?? "0") ?? 0
        while offset < Int64(size) {
            try fileHandle.seek(toOffset: UInt64(offset))
            guard var chunk = try fileHandle.read(upToCount: min(chunkSize, size - Int(offset))), !chunk.isEmpty else {
                throw AuthManagerError.videoUploadFailed
            }

            var patchRequest = URLRequest(url: uploadURL)
            patchRequest.httpMethod = "PATCH"
            patchRequest.httpBody = chunk
            patchRequest.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
            patchRequest.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
            patchRequest.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
            patchRequest.setValue(token, forHTTPHeaderField: "x-signature")
            patchRequest.setValue(Self.publishableKey, forHTTPHeaderField: "apikey")
            patchRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            var attempts = 0
            var chunkFinished = false
            while !chunkFinished {
                do {
                    let (_, patchResponse) = try await URLSession.shared.data(for: patchRequest)
                    guard let response = patchResponse as? HTTPURLResponse else {
                        throw AuthManagerError.videoUploadFailed
                    }
                    if (200..<300).contains(response.statusCode),
                       let nextOffset = response.value(forHTTPHeaderField: "Upload-Offset").flatMap(Int64.init),
                       nextOffset > offset, nextOffset <= Int64(size) {
                        offset = nextOffset
                        chunkFinished = true
                    } else if (400..<500).contains(response.statusCode) && response.statusCode != 409 {
                        throw AuthManagerError.videoUploadFailed
                    } else {
                        throw URLError(.cannotConnectToHost)
                    }
                } catch let error as AuthManagerError {
                    throw error
                } catch {
                    attempts += 1
                    guard attempts <= 3 else { throw AuthManagerError.videoUploadFailed }
                    try await Task.sleep(for: .seconds(attempts))

                    var headRequest = URLRequest(url: uploadURL)
                    headRequest.httpMethod = "HEAD"
                    headRequest.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
                    headRequest.setValue(token, forHTTPHeaderField: "x-signature")
                    headRequest.setValue(Self.publishableKey, forHTTPHeaderField: "apikey")
                    headRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    let (_, headResponse) = try await URLSession.shared.data(for: headRequest)
                    guard let response = headResponse as? HTTPURLResponse,
                          (200..<300).contains(response.statusCode),
                          let serverOffset = response.value(forHTTPHeaderField: "Upload-Offset").flatMap(Int64.init),
                          serverOffset >= 0, serverOffset <= Int64(size) else {
                        throw AuthManagerError.videoUploadFailed
                    }
                    let chunkEnd = offset + Int64(chunk.count)
                    offset = serverOffset
                    chunkFinished = serverOffset >= chunkEnd
                    if !chunkFinished {
                        try fileHandle.seek(toOffset: UInt64(offset))
                        guard let remainingChunk = try fileHandle.read(upToCount: min(chunkSize, size - Int(offset))), !remainingChunk.isEmpty else {
                            throw AuthManagerError.videoUploadFailed
                        }
                        chunk = remainingChunk
                        patchRequest.httpBody = chunk
                        patchRequest.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
                    }
                }
            }
            onProgress(Double(offset) / Double(size))
        }
    }

    func fetchCompletedLessonIDs() async throws -> Set<String> {
        guard let client, let user else { return [] }
        let response = try await client
            .from("lesson_progress")
            .select("lesson_id")
            .eq("user_id", value: user.id.uuidString)
            .execute()
        let rows = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]]
        return Set(rows?.compactMap { $0["lesson_id"] as? String } ?? [])
    }

    func fetchLessonResumeRecords() async throws -> [LessonResumeRecord] {
        guard let client, let user else { return [] }
        let response = try await client.from("lesson_resume_state")
            .select("lesson_id,position_seconds,updated_at")
            .eq("user_id", value: user.id.uuidString)
            .order("updated_at", ascending: false)
            .execute()
        return try JSONDecoder().decode([LessonResumeRecord].self, from: response.data)
    }

    func saveLessonResumePosition(
        _ positionSeconds: Double,
        lessonID: String,
        for userID: UUID,
        updatedAt: Date
    ) async throws {
        guard let client, user?.id == userID else { throw AuthManagerError.notConfigured }
        guard positionSeconds.isFinite, positionSeconds >= 0 else { throw AuthManagerError.invalidResumePosition }
        let value = LessonResumeUpsert(
            userID: userID,
            lessonID: lessonID,
            positionSeconds: positionSeconds,
            updatedAt: updatedAt
        )
        try await client.from("lesson_resume_state")
            .upsert(value, onConflict: "user_id,lesson_id")
            .execute()
    }

    func refreshVerifiedPurchases() async throws {
        guard let user else { throw AuthManagerError.notConfigured }
        let productIDs = try await fetchActivePurchasedProductIDs(userID: user.id)
        guard self.user?.id == user.id else { return }
        verifiedCourseProductIDs = productIDs
    }

    private func fetchActivePurchasedProductIDs(userID: UUID) async throws -> Set<String> {
        guard let client else { throw AuthManagerError.notConfigured }
        let response = try await client
            .from("verified_purchases")
            .select("product_id,revoked_at")
            .eq("user_id", value: userID.uuidString)
            .execute()
        let rows = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]]
        return Set((rows ?? []).compactMap { row in
            guard row["revoked_at"] is NSNull else { return nil }
            return row["product_id"] as? String
        })
    }

    @discardableResult
    func verifyStoreKitTransaction(_ signedTransactionInfo: String, appAccountToken: UUID?) async throws -> Bool {
        guard let client else { throw AuthManagerError.notConfigured }
        guard let user else { throw CancellationError() }
        guard CourseAccessPolicy.canSubmitTransactionForVerification(
            transactionAccountToken: appAccountToken,
            currentAccountID: user.id
        ) else { throw CancellationError() }
        let requestedUserID = user.id
        let request = StoreKitVerificationRequest(signedTransactionInfo: signedTransactionInfo)
        let responseData: Data = try await client.functions.invoke(
            "verify-storekit-purchase",
            options: .init(body: request),
            decode: { data, _ in data }
        )
        guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let productID = response["productID"] as? String,
              let revoked = response["revoked"] as? Bool else {
            throw AuthManagerError.invalidServerResponse
        }
        guard self.user?.id == requestedUserID else { throw CancellationError() }
        if revoked {
            try await refreshVerifiedPurchases()
            guard self.user?.id == requestedUserID else { throw CancellationError() }
            return false
        } else {
            verifiedCourseProductIDs.insert(productID)
            return true
        }
    }

    func fetchPublishedCourses() async throws {
        guard let client else { throw AuthManagerError.notConfigured }
        let requestedUserID = user?.id
        isLoadingCourses = true
        courseLoadMessage = nil
        defer { isLoadingCourses = false }
        do {
            if let requestedUserID {
                let productIDs = try await fetchActivePurchasedProductIDs(userID: requestedUserID)
                guard self.user?.id == requestedUserID else { return }
                verifiedCourseProductIDs = productIDs
            }

            let courseSelection = "id,store_product_id,title,subtitle,description,title_ru,subtitle_ru,description_ru,category,category_ru,instructor_name,instructor_title,instructor_title_ru,instructor_bio,instructor_bio_ru,cover_path,sort_order,is_published,course_sections(id,title,description,title_ru,description_ru,sort_order,lessons(id,title,description,title_ru,description_ru,sort_order,duration_seconds,is_preview))"
            let response = try await client
                .from("courses")
                .select(courseSelection)
                .eq("is_published", value: true)
                .order("sort_order")
                .execute()
            guard self.user?.id == requestedUserID else { return }
            var rows = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] ?? []
            if !verifiedCourseProductIDs.isEmpty {
                let ownedResponse = try await client
                    .from("courses")
                    .select(courseSelection)
                    .in("store_product_id", values: Array(verifiedCourseProductIDs))
                    .execute()
                guard self.user?.id == requestedUserID else { return }
                let ownedRows = try JSONSerialization.jsonObject(with: ownedResponse.data) as? [[String: Any]] ?? []
                rows.append(contentsOf: ownedRows)
            }

            let uniqueRows = Dictionary(
                rows.compactMap { row -> (String, [String: Any])? in
                    guard let id = row["id"] as? String else { return nil }
                    return (id, row)
                },
                uniquingKeysWith: { _, latest in latest }
            )
            accessibleCourses = uniqueRows.values.compactMap { row -> AccessibleCourse? in
                guard let id = row["id"] as? String,
                      let productID = row["store_product_id"] as? String,
                      let title = row["title"] as? String else { return nil }
                let coverPath = row["cover_path"] as? String
                let coverURL = coverPath.flatMap { try? client.storage.from("course-covers").getPublicURL(path: $0) }
                let sectionRows = row["course_sections"] as? [[String: Any]] ?? []
                let sections: [PublishedSection] = sectionRows.map { sectionRow in
                    let lessons: [PublishedLesson] = (sectionRow["lessons"] as? [[String: Any]] ?? []).compactMap { lessonRow -> PublishedLesson? in
                        guard let lessonID = lessonRow["id"] as? String,
                              let lessonTitle = lessonRow["title"] as? String else { return nil }
                        return PublishedLesson(
                            id: lessonID,
                            title: lessonTitle,
                            description: lessonRow["description"] as? String ?? "",
                            titleRu: lessonRow["title_ru"] as? String,
                            descriptionRu: lessonRow["description_ru"] as? String,
                            sortOrder: (lessonRow["sort_order"] as? NSNumber)?.intValue ?? 0,
                            durationSeconds: (lessonRow["duration_seconds"] as? NSNumber)?.intValue,
                            isPreview: lessonRow["is_preview"] as? Bool ?? false
                        )
                    }.sorted { $0.sortOrder < $1.sortOrder }
                    let sectionID = sectionRow["id"] as? String ?? ""
                    let sectionTitle = sectionRow["title"] as? String ?? ""
                    let sectionDescription = sectionRow["description"] as? String ?? ""
                    let sectionTitleRu = sectionRow["title_ru"] as? String
                    let sectionDescriptionRu = sectionRow["description_ru"] as? String
                    let sectionOrder = (sectionRow["sort_order"] as? NSNumber)?.intValue ?? 0
                    return PublishedSection(id: sectionID, title: sectionTitle, description: sectionDescription, titleRu: sectionTitleRu, descriptionRu: sectionDescriptionRu, sortOrder: sectionOrder, lessons: lessons)
                }.sorted { $0.sortOrder < $1.sortOrder }
                return AccessibleCourse(
                    id: id,
                    productID: productID,
                    title: title,
                    subtitle: row["subtitle"] as? String ?? "",
                    titleRu: row["title_ru"] as? String,
                    subtitleRu: row["subtitle_ru"] as? String,
                    sortOrder: (row["sort_order"] as? NSNumber)?.intValue ?? 0,
                    isPublished: (row["is_published"] as? Bool) ?? true,
                    description: row["description"] as? String ?? "",
                    descriptionRu: row["description_ru"] as? String,
                    category: row["category"] as? String,
                    categoryRu: row["category_ru"] as? String,
                    instructorName: row["instructor_name"] as? String,
                    instructorTitle: row["instructor_title"] as? String,
                    instructorTitleRu: row["instructor_title_ru"] as? String,
                    instructorBio: row["instructor_bio"] as? String,
                    instructorBioRu: row["instructor_bio_ru"] as? String,
                    coverURL: coverURL,
                    sections: sections
                )
            }.sorted(by: Self.courseOrder)
            let publicCatalog = accessibleCourses.filter(\.isPublished)
            if let cache = try? JSONEncoder().encode(publicCatalog) {
                UserDefaults.standard.set(cache, forKey: Self.publishedCourseCacheKey)
            }
        } catch {
            courseLoadMessage = "Каталог жүктелмеді. Интернетті тексеріп, қайта көріңіз."
            throw error
        }
    }

    func accessibleCourse(for productID: String) -> AccessibleCourse? {
        accessibleCourses.first { $0.productID == productID }
    }

    func publicCourseCoverURL(for path: String) -> URL? {
        guard let client else { return nil }
        return try? client.storage.from("course-covers").getPublicURL(path: path)
    }

    private static func courseOrder(_ lhs: AccessibleCourse, _ rhs: AccessibleCourse) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.productID < rhs.productID
    }

    func markLessonComplete(_ lessonID: String, for userID: UUID) async throws {
        guard let client, user?.id == userID else { throw AuthManagerError.notConfigured }
        let value = LessonProgressUpsert(userID: userID, lessonID: lessonID)
        try await client.from("lesson_progress").upsert(value, onConflict: "user_id,lesson_id").execute()
    }

    func lessonVideoURL(for lessonID: String) async throws -> URL? {
        guard let client, user != nil else { throw AuthManagerError.notConfigured }
        let response = try await client
            .from("lessons")
            .select("video_path")
            .eq("id", value: lessonID)
            .limit(1)
            .execute()
        let rows = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]]
        guard let path = rows?.first?["video_path"] as? String, !path.isEmpty else { return nil }
        return try await client.storage
            .from("course-videos")
            .createSignedURL(path: path, expiresIn: 3600)
    }

    func signOut() async throws {
        guard let client else { throw AuthManagerError.notConfigured }
        try await client.auth.signOut()
        clearAccountState()
    }

    func deleteAccount() async throws {
        guard let client, user != nil else { throw AuthManagerError.notConfigured }
        isWorking = true
        defer { isWorking = false }
        do {
            let responseData: Data = try await client.functions.invoke(
                "delete-account",
                decode: { data, _ in data }
            )
            guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  response["deleted"] as? Bool == true else {
                throw AuthManagerError.invalidServerResponse
            }
        } catch {
            // The server may already have revoked all refresh sessions before a
            // later deletion step failed. Clear this device's stale local session.
            try? await client.auth.signOut(scope: .local)
            clearAccountState()
            throw error
        }
        try? await client.auth.signOut(scope: .local)
        clearAccountState()
    }

    private func clearAccountState() {
        user = nil
        displayName = ""
        isCourseAdmin = false
        verifiedCourseProductIDs = []
        accessibleCourses = accessibleCourses.filter(\.isPublished)
        isPasswordRecovery = false
    }

    private static func makeClient() -> SupabaseClient? {
        // Supabase publishable keys are designed to ship in client applications.
        // Keeping these values here avoids synchronous plist/file reads at startup.
        return SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: publishableKey,
            options: .init(auth: .init(
                redirectToURL: URL(string: "zhanarmassage://auth-callback"),
                emitLocalSessionAsInitialSession: true
            ))
        )
    }

    private func fetchDisplayName(userID: UUID) async throws -> String {
        guard let client else { return "" }
        let response = try await client
            .from("profiles")
            .select("display_name")
            .eq("id", value: userID.uuidString)
            .execute()
        let rows = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]]
        return rows?.first?["display_name"] as? String ?? ""
    }
}

enum AuthManagerError: LocalizedError {
    case notConfigured
    case invalidServerResponse
    case missingDisplayName
    case adminAccessRequired
    case adminMutationNotApplied
    case invalidProductID
    case invalidResumePosition
    case unsupportedVideo
    case videoSizeLimit
    case videoUploadFailed
    case videoCatalogSaveFailed
    case unsupportedCover
    case coverSizeLimit
    case coverUploadFailed
    case coverCatalogSaveFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Аккаунт қызметі әлі бапталмаған. Кейінірек қайталап көріңіз."
        case .invalidServerResponse:
            "Сатып алуды тексеру мүмкін болмады. Қайталап көріңіз."
        case .missingDisplayName:
            "Атыңызды енгізіңіз."
        case .adminAccessRequired:
            "Бұл бөлім тек мақұлданған әкімші аккаунтына қолжетімді."
        case .adminMutationNotApplied:
            "Өзгеріс серверде сақталмады. Әкімші құқықтарын тексеріп, қайталап көріңіз."
        case .invalidProductID:
            "App Store өнімі әрпі не санынан басталып, әріп, сан, нүкте, сызықша немесе астын сызудан тұруы керек."
        case .invalidResumePosition:
            "Сабақтағы сақтау орны дұрыс емес."
        case .unsupportedVideo:
            "MP4, MOV немесе M4V форматындағы видео таңдаңыз."
        case .videoSizeLimit:
            "Видео бос болмауы және 50 МБ-тан аспауы керек."
        case .videoUploadFailed:
            "Видео жүктелмеді. Интернетті тексеріп, қайталап көріңіз."
        case .videoCatalogSaveFailed:
            "Видео жүктелді, бірақ сабақпен байланыстыру мүмкін болмады. Сабақты жаңартып, видеоны қайта жүктеңіз."
        case .unsupportedCover:
            "Мұқаба үшін JPG, PNG немесе WebP суретін таңдаңыз."
        case .coverSizeLimit:
            "Мұқаба бос болмауы және 5 МБ-тан аспауы керек."
        case .coverUploadFailed:
            "Мұқаба жүктелмеді. Интернетті тексеріп, қайталап көріңіз."
        case .coverCatalogSaveFailed:
            "Мұқаба жүктелді, бірақ курсқа байланыстыру мүмкін болмады. Тағы бір рет жүктеп көріңіз."
        }
    }
}

extension AuthManager {
    static func userFacingMessage(for error: Error, context: UserFacingErrorContext) -> String {
        let language = AppLanguageCode.current
        if let authManagerError = error as? AuthManagerError,
           let key = authManagerError.errorDescription {
            return language.localized(key)
        }

        if let authError = error as? AuthError {
            let key = AuthErrorMessagePolicy.messageKey(for: authError.errorCode.rawValue, context: context)
            return language.localized(key)
        }

        if let urlError = error as? URLError,
           [.notConnectedToInternet, .timedOut, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed]
            .contains(urlError.code) {
            return language.localized(AuthErrorMessagePolicy.networkErrorKey)
        }
        return language.localized(AuthErrorMessagePolicy.messageKey(for: nil, context: context))
    }
}
