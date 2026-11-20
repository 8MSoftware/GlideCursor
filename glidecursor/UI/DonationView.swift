import SwiftUI

/// 2回目以降の起動で出す、寄付のお願い。「今後は表示しない」を付けて閉じるまで出す。
/// 閉じるときに、歯車のメニューからいつでも寄付できることを伝える。
struct DonationView: View {
    var onFinish: () -> Void
    @State private var dontShowAgain = false
    @State private var closing = false

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            if closing {
                Text("Thank you!").font(.title3).fontWeight(.semibold)
                Text("You can donate any time from the gear menu in the settings. If you like GlideCursor, we'd be glad of your support!")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("OK") { onFinish() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            } else {
                Text("GlideCursor is free").font(.title3).fontWeight(.semibold)
                Text("If GlideCursor fits the way you work, a donation would help keep it going and working with future versions of macOS.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Close") { close() }
                        .controlSize(.large)
                    Button("Donate") {
                        Donation.open()
                        close()
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                }
                Toggle("Don't show this again", isOn: $dontShowAgain)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
        }
        .padding(28)
        .frame(width: 380)
    }

    private func close() {
        if dontShowAgain { SettingsManager.shared.donationPromptDismissed = true }
        closing = true
    }
}

enum Donation {
    static let url = URL(string: "https://donate.stripe.com/fZu14n1BefAPbkF9NdgA804")!
    static func open() { NSWorkspace.shared.open(url) }
}
