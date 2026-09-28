import SwiftUI

struct AppHeader: View {
    @Binding var currentPage: AppPage
    @AppStorage("globalFundamentalsOff") private var fundamentalsOff: Bool = true

    var body: some View {
        HStack(alignment: .center) {
            Spacer()
                .overlay(alignment: .trailing) {
                    fundButton
                        .offset(x: -15, y: -5)
                }

            VStack(spacing: 4) {
                Text("EXOCHRONOMETER")
                    .font(.system(size: 14, weight: .light, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(.white.opacity(0.7))
                Text(currentPage == .circles ? "JOURNAL" : currentPage.label.uppercased())
                    .font(.system(size: 9, weight: .light, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()
                .overlay(alignment: .leading) {
                    menuButton
                        .offset(x: 25, y: -5)
                }
        }
        .padding(.top, 16)
    }

    private var fundButton: some View {
        Button {
            fundamentalsOff.toggle()
        } label: {
            Text(fundamentalsOff ? "FUND OFF" : "FUND ON")
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(!fundamentalsOff ? .black : .white.opacity(0.7))
                .background(Capsule().fill(!fundamentalsOff ? Color.white : .clear))
                .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5))
        }
    }

    private var menuButton: some View {
        Menu {
            ForEach(AppPage.allCases) { page in
                Button {
                    currentPage = page
                } label: {
                    if page == currentPage {
                        Label(page.label, systemImage: "checkmark")
                    } else {
                        Text(page.label)
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
    }
}
