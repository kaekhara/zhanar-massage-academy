import SwiftUI
import UniformTypeIdentifiers

private func adminLocalizedTitle(_ kazakh: String, russian: String?, language: AppLanguageCode) -> String {
    guard language == .russian,
          let russian,
          !russian.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return kazakh }
    return russian
}

struct AdminDashboardView: View {
    @ObservedObject var auth: AuthManager
    @EnvironmentObject private var languageSettings: LanguageSettings
    @Environment(\.dismiss) private var dismiss
    @State private var courses: [AdminCourse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedCourse: AdminCourse?
    @State private var showingNewCourse = false

    private let brown = Color(red: 0.48, green: 0.20, blue: 0.06)

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && courses.isEmpty {
                    ProgressView("Курстар жүктелуде…").tint(brown)
                } else if courses.isEmpty {
                    ContentUnavailableView("Курс жоқ", systemImage: "books.vertical", description: Text("Серверде курстар пайда болған соң, оларды осы жерден басқаруға болады."))
                } else {
                    List {
                        Section {
                            ForEach(courses) { course in
                                Button { selectedCourse = course } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "book.closed.fill")
                                            .font(.title3).foregroundStyle(brown)
                                            .frame(width: 42, height: 42)
                                            .background(Color(red: 0.98, green: 0.93, blue: 0.88), in: RoundedRectangle(cornerRadius: 12))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(verbatim: adminLocalizedTitle(course.title, russian: course.titleRu, language: languageSettings.language))
                                                .font(.headline).foregroundStyle(.primary)
                                            Text("\(course.sections.count) бөлім · \(course.sections.reduce(0) { $0 + $1.lessons.count }) сабақ")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(verbatim: languageSettings.language.localized(course.isPublished ? "Жарияланған" : "Жоба"))
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(course.isPublished ? .green : .orange)
                                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        } header: {
                            Text("Оқу каталогы")
                        } footer: {
                            Text("Сабақ видеоларын редакторда жеке жүктеуге болады; толық курсты пакетпен импорттауға болады.")
                        }
                    }
                    .refreshable { await loadCourses() }
                }
            }
            .background(Color(red: 0.98, green: 0.97, blue: 0.95))
            .navigationTitle("Әкімші")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Дайын") { dismiss() } }
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingNewCourse = true } label: { Label("Курс құру", systemImage: "plus") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await loadCourses() } } label: {
                        if isLoading { ProgressView().tint(brown) } else { Image(systemName: "arrow.clockwise") }
                    }.disabled(isLoading)
                }
            }
            .task { await loadCourses() }
            .sheet(item: $selectedCourse, onDismiss: { Task { await loadCourses() } }) { course in
                AdminCourseEditorView(auth: auth, course: course)
            }
            .sheet(isPresented: $showingNewCourse, onDismiss: { Task { await loadCourses() } }) {
                AdminNewCourseView(auth: auth, sortOrder: (courses.map(\.sortOrder).max() ?? 0) + 1)
            }
            .alert("Әкімші деректерін жүктеу мүмкін болмады", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Жабу", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Қайталап көріңіз.") }
        }
    }

    @MainActor private func loadCourses() async {
        guard auth.isCourseAdmin else { errorMessage = AuthManager.userFacingMessage(for: AuthManagerError.adminAccessRequired, context: .adminAction); return }
        isLoading = true
        defer { isLoading = false }
        do { courses = try await auth.fetchAdminCourses() }
        catch { errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction) }
    }
}

private struct AdminNewCourseView: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    let sortOrder: Int
    @State private var title = ""
    @State private var subtitle = ""
    @State private var description = ""
    @State private var titleRu = ""
    @State private var subtitleRu = ""
    @State private var descriptionRu = ""
    @State private var category = ""
    @State private var categoryRu = ""
    @State private var instructorName = ""
    @State private var instructorTitle = ""
    @State private var instructorTitleRu = ""
    @State private var instructorBio = ""
    @State private var instructorBioRu = ""
    @State private var productID = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Жаңа курс") {
                    TextField("Курс атауы", text: $title)
                    TextField("Қысқаша сипаттама", text: $subtitle, axis: .vertical).lineLimit(2...4)
                    TextField("Толық сипаттама", text: $description, axis: .vertical).lineLimit(3...8)
                    TextField("Атауы · Русский", text: $titleRu)
                    TextField("Қысқаша сипаттама · Русский", text: $subtitleRu, axis: .vertical).lineLimit(2...4)
                    TextField("Толық сипаттама · Русский", text: $descriptionRu, axis: .vertical).lineLimit(3...8)
                    TextField("Санат · Қазақша", text: $category)
                    TextField("Категория · Русский", text: $categoryRu)
                }
                Section("Оқытушы (міндетті емес)") {
                    TextField("Оқытушының аты-жөні", text: $instructorName)
                    TextField("Лауазымы немесе мамандығы · Қазақша", text: $instructorTitle)
                    TextField("Должность или специализация · Русский", text: $instructorTitleRu)
                    TextField("Оқытушы туралы · Қазақша", text: $instructorBio, axis: .vertical).lineLimit(3...7)
                    TextField("Об преподавателе · Русский", text: $instructorBioRu, axis: .vertical).lineLimit(3...7)
                }
                Section("App Store") {
                    TextField("App Store өнімінің ID-і", text: $productID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("Курс жоба ретінде жасалады, ал оның тұрақты ID-і осы өнім ID-імен бірдей болады. Бөлімдер мен сабақтарды осы жерде, видеоларды сабақ редакторында қосыңыз. Сатуды бастау үшін App Store Connect-те дәл осы өнім ID-сін құрыңыз.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Курс құру")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Болдырмау") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Жоба жасау") { Task { await createCourse() } }
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || productID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Курсты құру мүмкін болмады", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("Жабу", role: .cancel) { errorMessage = nil } } message: { Text(LocalizedStringKey(errorMessage ?? "Қайталап көріңіз.")) }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor private func createCourse() async {
        guard !isSaving else { return }
        isSaving = true; defer { isSaving = false }
        do {
            try await auth.createAdminCourse(title: title, subtitle: subtitle, description: description, titleRu: titleRu, subtitleRu: subtitleRu, descriptionRu: descriptionRu, category: category, categoryRu: categoryRu, instructorName: instructorName, instructorTitle: instructorTitle, instructorTitleRu: instructorTitleRu, instructorBio: instructorBio, instructorBioRu: instructorBioRu, productID: productID, sortOrder: sortOrder)
            dismiss()
        } catch { errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction) }
    }
}

private struct AdminCourseEditorView: View {
    @ObservedObject var auth: AuthManager
    @EnvironmentObject private var languageSettings: LanguageSettings
    @Environment(\.dismiss) private var dismiss
    @State private var course: AdminCourse
    @State private var newSectionTitle = ""
    @State private var newSectionTitleRu = ""
    @State private var showNewSection = false
    @State private var showPublishConfirmation = false
    @State private var showDeleteEmptyDraftConfirmation = false
    @State private var showingCoverPicker = false
    @State private var isUploadingCover = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var sectionToDelete: AdminSection?

    init(auth: AuthManager, course: AdminCourse) {
        self.auth = auth
        _course = State(initialValue: course)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Курс") {
                    TextField("Атауы", text: $course.title)
                    TextField("Қысқаша сипаттама", text: $course.subtitle, axis: .vertical).lineLimit(2...4)
                    TextField("Толық сипаттама", text: $course.description, axis: .vertical).lineLimit(3...8)
                    TextField("Атауы · Русский", text: Binding(get: { course.titleRu ?? "" }, set: { course.titleRu = $0.isEmpty ? nil : $0 }))
                    TextField("Қысқаша сипаттама · Русский", text: Binding(get: { course.subtitleRu ?? "" }, set: { course.subtitleRu = $0.isEmpty ? nil : $0 }), axis: .vertical).lineLimit(2...4)
                    TextField("Толық сипаттама · Русский", text: Binding(get: { course.descriptionRu ?? "" }, set: { course.descriptionRu = $0.isEmpty ? nil : $0 }), axis: .vertical).lineLimit(3...8)
                    TextField("Санат · Қазақша", text: Binding(get: { course.category ?? "" }, set: { course.category = $0.isEmpty ? nil : $0 }))
                    TextField("Категория · Русский", text: Binding(get: { course.categoryRu ?? "" }, set: { course.categoryRu = $0.isEmpty ? nil : $0 }))
                    LabeledContent("App Store өнімі · курс ID-і", value: course.productID)
                    Stepper("Каталогтағы орны: \(course.sortOrder)", value: $course.sortOrder, in: 1...999)
                    if let coverPath = course.coverPath,
                       let coverURL = auth.publicCourseCoverURL(for: coverPath) {
                        AsyncImage(url: coverURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else if phase.error != nil {
                                RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.12))
                                    .overlay {
                                        Label("Мұқаба жүктелмеді", systemImage: "photo")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                            } else {
                                RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.12))
                                    .overlay(ProgressView())
                            }
                        }
                        .frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Button {
                        showingCoverPicker = true
                    } label: {
                        if isUploadingCover {
                            Label("Мұқаба жүктелуде…", systemImage: "photo")
                        } else {
                            Label(languageSettings.language.localized(course.coverPath == nil ? "Курс мұқабасын жүктеу" : "Мұқабаны ауыстыру"), systemImage: "photo")
                        }
                    }
                    .disabled(isSaving || isUploadingCover)
                    Text("JPG, PNG немесе WebP · 5 МБ-қа дейін. Мұқаба каталогта жалпыға ашық көрсетіледі.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Курс мәліметтерін сақтау", systemImage: "checkmark.circle.fill") { Task { await saveCourse() } }
                        .disabled(isSaving || isUploadingCover || course.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Оқытушы (міндетті емес)") {
                    TextField("Оқытушының аты-жөні", text: Binding(get: { course.instructorName ?? "" }, set: { course.instructorName = $0.isEmpty ? nil : $0 }))
                    TextField("Лауазымы немесе мамандығы · Қазақша", text: Binding(get: { course.instructorTitle ?? "" }, set: { course.instructorTitle = $0.isEmpty ? nil : $0 }))
                    TextField("Должность или специализация · Русский", text: Binding(get: { course.instructorTitleRu ?? "" }, set: { course.instructorTitleRu = $0.isEmpty ? nil : $0 }))
                    TextField("Оқытушы туралы · Қазақша", text: Binding(get: { course.instructorBio ?? "" }, set: { course.instructorBio = $0.isEmpty ? nil : $0 }), axis: .vertical).lineLimit(3...7)
                    TextField("Об преподавателе · Русский", text: Binding(get: { course.instructorBioRu ?? "" }, set: { course.instructorBioRu = $0.isEmpty ? nil : $0 }), axis: .vertical).lineLimit(3...7)
                    Button("Оқытушы деректерін сақтау", systemImage: "checkmark.circle.fill") { Task { await saveCourse() } }
                        .disabled(isSaving || isUploadingCover)
                }

                Section {
                    ForEach(course.sections) { section in
                        NavigationLink {
                            AdminSectionEditorView(auth: auth, section: section)
                                .onDisappear { Task { await refreshCourseStructure() } }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: adminLocalizedTitle(section.title, russian: section.titleRu, language: languageSettings.language))
                                    .foregroundStyle(.primary)
                                Text("\(section.lessons.count) сабақ")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Жою", role: .destructive) { sectionToDelete = section }
                        }
                    }
                    Button("Бөлім қосу", systemImage: "plus.circle.fill") { showNewSection = true }
                } header: { Text("Құрылымы") } footer: { Text("Бөлім мен сабақ атауларын кез келген уақытта өзгертуге болады. Видео мен жариялау тексерістен өтеді.") }

                Section("Жариялау") {
                    LabeledContent("Күйі", value: languageSettings.language.localized(course.isPublished ? "Жарияланған" : "Жоба"))
                    Button(languageSettings.language.localized(course.isPublished ? "Жобаларға қайтару" : "Курсты жариялау"), systemImage: course.isPublished ? "eye.slash" : "paperplane.fill") {
                        showPublishConfirmation = true
                    }
                    .foregroundStyle(course.isPublished ? .orange : .green)
                    .disabled(isSaving)
                    if !course.isPublished && course.sections.isEmpty && course.coverPath == nil {
                        Button("Бос жобаны жою", role: .destructive) {
                            showDeleteEmptyDraftConfirmation = true
                        }
                        .disabled(isSaving || isUploadingCover)
                    }
                }
            }
            .navigationTitle("Курс редакторы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Жабу") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if isSaving { ProgressView() }
                }
            }
            .sheet(isPresented: $showNewSection) {
                NavigationStack {
                    Form {
                    TextField("Бөлім атауы · Қазақша", text: $newSectionTitle)
                    TextField("Бөлім атауы · Русский", text: $newSectionTitleRu)
                }
                        .navigationTitle("Жаңа бөлім")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Болдырмау") { showNewSection = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Қосу") { Task { await addSection() } }
                                    .disabled(isSaving || newSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                }.presentationDetents([.medium])
            }
            .fileImporter(
                isPresented: $showingCoverPicker,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await uploadCover(from: url) }
                case .failure(let error):
                    if (error as NSError).code == NSUserCancelledError { return }
                    errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction)
                }
            }
            .confirmationDialog("Курстың жария күйін өзгерту керек пе?", isPresented: $showPublishConfirmation, titleVisibility: .visible) {
                Button(languageSettings.language.localized(course.isPublished ? "Жобаға қайтару" : "Жариялау"), role: course.isPublished ? .destructive : nil) {
                    Task { await changePublication() }
                }
                Button("Болдырмау", role: .cancel) {}
            } message: {
                Text(verbatim: languageSettings.language.localized(course.isPublished ? "Ол жаңа оқушылардың каталогынан алынады. Сатып алғандарда қолжетімді болып қалады." : "Сервер қазақша және орысша мәтіндерді, App Store өнімінің ID-ін, бөлімдер мен жүктелген видеоларды тексереді. Өнімнің App Store-да қолжетімділігін бөлек растаңыз."))
            }
            .confirmationDialog("Бос жоба жойылсын ба?", isPresented: $showDeleteEmptyDraftConfirmation, titleVisibility: .visible) {
                Button("Жобаны біржола жою", role: .destructive) { Task { await deleteEmptyDraftCourse() } }
                Button("Болдырмау", role: .cancel) {}
            } message: {
                Text("Бұл әрекетті қайтару мүмкін емес. Тек бөлімдері мен мұқабасы жоқ, жарияланбаған курс жойылады.")
            }
            .confirmationDialog("Бөлімді және оның сабақтарын жою керек пе?", isPresented: Binding(
                get: { sectionToDelete != nil }, set: { if !$0 { sectionToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Бөлім мен сабақтарды жою", role: .destructive) { Task { await deleteSection() } }
                Button("Болдырмау", role: .cancel) { sectionToDelete = nil }
            } message: { Text("Бұл бөлімдегі оқу барысы да жойылады. Қайтару мүмкін емес.") }
            .alert("Өзгерісті сақтау мүмкін болмады", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Жабу", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Қайталап көріңіз.") }
        }
    }

    @MainActor private func saveCourse() async {
        guard !isSaving, !isUploadingCover else { return }
        isSaving = true; defer { isSaving = false }
        do { try await auth.saveAdminCourse(course) }
        catch { errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction) }
    }

    @MainActor private func uploadCover(from url: URL) async {
        guard !isSaving, !isUploadingCover else { return }
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Таңдалған мұқаба файлын оқу мүмкін болмады. Қайта таңдаңыз."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        isUploadingCover = true
        defer { isUploadingCover = false }
        do {
            course.coverPath = try await auth.uploadAdminCourseCover(courseID: course.id, fileURL: url)
        } catch {
            errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction)
        }
    }

    @MainActor private func addSection() async {
        guard !isSaving, !isUploadingCover else { return }
        let title = newSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        isSaving = true; defer { isSaving = false }
        do {
            try await auth.addAdminSection(course: course, title: title, titleRu: newSectionTitleRu)
            newSectionTitle = ""; newSectionTitleRu = ""; showNewSection = false
            do {
                course.sections = try await auth.fetchAdminCourses().first(where: { $0.id == course.id })?.sections ?? course.sections
            } catch {
                errorMessage = AppLanguageCode.current.localized("Жазба сақталды, бірақ тізім жаңартылмады. Редакторды жауып, қайта ашыңыз.")
            }
        } catch { errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction) }
    }

    @MainActor private func refreshCourseStructure() async {
        do {
            guard let updated = try await auth.fetchAdminCourses().first(where: { $0.id == course.id }) else {
                throw AuthManagerError.adminMutationNotApplied
            }
            course.sections = updated.sections
        } catch {
            errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction)
        }
    }

    @MainActor private func changePublication() async {
        guard !isSaving, !isUploadingCover else { return }
        isSaving = true; defer { isSaving = false }
        do {
            try await auth.setAdminCoursePublished(course, published: !course.isPublished)
            course.isPublished.toggle()
        } catch {
            errorMessage = course.isPublished
                ? AuthManager.userFacingMessage(for: error, context: .adminAction)
                : AppLanguageCode.current.localized("Курсты жариялау мүмкін болмады. Қазақша және орысша мәтіндерді, видеоларды, App Store өнімінің ID-ін және интернетті тексеріңіз.")
        }
    }

    @MainActor private func deleteEmptyDraftCourse() async {
        guard !isSaving, !isUploadingCover else { return }
        isSaving = true; defer { isSaving = false }
        do {
            try await auth.deleteAdminEmptyDraftCourse(course)
            dismiss()
        } catch {
            errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction)
        }
    }

    @MainActor private func deleteSection() async {
        guard !isSaving, !isUploadingCover else { return }
        guard let section = sectionToDelete else { return }
        isSaving = true; defer { isSaving = false }
        do {
            try await auth.deleteAdminSection(section)
            course.sections.removeAll { $0.id == section.id }
            sectionToDelete = nil
        } catch { errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction) }
    }
}

private struct AdminSectionEditorView: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var section: AdminSection
    @State private var newLessonTitle = ""
    @State private var newLessonTitleRu = ""
    @State private var showNewLesson = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var lessonToDelete: AdminLesson?

    init(auth: AuthManager, section: AdminSection) {
        self.auth = auth
        _section = State(initialValue: section)
    }

    var body: some View {
        Form {
            Section("Бөлім") {
                TextField("Атауы · Қазақша", text: $section.title)
                TextField("Атауы · Русский", text: Binding(get: { section.titleRu ?? "" }, set: { section.titleRu = $0.isEmpty ? nil : $0 }))
                TextField("Сипаттама · Қазақша", text: $section.description, axis: .vertical).lineLimit(2...5)
                TextField("Сипаттама · Русский", text: Binding(get: { section.descriptionRu ?? "" }, set: { section.descriptionRu = $0.isEmpty ? nil : $0 }), axis: .vertical).lineLimit(2...5)
                LabeledContent("Пакетке арналған бөлім ID-і", value: section.id)
                    .font(.caption).textSelection(.enabled)
                Stepper("Реті: \(section.sortOrder)", value: $section.sortOrder, in: 1...999)
                Button("Бөлімді сақтау", systemImage: "checkmark.circle.fill") { Task { await saveSection() } }
            }
            Section("Сабақтар") {
                ForEach(section.lessons) { lesson in
                    NavigationLink {
                        AdminLessonEditorView(auth: auth, lesson: lesson)
                            .onDisappear { Task { await refreshSectionLessons() } }
                    } label: {
                        AdminLessonRow(lesson: lesson)
                    }.swipeActions { Button("Жою", role: .destructive) { lessonToDelete = lesson } }
                }
                Button("Сабақ қосу", systemImage: "plus.circle.fill") { showNewLesson = true }
                Text("Әр сабақтың видеосын сабақ редакторынан жеке жүктеуге болады. Файлдар жабық қоймада сақталады.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Бөлім редакторы")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if isSaving { ProgressView() } }
        .sheet(isPresented: $showNewLesson) {
            NavigationStack {
                Form {
                    TextField("Сабақ атауы · Қазақша", text: $newLessonTitle)
                    TextField("Сабақ атауы · Русский", text: $newLessonTitleRu)
                }
                    .navigationTitle("Жаңа сабақ")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Болдырмау") { showNewLesson = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Қосу") { Task { await addLesson() } }
                                .disabled(isSaving || newLessonTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
            }.presentationDetents([.medium])
        }
        .confirmationDialog("Сабақты және оның оқу барысын жою керек пе?", isPresented: Binding(
            get: { lessonToDelete != nil }, set: { if !$0 { lessonToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Сабақты жою", role: .destructive) { Task { await deleteLesson() } }
            Button("Болдырмау", role: .cancel) { lessonToDelete = nil }
        }
        .alert("Сақтау мүмкін болмады", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("Жабу", role: .cancel) { errorMessage = nil } } message: { Text(LocalizedStringKey(errorMessage ?? "Қайталап көріңіз.")) }
    }

    @MainActor private func saveSection() async {
        guard !isSaving else { return }
        isSaving = true; defer { isSaving = false }
        do { try await auth.saveAdminSection(section) }
        catch { errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction) }
    }

    @MainActor private func addLesson() async {
        guard !isSaving else { return }
        let title = newLessonTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        isSaving = true; defer { isSaving = false }
        do {
            try await auth.addAdminLesson(section: section, title: title, titleRu: newLessonTitleRu)
            newLessonTitle = ""; newLessonTitleRu = ""; showNewLesson = false
            do {
                section.lessons = try await auth.fetchAdminCourses().flatMap(\.sections).first(where: { $0.id == section.id })?.lessons ?? section.lessons
            } catch {
                errorMessage = AppLanguageCode.current.localized("Жазба сақталды, бірақ тізім жаңартылмады. Редакторды жауып, қайта ашыңыз.")
            }
        } catch { errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction) }
    }

    @MainActor private func refreshSectionLessons() async {
        do {
            guard let updated = try await auth.fetchAdminCourses()
                .flatMap(\.sections).first(where: { $0.id == section.id }) else {
                throw AuthManagerError.adminMutationNotApplied
            }
            section.lessons = updated.lessons
        } catch {
            errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction)
        }
    }

    @MainActor private func deleteLesson() async {
        guard !isSaving else { return }
        guard let lesson = lessonToDelete else { return }
        isSaving = true; defer { isSaving = false }
        do {
            try await auth.deleteAdminLesson(lesson)
            section.lessons.removeAll { $0.id == lesson.id }
            lessonToDelete = nil
        } catch { errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction) }
    }
}

private struct AdminLessonRow: View {
    @EnvironmentObject private var languageSettings: LanguageSettings
    let lesson: AdminLesson

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: adminLocalizedTitle(lesson.title, russian: lesson.titleRu, language: languageSettings.language))
                .foregroundStyle(.primary)
            HStack(spacing: 5) {
                Image(systemName: lesson.videoPath == nil ? "video.slash" : "video.fill")
                Text(verbatim: languageSettings.language.localized(lesson.videoPath == nil ? "Видео жоқ" : "Видео тіркелген"))
            }
            .font(.caption)
            .foregroundStyle(lesson.videoPath == nil ? Color.orange : Color.secondary)
        }
    }
}

private struct AdminLessonEditorView: View {
    @ObservedObject var auth: AuthManager
    @EnvironmentObject private var languageSettings: LanguageSettings
    @State private var lesson: AdminLesson
    @State private var isSaving = false
    @State private var isUploadingVideo = false
    @State private var showingVideoPicker = false
    @State private var errorMessage: String?

    init(auth: AuthManager, lesson: AdminLesson) {
        self.auth = auth
        _lesson = State(initialValue: lesson)
    }

    var body: some View {
        Form {
            Section("Материал сабақ") {
                TextField("Атауы", text: $lesson.title)
                TextField("Сипаттама · Қазақша", text: $lesson.description, axis: .vertical).lineLimit(3...8)
                TextField("Атауы · Русский", text: Binding(get: { lesson.titleRu ?? "" }, set: { lesson.titleRu = $0.isEmpty ? nil : $0 }))
                TextField("Сипаттама · Русский", text: Binding(get: { lesson.descriptionRu ?? "" }, set: { lesson.descriptionRu = $0.isEmpty ? nil : $0 }), axis: .vertical).lineLimit(3...8)
                LabeledContent("Пакетке арналған сабақ ID-і", value: lesson.id)
                    .font(.caption).textSelection(.enabled)
                Stepper("Реті: \(lesson.sortOrder)", value: $lesson.sortOrder, in: 1...999)
                    .disabled(isUploadingVideo)
                Stepper("Ұзақтығы: \(lesson.durationSeconds ?? 0) сек", value: Binding(
                    get: { lesson.durationSeconds ?? 0 }, set: { lesson.durationSeconds = $0 == 0 ? nil : $0 }
                ), in: 0...86400, step: 30)
                .disabled(isUploadingVideo)
                Toggle("Тегін таныстыру сабағы", isOn: $lesson.isPreview)
                    .disabled(isUploadingVideo)
                LabeledContent("Видео күйі", value: languageSettings.language.localized(lesson.videoPath == nil ? "Импорт күтілуде" : "Жабық қоймаға жүктелген"))
                Button {
                    showingVideoPicker = true
                } label: {
                    if isUploadingVideo {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Видео жүктелуде…", systemImage: "arrow.up.video")
                            if let progress = auth.adminVideoUploadProgress {
                                ProgressView(value: progress)
                                Text("\(Int(progress * 100))%")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Label(languageSettings.language.localized(lesson.videoPath == nil ? "Видео таңдау және жүктеу" : "Видеоны ауыстыру"), systemImage: "arrow.up.video")
                    }
                }
                .disabled(isSaving || isUploadingVideo)
                Text("MP4, MOV немесе M4V · 50 МБ-қа дейін. Жүктелген видео жабық қоймада сақталады.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Сабақты сақтау", systemImage: "checkmark.circle.fill") { Task { await saveLesson() } }
                    .disabled(isSaving || isUploadingVideo || lesson.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Сабақ редакторы")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if isSaving { ProgressView() } }
        .fileImporter(
            isPresented: $showingVideoPicker,
            allowedContentTypes: [.mpeg4Movie, .quickTimeMovie, .movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await uploadVideo(from: url) }
            case .failure(let error):
                if (error as NSError).code == NSUserCancelledError { return }
                errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction)
            }
        }
        .alert("Сақтау мүмкін болмады", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("Жабу", role: .cancel) { errorMessage = nil } } message: { Text(LocalizedStringKey(errorMessage ?? "Қайталап көріңіз.")) }
    }

    @MainActor private func saveLesson() async {
        guard !isSaving, !isUploadingVideo else { return }
        isSaving = true; defer { isSaving = false }
        do { try await auth.saveAdminLesson(lesson) }
        catch { errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction) }
    }

    @MainActor private func uploadVideo(from url: URL) async {
        guard !isSaving, !isUploadingVideo else { return }
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Таңдалған видео файлын оқу мүмкін болмады. Қайта таңдаңыз."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        isUploadingVideo = true
        defer { isUploadingVideo = false }
        do {
            lesson.videoPath = try await auth.uploadAdminLessonVideo(lessonID: lesson.id, fileURL: url)
        } catch {
            errorMessage = AuthManager.userFacingMessage(for: error, context: .adminAction)
        }
    }
}

