import SwiftUI

struct ContentView: View {
    @StateObject private var project = ProjectState()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(project: project)
            Divider()
            VideoCanvasView(project: project)
        }
    }
}

#Preview {
    ContentView()
}
