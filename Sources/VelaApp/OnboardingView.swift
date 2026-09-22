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
        VStack(spacing: 0) {
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
        .frame(minWidth: 520, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand(perform: dismiss)
    }

    private var introduction: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
            Text(introductionTitle)
                .font(.system(size: 24, weight: .semibold))
                .padding(.top, 20)
            Text("よく使うアプリ、ショートカット、定型文を、\nいつものAIと相談しながら設定できます。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 10)
            Spacer(minLength: 24)
            footer {
                Button("導入手順", action: showGuide)
                    .buttonStyle(.link)
                Spacer()
                Button("あとで", action: dismiss)
                Button("設定を始める", action: continueToAIChoice)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var introductionTitle: String {
        if case .installationComplete = page { return "インストールが完了しました" }
        return "Velaへようこそ"
    }

    private func handoff(target: AISetupTarget, openedAutomatically: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)
            Text(openedAutomatically ? "\(target.title)で続ける" : "依頼文をコピーしました")
                .font(.system(size: 24, weight: .semibold))
                .padding(.top, 22)
            Text("AIの会話に依頼文が入っていない場合は、\n⌘Vで貼り付けて送信してください。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 12)
            Spacer(minLength: 24)
            footer {
                Button("戻る", action: backToAIChoice)
                Spacer()
                Button("閉じる", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("設定に使うAIを選ぶ")
                    .font(.system(size: 22, weight: .semibold))
                Text("選んだアプリを開き、設定の依頼文を渡します。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Picker("AI", selection: $selectedTarget) {
                    ForEach(options, id: \.target) { option in
                        HStack(spacing: 8) {
                            Text(option.target.title)
                            if option.isInstalled {
                                Text("インストール済み")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 11))
                            }
                        }
                        .padding(.vertical, 7)
                        .tag(option.target)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .padding(.top, 14)
                Text("アプリがない場合も、依頼文をコピーして使えます。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(32)
            Spacer(minLength: 0)
            footer {
                Button("戻る", action: back)
                Spacer()
                Button("続ける") { continueWith(selectedTarget) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private func footer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) {
        Divider()
        HStack(spacing: 12, content: content)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
    }
}
