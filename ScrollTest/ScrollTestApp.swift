import SwiftUI

@main
struct ScrollTestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var scrollTarget: String?

    var body: some View {
        VStack {
            // Tab selector
            Picker("Tab", selection: $selectedTab) {
                Text("Tab 1").tag(0)
                Text("Tab 2").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            // Content
            if selectedTab == 0 {
                Tab1View(onLinkTap: {
                    selectedTab = 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scrollTarget = "section-C"
                    }
                })
            } else {
                Tab2View(scrollTarget: $scrollTarget)
            }
        }
        .frame(width: 400, height: 500)
    }
}

struct Tab1View: View {
    let onLinkTap: () -> Void

    var body: some View {
        VStack {
            Text("This is Tab 1")
            Spacer()
            Button("Go to Section C in Tab 2") {
                onLinkTap()
            }
            Spacer()
        }
    }
}

struct Tab2View: View {
    @Binding var scrollTarget: String?
    @State private var scrollPosition: String?

    let sections = ["A", "B", "C", "D", "E"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(sections, id: \.self) { section in
                    SectionView(name: section)
                        .id("section-\(section)")
                }
            }
            .padding()
        }
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .onChange(of: scrollTarget) { _, newTarget in
            print("onChange: scrollTarget = \(String(describing: newTarget))")
            if let target = newTarget {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    print("Setting scrollPosition to: \(target)")
                    withAnimation {
                        scrollPosition = target
                    }
                }
            }
        }
        .onAppear {
            print("onAppear: scrollTarget = \(String(describing: scrollTarget))")
            if let target = scrollTarget {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    print("onAppear - Setting scrollPosition to: \(target)")
                    withAnimation {
                        scrollPosition = target
                    }
                }
            }
        }
    }
}

struct SectionView: View {
    let name: String

    var body: some View {
        VStack {
            Text("Section \(name)")
                .font(.title)
                .padding()

            ForEach(0..<5) { i in
                Text("Item \(name)-\(i)")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
}
