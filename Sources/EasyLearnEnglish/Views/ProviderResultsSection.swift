import SwiftUI

struct ProviderResultsSection: View {
    let title: String
    let results: [DefinitionProviderResult]
    let isLoading: Bool
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            if results.isEmpty {
                Text(emptyText)
                    .foregroundColor(.secondary)
            } else {
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(result.text)
                            .font(.body)
                            .foregroundColor(result.isError ? .secondary : .primary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(6)
                }
            }
        }
    }
}
