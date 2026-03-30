import SwiftUI

struct SettingsView: View {
    private enum Tabs: Hashable {
        case connection, general
    }
    
    var body: some View {
        TabView {
            ConnectionSettingsView()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }
                .tag(Tabs.connection)
            
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tabs.general)
        }
        .frame(width: 450, height: 250)
    }
}

struct ConnectionSettingsView: View {
    @AppStorage("apiEndpoint") private var apiEndpoint = "https://api.yourdomain.com"
    @AppStorage("apiKey") private var apiKey = ""
    
    var body: some View {
        Form {
            Section {
                TextField("Server URL:", text: $apiEndpoint)
                    .textFieldStyle(.roundedBorder)
                    .help("The backend API endpoint to connect the agent.")
                
                SecureField("API Token:", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .help("Authentication token for secure API access.")
            }
            
            Divider()
                .padding(.vertical, 8)
            
            HStack {
                Spacer()
                Button("Test Connection") {
                    // Logic to ping the API
                }
            }
        }
        .padding(20)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("refreshRate") private var refreshRate = 5
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .help("Automatically start MissionControl when you log into your Mac.")
            }
            
            Divider()
                .padding(.vertical, 8)
            
            Section {
                Picker("Refresh Interval:", selection: $refreshRate) {
                    Text("Real-time (WebSocket)").tag(0)
                    Text("Every 3 seconds").tag(3)
                    Text("Every 5 seconds").tag(5)
                    Text("Every 10 seconds").tag(10)
                }
                .pickerStyle(.menu)
            }
        }
        .padding(20)
    }
}

// MARK: - Manual Settings Window Manager

class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 250),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "Settings"
            win.center()
            win.setFrameAutosaveName("MissionControl Settings")
            win.contentView = NSHostingView(rootView: SettingsView())
            win.isReleasedWhenClosed = false
            self.window = win
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
