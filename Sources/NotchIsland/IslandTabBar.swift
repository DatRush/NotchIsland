import SwiftUI

struct IslandTabBar: View {
    @ObservedObject var model: Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var drag: TabDrag?

    private struct TabDrag {
        let section: IslandSection
        let translation: CGSize
    }

    private var sections: [IslandSection] { model.visibleSections }
    private var slotWidth: CGFloat { (model.surfaceSize.width - 56) / CGFloat(sections.count) }
    private var sourceIndex: Int? { drag.flatMap { sections.firstIndex(of: $0.section) } }
    private var targetIndex: Int? {
        guard let drag, let sourceIndex else { return nil }
        return destination(from: sourceIndex, translation: drag.translation.width)
    }
    private var settling: Animation? { reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.86) }

    private func destination(from index: Int, translation: CGFloat) -> Int {
        min(sections.count - 1, max(0, index + Int((translation / slotWidth).rounded())))
    }

    private func offset(for index: Int) -> CGFloat {
        guard let drag, let sourceIndex, let targetIndex else { return 0 }
        if index == sourceIndex {
            return min(CGFloat(sections.count - 1 - index) * slotWidth,
                       max(-CGFloat(index) * slotWidth, drag.translation.width))
        }
        if sourceIndex < targetIndex && index > sourceIndex && index <= targetIndex { return -slotWidth }
        if targetIndex < sourceIndex && index >= targetIndex && index < sourceIndex { return slotWidth }
        return 0
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                let lifted = drag?.section == section
                Button { model.select(section) } label: {
                    Image(systemName: section.icon)
                        .font(.system(size: 17))
                        .frame(width: 42, height: 32)
                        .foregroundColor(lifted || model.section == section ? .white : .gray)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(lifted ? 0.25 : model.section == section ? 0.16 : 0)))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(lifted ? 0.65 : 0), lineWidth: 1))
                        .scaleEffect(lifted && !reduceMotion ? 1.12 : 1)
                        .shadow(color: .black.opacity(lifted ? 0.65 : 0), radius: 5, y: 3)
                        .frame(width: slotWidth, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .highPriorityGesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("island-tabs"))
                    .updating($drag) { value, state, transaction in
                        transaction.animation = nil
                        state = TabDrag(section: section, translation: value.translation)
                    }
                    .onEnded { value in
                        let destination = destination(from: index, translation: value.translation.width)
                        withAnimation(settling) {
                            model.moveSection(section.rawValue, to: sections[destination])
                        }
                    })
                .offset(x: offset(for: index), y: lifted ? -3 : 0)
                .zIndex(lifted ? 1 : 0)
                // The held icon tracks the pointer directly; only its neighbours settle.
                .animation(lifted ? nil : settling, value: targetIndex)
                .animation(settling, value: drag?.section)
                .help(section.title + L(" · Перетащи, чтобы изменить порядок", " · Drag to reorder"))
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(model.section == section ? .isSelected : [])
            }
        }
        .coordinateSpace(name: "island-tabs")
    }
}
