import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)
                    Text("KMac Pilot")
                        .font(.largeTitle.bold())
                    Text("Connect to your Mac")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Server URL", systemImage: "link")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("http://192.168.1.x:7890", text: $appState.serverURL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Auth Token", systemImage: "key")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        SecureField("Paste token from server", text: $appState.token)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }
                .padding(.horizontal, 24)

                if let error = appState.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task { await appState.connect() }
                } label: {
                    HStack {
                        if appState.isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Connect")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.serverURL.isEmpty || appState.token.isEmpty || appState.isLoading)
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 4) {
                    Text("Run on your Mac:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("pilot server start")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
