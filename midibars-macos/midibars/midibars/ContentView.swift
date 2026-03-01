import SwiftUI

struct ContentView: View {
    @StateObject private var project = ProjectState()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(project: project)
            Divider()
            VStack(spacing: 0) {
                VideoCanvasView(project: project)
                if project.audioURL != nil {
                    Divider()
                    AudioWaveformPanel(project: project)
                        .frame(height: 120)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: project.audioURL != nil)
    }
}

#Preview {
    ContentView()
}
