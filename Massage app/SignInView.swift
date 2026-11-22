import SwiftUI

struct SignInView: View {
    @ObservedObject var auth: AuthManager
    @EnvironmentObject private var languageSettings: LanguageSettings
    let onPreview: () -> Void
    let onPrivacy: () -> Void

    @State private var phone = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isEmailMode = true
    @State private var isCreatingAccount = false
    @State private var code = ""
    @State private var displayName = ""
    @State private var codeWasSent = false
    @State private var feedback: String?
    @State private var feedbackIsError = false
    @State private var resendAvailableAt: Date?
    @State private var resendCountdown = 0

    private let brown = Color(red: 0.48, green: 0.20, blue: 0.06)
    private let fieldPromptColor = Color(red: 0.38, green: 0.35, blue: 0.33)
    private let resendCooldownSeconds: TimeInterval = 60
    private let otpLength = 6

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image("ZhanarMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104, height: 104)
                        .accessibilityLabel("ZHANAR Massage Academy")
                    Text("ZHANAR").font(.system(size: 13, weight: .bold)).tracking(2).foregroundStyle(brown)
                    Text("Massage Academy").font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                    Text("Қош келдіңіз").font(.system(size: 27, weight: .bold)).foregroundStyle(.black)
                    Text(isEmailMode ? "Курстарды оқу үшін аккаунтыңызға кіріңіз" : "Оқу курстарыңызға кіру үшін телефон нөміріңізді растаңыз")
                        .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                VStack(spacing: 14) {
                    Picker("Кіру тәсілі", selection: $isEmailMode) {
                        Text("Email және құпиясөз").tag(true)
                        Text("Телефон арқылы").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isEmailMode) { _, _ in feedback = nil; codeWasSent = false }

                    if isEmailMode {
                        if isCreatingAccount {
                            TextField("Аты-жөніңіз (міндетті емес)", text: $displayName, prompt: Text("Аты-жөніңіз (міндетті емес)").foregroundColor(fieldPromptColor))
                                .textContentType(.name)
                                .textInputAutocapitalization(.words)
                                .padding(16)
                                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        }
                        TextField("Электрондық пошта", text: $email, prompt: Text("Электрондық пошта").foregroundColor(fieldPromptColor))
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        SecureField("Құпиясөз", text: $password, prompt: Text("Құпиясөз").foregroundColor(fieldPromptColor))
                            .textContentType(isCreatingAccount ? .newPassword : .password)
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        Button {
                            Task { await submitEmailAccount() }
                        } label: {
                            actionLabel(isCreatingAccount ? "Аккаунт құру" : "Кіру", isEnabled: !auth.isWorking && email.contains("@") && password.count >= (isCreatingAccount ? 8 : 1))
                        }
                        .disabled(auth.isWorking || !email.contains("@") || password.count < (isCreatingAccount ? 8 : 1))

                        if !isCreatingAccount {
                            Button("Құпиясөзді ұмыттыңыз ба?") { Task { await resetPassword() } }
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(brown)
                                .disabled(auth.isWorking || !email.contains("@"))
                        }
                        Button(isCreatingAccount ? "Аккаунтыңыз бар ма? Кіру" : "Жаңа аккаунт құру") {
                            isCreatingAccount.toggle()
                            feedback = nil
                        }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(brown)
                    } else {
                        TextField("Аты-жөніңіз (міндетті емес)", text: $displayName, prompt: Text("Аты-жөніңіз (міндетті емес)").foregroundColor(fieldPromptColor))
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        TextField("+7 700 305 25 05", text: $phone, prompt: Text("+7 700 305 25 05").foregroundColor(fieldPromptColor))
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            .disabled(codeWasSent)
                    if codeWasSent {
                        TextField("SMS коды", text: $code, prompt: Text("SMS коды").foregroundColor(fieldPromptColor))
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .textInputAutocapitalization(.never)
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            .onChange(of: code) { _, value in
                                let digits = String(asciiDigits(from: value).prefix(otpLength))
                                if code != digits { code = digits }
                            }

                        Button("Нөмірді өзгерту") {
                            codeWasSent = false
                            code = ""
                            feedback = nil
                            feedbackIsError = false
                            resendAvailableAt = nil
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(brown)

                        if resendCountdown > 0 {
                            Text("Жаңа кодты \(resendCountdown) секундтан кейін сұрауға болады.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Button {
                                Task { await sendCode() }
                            } label: {
                                if auth.isWorking { ProgressView().tint(brown) }
                                Text(auth.isWorking ? "Өңделуде…" : "Жаңа код жіберу")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(brown)
                            .disabled(auth.isWorking || normalizedPhone == nil)
                        }

                        Button {
                            Task { await verifyCode() }
                        } label: {
                            actionLabel("Кодты растау", isEnabled: !auth.isWorking && code.count >= otpLength)
                        }
                        .disabled(auth.isWorking || code.count < otpLength)
                    } else {
                        Button {
                            Task { await sendCode() }
                        } label: {
                            actionLabel("SMS кодын жіберу", isEnabled: !auth.isWorking && normalizedPhone != nil)
                        }
                        .disabled(auth.isWorking || normalizedPhone == nil)
                    }
                    }

                    if let feedback {
                        Text(LocalizedStringKey(feedback))
                            .font(.system(size: 13))
                            .foregroundStyle(feedbackIsError ? Color.red : Color.secondary)
                            .multilineTextAlignment(.center)
                    }

                    AppLanguagePicker()

                    Button("Деректер мен құпиялылық", action: onPrivacy)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(brown)

                    #if DEBUG
                    Button("Алдын ала қарау режимі") { onPreview() }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(brown).padding(.top, 4)
                    #endif
                }
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(red: 0.975, green: 0.965, blue: 0.95).ignoresSafeArea())
        .task(id: resendAvailableAt) {
            guard let resendAvailableAt else {
                resendCountdown = 0
                return
            }
            while !Task.isCancelled {
                let secondsRemaining = Int(ceil(resendAvailableAt.timeIntervalSinceNow))
                guard secondsRemaining > 0 else { break }
                resendCountdown = secondsRemaining
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
            resendCountdown = 0
        }
    }

    private var normalizedPhone: String? {
        let digits = asciiDigits(from: phone)
        if digits.count == 10 { return "+7\(digits)" }
        if digits.count == 11, digits.first == "8" { return "+7\(digits.dropFirst())" }
        if digits.count == 11, digits.first == "7" { return "+\(digits)" }
        return nil
    }

    private func asciiDigits(from value: String) -> String {
        value.compactMap { character -> String? in
            guard let digit = character.wholeNumberValue, (0...9).contains(digit) else { return nil }
            return String(digit)
        }.joined()
    }

    private func actionLabel(_ title: String, isEnabled: Bool) -> some View {
        HStack(spacing: 10) {
            if auth.isWorking { ProgressView().tint(isEnabled ? .white : brown) }
            Text(LocalizedStringKey(auth.isWorking ? "Өңделуде…" : title))
        }
        .font(.system(size: 15, weight: .bold))
        .frame(maxWidth: .infinity).padding(.vertical, 17)
        .foregroundStyle(isEnabled ? Color.white : brown)
        .background(
            isEnabled ? brown : Color(red: 0.91, green: 0.88, blue: 0.84),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func sendCode() async {
        guard let normalizedPhone else { return }
        do {
            try await auth.sendOTP(to: normalizedPhone)
            codeWasSent = true
            resendAvailableAt = Date().addingTimeInterval(resendCooldownSeconds)
            feedbackIsError = false
            feedback = "SMS код жіберілді. Хабарламаны тексеріңіз."
        } catch {
            feedbackIsError = true
            feedback = "SMS кодын жіберу мүмкін болмады. Нөмірді тексеріп, сәлден соң қайталап көріңіз."
        }
    }

    private func verifyCode() async {
        guard let normalizedPhone else { return }
        do {
            try await auth.verifyOTP(phone: normalizedPhone, code: code, displayName: displayName)
            feedback = nil
            feedbackIsError = false
        } catch {
            feedbackIsError = true
            feedback = "Код қабылданбады немесе мерзімі аяқталды. Интернетті тексеріп, жаңа код сұраңыз."
        }
    }

    private func submitEmailAccount() async {
        do {
            if isCreatingAccount {
                let signedIn = try await auth.signUpWithEmail(email: email, password: password, displayName: displayName)
                feedbackIsError = false
                feedback = signedIn ? nil : "Аккаунт жасалды. Электрондық поштаңызды растап, қайта кіріңіз."
            } else {
                try await auth.signInWithEmail(email: email, password: password)
                feedback = nil
                feedbackIsError = false
            }
        } catch {
            feedback = AuthManager.userFacingMessage(for: error, context: isCreatingAccount ? .signUp : .signIn)
            feedbackIsError = true
        }
    }

    private func resetPassword() async {
        do {
            try await auth.sendPasswordReset(to: email)
            feedback = "Құпиясөзді қалпына келтіру сілтемесі поштаңызға жіберілді."
            feedbackIsError = false
        } catch {
            feedback = AuthManager.userFacingMessage(for: error, context: .passwordRecovery)
            feedbackIsError = true
        }
    }

}

struct PasswordRecoveryView: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Жаңа құпиясөз") {
                    SecureField("Құпиясөз (кемінде 8 таңба)", text: $password)
                        .textContentType(.newPassword)
                    SecureField("Құпиясөзді қайталаңыз", text: $confirmation)
                        .textContentType(.newPassword)
                }
                if let errorMessage { Text(LocalizedStringKey(errorMessage)).foregroundStyle(.red) }
                Button("Құпиясөзді сақтау") { Task { await savePassword() } }
                    .disabled(auth.isWorking || password.count < 8 || password != confirmation)
            }
            .navigationTitle("Құпиясөзді қалпына келтіру")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Жабу") { auth.dismissPasswordRecovery(); dismiss() } } }
        }
    }

    @MainActor private func savePassword() async {
        do {
            try await auth.updatePasswordAfterRecovery(password)
            dismiss()
        } catch { errorMessage = AuthManager.userFacingMessage(for: error, context: .passwordUpdate) }
    }
}
