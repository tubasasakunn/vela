import AppKit
import SwiftUI
import VelaCore

enum OnboardingPage {
    case welcome
    case installationComplete
    case aiChoice(options: [AISetupOption])
    case handoff(target: AISetupTarget, openedAutomatically: Bool)
}

struct OnboardingView: View {
    let page: OnboardingPage
    let chooseAI: (AISetupTarget) -> Void
    let continueToAIChoice: () -> Void
    let backToEntry: () -> Void
    let backToAIChoice: () -> Void
    let showGuide: () -> Void
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            SetupBackdrop()
            VStack(spacing: 0) {
                setupHeader
                Group {
                    switch page {
                    case .welcome, .installationComplete:
                        introduction
                    case let .aiChoice(options):
                        AIChoicePage(options: options, back: backToEntry, continueWith: chooseAI)
                    case let .handoff(target, openedAutomatically):
                        handoff(target: target, openedAutomatically: openedAutomatically)
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 28)
        }
        .frame(minWidth: 700, minHeight: 500)
        .onExitCommand(perform: dismiss)
    }

    private var setupHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text("Vela")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            SetupProgress(currentStep: currentStep)
        }
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private var currentStep: Int {
        switch page {
        case .welcome, .installationComplete: return 0
        case .aiChoice: return 1
        case .handoff: return 2
        }
    }

    private var introduction: some View {
        VStack(spacing: 0) {
            HStack(spacing: 42) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(introductionTitle)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .tracking(-1.1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("よく使うアプリや定型文、ウィンドウ操作を、\nいつものAIと相談しながら自分仕様に整えます。")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                        .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 14) {
                        SetupCapability(icon: "command", title: "ショートカット", detail: "よく使う操作を、手の届く場所へ")
                        SetupCapability(icon: "doc.on.clipboard", title: "テキスト", detail: "履歴と定型文をすぐ呼び出す")
                        SetupCapability(icon: "rectangle.3.group", title: "ウィンドウ", detail: "探す、選ぶ、切り替えるを一瞬で")
                    }
                    .padding(.top, 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SetupJourneyCard()
                    .frame(width: 248)
            }
            .frame(maxHeight: .infinity)

            actionBar {
                Button("導入手順", action: showGuide)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("あとで", action: dismiss)
                    .modifier(SecondaryGlassButtonModifier())
                Button("設定を始める", systemImage: "arrow.right", action: continueToAIChoice)
                    .labelStyle(.titleAndIcon)
                    .keyboardShortcut(.defaultAction)
                    .modifier(PrimaryGlassButtonModifier())
            }
        }
    }

    private var introductionTitle: String {
        if case .installationComplete = page { return "準備ができました。" }
        return "Macを、\nあなたの手になじませる。"
    }

    private func handoff(target: AISetupTarget, openedAutomatically: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: target.symbolName)
                        .font(.system(size: 44, weight: .medium))
                        .frame(width: 112, height: 112)
                        .foregroundStyle(target.accentColor)
                        .glassSurface(cornerRadius: 36, tint: target.accentColor.opacity(0.16))
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(SetupPalette.mint, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
                        .shadow(color: SetupPalette.mint.opacity(0.32), radius: 12)
                }
                Text(openedAutomatically ? "\(target.title)へ引き継ぎました" : "依頼文をコピーしました")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                Text(handoffDescription(target: target, openedAutomatically: openedAutomatically))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            actionBar {
                Button("戻る", systemImage: "chevron.left", action: backToAIChoice)
                    .modifier(SecondaryGlassButtonModifier())
                Spacer()
                Button("閉じる", action: dismiss)
                    .keyboardShortcut(.defaultAction)
                    .modifier(PrimaryGlassButtonModifier())
            }
        }
    }

    private func handoffDescription(target: AISetupTarget, openedAutomatically: Bool) -> String {
        if openedAutomatically {
            return "依頼文も用意してあります。会話に入っていない場合は、\n⌘Vで貼り付けて送信してください。"
        }
        return "\(target.title)を開き、⌘Vで貼り付けて送信してください。\nVelaの保存先から一緒に決められます。"
    }
}

private struct AIChoicePage: View {
    let options: [AISetupOption]
    let back: () -> Void
    let continueWith: (AISetupTarget) -> Void
    @State private var selectedTarget: AISetupTarget

    init(options: [AISetupOption], back: @escaping () -> Void, continueWith: @escaping (AISetupTarget) -> Void) {
        self.options = options
        self.back = back
        self.continueWith = continueWith
        _selectedTarget = State(initialValue: options.first(where: \.isRecommended)?.target ?? .chatGPT)
    }

    private var selectedOption: AISetupOption? {
        options.first(where: { $0.target == selectedTarget })
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("一緒に設定するAIを選ぶ")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                Text("選んだAIにセットアップの依頼文を渡します。Velaの設定は、その会話の中で一緒に作れます。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                HStack(spacing: 24) {
                    VStack(spacing: 10) {
                        ForEach(options, id: \.target) { option in
                            AIOptionRow(
                                option: option,
                                isSelected: selectedTarget == option.target,
                                select: { selectedTarget = option.target }
                            )
                        }
                    }
                    .frame(width: 290)

                    AISelectionDetail(option: selectedOption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            actionBar {
                Button("戻る", systemImage: "chevron.left", action: back)
                    .modifier(SecondaryGlassButtonModifier())
                Spacer()
                Button("このAIで続ける", systemImage: "arrow.right") {
                    continueWith(selectedTarget)
                }
                .keyboardShortcut(.defaultAction)
                .modifier(PrimaryGlassButtonModifier())
            }
        }
        .animation(.snappy(duration: 0.28), value: selectedTarget)
    }
}

private struct AIOptionRow: View {
    let option: AISetupOption
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 14) {
                Image(systemName: option.target.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(option.target.accentColor)
                    .frame(width: 38, height: 38)
                    .background(option.target.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.target.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(optionStatus)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isSelected ? option.target.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .frame(height: 64)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassSurface(
                cornerRadius: 18,
                tint: isSelected ? option.target.accentColor.opacity(0.16) : .clear,
                interactive: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.target.title)、\(optionStatus)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var optionStatus: String {
        if option.isRecommended { return "このMacにインストール済み・おすすめ" }
        if option.isInstalled { return "このMacにインストール済み" }
        return "依頼文をコピーして使う"
    }
}

private struct AISelectionDetail: View {
    let option: AISetupOption?

    var body: some View {
        if let option {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: option.target.symbolName)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(option.target.accentColor)
                    Spacer()
                    if option.isInstalled {
                        Label("準備済み", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SetupPalette.mint)
                    }
                }
                Spacer()
                Text(option.target.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(option.target.setupDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .padding(.top, 8)
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                    Text("依頼文は自動でコピーされます")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.top, 18)
            }
            .padding(22)
            .glassSurface(cornerRadius: 26, tint: option.target.accentColor.opacity(0.11))
            .transition(.opacity)
            .id(option.target)
        }
    }
}

private struct SetupCapability: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SetupPalette.sky)
                .frame(width: 28, height: 28)
                .background(SetupPalette.sky.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SetupJourneyCard: View {
    private let steps = [
        ("sparkles", "AIを選ぶ", "いつもの相棒に引き継ぐ"),
        ("folder", "保存先を決める", "設定を手元で管理する"),
        ("slider.horizontal.3", "自分仕様にする", "会話しながら整える"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("約2分で準備できます")
                .font(.system(size: 13, weight: .semibold))
            Text("設定はいつでも変更できます。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 13) {
                        VStack(spacing: 0) {
                            Image(systemName: step.0)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 27, height: 27)
                                .background(stepColor(index), in: Circle())
                                .shadow(color: stepColor(index).opacity(0.3), radius: 8)
                            if index < steps.count - 1 {
                                Rectangle()
                                    .fill(LinearGradient(colors: [stepColor(index).opacity(0.45), stepColor(index + 1).opacity(0.25)], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 1, height: 34)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.1)
                                .font(.system(size: 12, weight: .semibold))
                            Text(step.2)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.top, 24)
        }
        .padding(22)
        .glassSurface(cornerRadius: 28, tint: SetupPalette.sky.opacity(0.10))
    }

    private func stepColor(_ index: Int) -> Color {
        [SetupPalette.sky, SetupPalette.violet, SetupPalette.mint][index]
    }
}

private struct SetupProgress: View {
    let currentStep: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { step in
                Capsule(style: .continuous)
                    .fill(step <= currentStep ? SetupPalette.sky : Color.secondary.opacity(0.18))
                    .frame(width: step == currentStep ? 22 : 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("セットアップ \(currentStep + 1) / 3")
    }
}

private struct SetupBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [SetupPalette.sky.opacity(0.08), .clear, SetupPalette.violet.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(SetupPalette.sky.opacity(0.16))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 300, y: -230)
            Circle()
                .fill(SetupPalette.violet.opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 90)
                .offset(x: -330, y: 240)
            VelaRouteShape()
                .stroke(
                    LinearGradient(
                        colors: [.clear, SetupPalette.sky.opacity(0.22), SetupPalette.violet.opacity(0.18), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
                .blur(radius: 0.4)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct VelaRouteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -20, y: rect.height * 0.78))
        path.addCurve(
            to: CGPoint(x: rect.width + 20, y: rect.height * 0.24),
            control1: CGPoint(x: rect.width * 0.27, y: rect.height * 0.96),
            control2: CGPoint(x: rect.width * 0.68, y: rect.height * 0.04)
        )
        return path
    }
}

private func actionBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    HStack(spacing: 12, content: content)
        .controlSize(.large)
        .padding(.top, 20)
}

private enum SetupPalette {
    static let sky = Color(red: 0.22, green: 0.62, blue: 0.98)
    static let violet = Color(red: 0.58, green: 0.44, blue: 0.96)
    static let mint = Color(red: 0.18, green: 0.72, blue: 0.60)
}

private extension AISetupTarget {
    var symbolName: String {
        switch self {
        case .chatGPT: return "bubble.left.and.bubble.right.fill"
        case .claude: return "sun.max.fill"
        case .gemini: return "diamond.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .chatGPT: return SetupPalette.sky
        case .claude: return Color(red: 0.92, green: 0.48, blue: 0.34)
        case .gemini: return SetupPalette.violet
        }
    }

    var setupDescription: String {
        switch self {
        case .chatGPT:
            return "CodexまたはChatGPTとの会話を開き、Velaの初期設定をそのまま始めます。"
        case .claude:
            return "Claudeとの会話を開き、使いたい操作やショートカットを相談しながら設定します。"
        case .gemini:
            return "Geminiを開いて依頼文を貼り付け、Velaの保存先と使い方を一緒に決めます。"
        }
    }
}

private extension View {
    func glassSurface(cornerRadius: CGFloat, tint: Color = .clear, interactive: Bool = false) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}

private struct GlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat
    let tint: Color
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(
                .regular.tint(tint).interactive(interactive),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else if reduceTransparency {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.2)))
                .shadow(color: Color.black.opacity(0.08), radius: 20, y: 8)
        }
    }
}

private struct PrimaryGlassButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .tint(SetupPalette.sky)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .tint(SetupPalette.sky)
        }
    }
}

private struct SecondaryGlassButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
