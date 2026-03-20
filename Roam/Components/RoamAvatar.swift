import SwiftUI

struct RoamAvatar: View {
    let initials: String
    var photoUrl: String?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let photoUrl, let url = URL(string: photoUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsCircle
                    }
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }

    private var initialsCircle: some View {
        ZStack {
            LinearGradient(
                colors: [RoamColors.loganDeep, RoamColors.loganDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initials)
                .font(RoamFont.mono(size * 0.36, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}
