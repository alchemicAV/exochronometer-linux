import SwiftUI

struct NoteIndicator: View {
    let opacity: Double
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: 12, height: 12)
            Circle()
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
                .frame(width: 12, height: 12)

            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .fill(.white)
                    .frame(width: 3, height: 3)
            }
        }
        .opacity(opacity)
        .shadow(color: .white.opacity(opacity * 0.6), radius: 4)
    }
}
