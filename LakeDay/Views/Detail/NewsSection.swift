import SwiftUI

/// The "News & alerts" list on the detail view (DATA-FEEDS §10). Alerts read
/// in the caution hue with a warning glyph; news reads quietly with a newspaper
/// glyph. Rows with a link open in Safari. The section chrome (title + card)
/// lives in `LakeDetailView`, so this is just the inner list — like `BeachRow`.
struct NewsSection: View {
    let items: [NewsItem]

    var body: some View {
        if items.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "newspaper")
                    .foregroundStyle(Color.secondaryText)
                    .imageScale(.small)
                Text("No recent news or alerts for this lake.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(for: item)
                    if index < items.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    /// Link-wrapped when the item has a URL, plain otherwise.
    @ViewBuilder
    private func row(for item: NewsItem) -> some View {
        if let url = item.url {
            Link(destination: url) { rowContent(item) }
                .buttonStyle(.plain)
        } else {
            rowContent(item)
        }
    }

    private func rowContent(_ item: NewsItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: item.kind == .alert ? "exclamationmark.triangle" : "newspaper")
                .foregroundStyle(item.kind == .alert ? Color.safetyCaution : Color.secondaryText)
                .imageScale(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)

                Text(caption(item))
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
            }

            Spacer(minLength: 8)

            if item.url != nil {
                Image(systemName: "arrow.up.forward")
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())   // whole row is tappable when linked
    }

    /// "source · 3d ago", or just the source when the date is unknown.
    private func caption(_ item: NewsItem) -> String {
        if let date = item.publishedAt {
            return "\(item.source) · \(Staleness.ago(date))"
        }
        return item.source
    }
}

#Preview("News & alerts", traits: .sizeThatFitsLayout) {
    NewsSection(items: MockPreviewBuilder.state(id: "green-lake").news)
        .padding()
        .background(Color.appBackground)
}
