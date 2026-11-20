import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "snowflake")
                .font(.system(size: 60))
            Text("SnowPlow")
                .font(.largeTitle)
                .bold()
            Text("Setup test works!")
                .font(.title3)
        }
        .padding()
    }
}
