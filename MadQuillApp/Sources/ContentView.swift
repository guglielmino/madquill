import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MadQuill")
                .font(.title)
            Text("This host app installs the Markdown Quick Look extension.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 160)
    }
}
