import SwiftUI

struct LicensesView: View {
    private let documents = [
        ("SFBAudioEngine", "SFBAudioEngine"),
        ("GRDB.swift", "GRDB"),
        ("Third-Party Notices", "ThirdPartyNotices"),
        ("AutoEq Attribution", "AutoEq-Attribution")
    ]

    var body: some View {
        List(documents, id: \.0) { title, resource in
            NavigationLink(title) {
                ScrollView {
                    Text(load(resource: resource))
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(title)
            }
        }
        .navigationTitle("Licenses")
    }

    private func load(resource: String) -> String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return String(localized: "License text is unavailable in this build.")
        }
        return text
    }
}
