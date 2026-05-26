import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case record
    case library
    case settings
}

struct RootView: View {
    @State private var selection: SidebarItem? = .record
    @EnvironmentObject private var modelManager: ModelManager

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Workspace") {
                    Label("Record", systemImage: "mic.fill")
                        .tag(SidebarItem.record)
                    Label("Library", systemImage: "tray.full.fill")
                        .tag(SidebarItem.library)
                }
                #if os(iOS)
                Section("App") {
                    Label("Settings", systemImage: "gearshape.fill")
                        .tag(SidebarItem.settings)
                }
                #endif
            }
            .navigationTitle("AudioScribe")
            #if os(macOS)
            .frame(minWidth: 200)
            #endif
        } detail: {
            switch selection ?? .record {
            case .record:
                RecorderView()
            case .library:
                LibraryView()
            case .settings:
                SettingsView()
            }
        }
        .task {
            await modelManager.refreshAvailableModels()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(TranscriptionService())
        .environmentObject(ModelManager())
        .modelContainer(for: [TranscriptionSession.self, TranscriptSegment.self], inMemory: true)
}
