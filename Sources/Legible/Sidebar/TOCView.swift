import AppKit
import SwiftUI

/// Headings of the current document and which one is being read.
@Observable
final class TOCModel {
    struct Heading: Identifiable, Equatable {
        let level: Int
        let text: String
        let id: String
    }

    struct Palette: Equatable {
        var background = Color(nsColor: .windowBackgroundColor)
        var text = Color(nsColor: .labelColor)
        var muted = Color(nsColor: .secondaryLabelColor)
        var accent = Color.accentColor
        var rule = Color(nsColor: .separatorColor)
    }

    var headings: [Heading] = []
    var currentID: String?
    var palette = Palette()
    var onSelect: ((String) -> Void)?

    func apply(theme: Theme) {
        func color(_ name: String, _ fallback: Color) -> Color {
            theme.variable(name).flatMap(NSColor.init(hex:)).map(Color.init(nsColor:)) ?? fallback
        }
        palette = Palette(background: color("bg", Color(nsColor: .windowBackgroundColor)),
                          text: color("fg", Color(nsColor: .labelColor)),
                          muted: color("fg-muted", Color(nsColor: .secondaryLabelColor)),
                          accent: color("link", .accentColor),
                          rule: color("rule", Color(nsColor: .separatorColor)))
    }
}

struct TOCView: View {
    @Bindable var model: TOCModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var minLevel: Int { model.headings.map(\.level).min() ?? 1 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.headings.isEmpty {
                        Text("No headings")
                            .foregroundStyle(model.palette.muted)
                            .padding(16)
                    }
                    ForEach(model.headings) { heading in
                        row(heading)
                            .id(heading.id)
                    }
                }
                .padding(.vertical, 10)
            }
            .onChange(of: model.currentID) { _, id in
                guard let id else { return }
                if reduceMotion { proxy.scrollTo(id, anchor: .center) } else {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .background(model.palette.background)
        .overlay(alignment: .trailing) { Rectangle().fill(model.palette.rule).frame(width: 1) }
        .accessibilityLabel("Table of contents")
    }

    private func row(_ heading: TOCModel.Heading) -> some View {
        let isCurrent = heading.id == model.currentID
        let depth = max(0, heading.level - minLevel)
        return Button {
            model.onSelect?(heading.id)
        } label: {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(isCurrent ? model.palette.accent : .clear)
                    .frame(width: 3)
                Text(heading.text)
                    .font(depth == 0 ? .system(size: 13, weight: .semibold) : .system(size: 12))
                    .foregroundStyle(isCurrent ? model.palette.text : (depth == 0 ? model.palette.text : model.palette.muted))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.leading, CGFloat(depth) * 12)
                Spacer(minLength: 0)
            }
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}
