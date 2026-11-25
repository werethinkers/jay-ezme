import SwiftUI
import AuthenticationServices

// MARK: - Presentation context for ASWebAuthenticationSession

final class WebAuthContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }
}

// MARK: - Sign-in buttons view

struct KeyDoOAuthButtons: View {
    @ObservedObject var cloud: EzMeCloud
    var onSignedIn: (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.signIn) { request in
                cloud.prepareAppleSignIn(request: request)
            } onCompletion: { result in
                cloud.completeAppleSignIn(result: result, onSignedIn: onSignedIn)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(width: 280, height: 44)
            .cornerRadius(8)
            .disabled(cloud.isWorking)

            Button { cloud.signInWithGoogle(onSignedIn: onSignedIn) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "globe").font(.system(size: 15, weight: .semibold))
                    Text("Sign in with Google").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color.black.opacity(0.75))
                .frame(width: 280, height: 44)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(cloud.isWorking)
        }
    }
}
