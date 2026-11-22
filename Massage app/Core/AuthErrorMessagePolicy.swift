enum UserFacingErrorContext: CaseIterable {
    case signIn
    case signUp
    case passwordRecovery
    case passwordUpdate
    case profileSave
    case signOut
    case adminAction

    var fallbackKey: String {
        switch self {
        case .signIn: "Кіру мүмкін болмады. Деректерді тексеріп, қайталап көріңіз."
        case .signUp: "Аккаунт құру мүмкін болмады. Деректерді тексеріп, қайталап көріңіз."
        case .passwordRecovery: "Қалпына келтіру сілтемесін жіберу мүмкін болмады. Email-ді тексеріп, қайталап көріңіз."
        case .passwordUpdate: "Жаңа құпиясөзді сақтау мүмкін болмады. Қайталап көріңіз."
        case .profileSave: "Профильді сақтау мүмкін болмады. Қайталап көріңіз."
        case .signOut: "Аккаунттан шығу мүмкін болмады. Қайталап көріңіз."
        case .adminAction: "Өзгерістерді сақтау мүмкін болмады. Интернетті тексеріп, қайталап көріңіз."
        }
    }
}

enum AuthErrorMessagePolicy {
    static let networkErrorKey = "Интернет байланысын тексеріп, қайталап көріңіз."

    private static let messageKeys: [String: String] = [
        "invalid_credentials": "Email немесе құпиясөз қате. Қайталап көріңіз.",
        "email_not_confirmed": "Кіру алдында Email мекенжайын растаңыз.",
        "email_exists": "Бұл деректермен аккаунт бұрыннан бар. Кіруге өтіңіз.",
        "user_already_exists": "Бұл деректермен аккаунт бұрыннан бар. Кіруге өтіңіз.",
        "phone_exists": "Бұл деректермен аккаунт бұрыннан бар. Кіруге өтіңіз.",
        "weak_password": "Құпиясөз тым әлсіз. Ұзынырақ құпиясөз таңдаңыз.",
        "otp_expired": "Растау кодының мерзімі аяқталды. Жаңа код сұратыңыз.",
        "flow_state_expired": "Растау кодының мерзімі аяқталды. Жаңа код сұратыңыз.",
        "over_request_rate_limit": "Сұраулар тым жиі жіберілді. Сәл күтіп, қайталап көріңіз.",
        "over_email_send_rate_limit": "Сұраулар тым жиі жіберілді. Сәл күтіп, қайталап көріңіз.",
        "over_sms_send_rate_limit": "Сұраулар тым жиі жіберілді. Сәл күтіп, қайталап көріңіз.",
        "email_provider_disabled": "Бұл кіру тәсілі әзірге бапталмаған. Мектеп қолдау қызметіне хабарласыңыз.",
        "phone_provider_disabled": "Бұл кіру тәсілі әзірге бапталмаған. Мектеп қолдау қызметіне хабарласыңыз.",
        "otp_disabled": "Бұл кіру тәсілі әзірге бапталмаған. Мектеп қолдау қызметіне хабарласыңыз.",
        "signup_disabled": "Бұл кіру тәсілі әзірге бапталмаған. Мектеп қолдау қызметіне хабарласыңыз.",
        "not_admin": "Бұл әрекетке әкімші рұқсаты қажет.",
        "session_missing": "Сеанс аяқталды. Аккаунтқа қайта кіріңіз.",
        "session_expired": "Сеанс аяқталды. Аккаунтқа қайта кіріңіз.",
        "refresh_token_not_found": "Сеанс аяқталды. Аккаунтқа қайта кіріңіз."
    ]

    static func messageKey(for code: String?, context: UserFacingErrorContext) -> String {
        guard let code, let messageKey = messageKeys[code] else { return context.fallbackKey }
        return messageKey
    }
}
