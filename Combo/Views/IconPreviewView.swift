import SwiftUI

struct IconPreviewView: View {
    @ObservedObject var store: Store
    let close: () -> Void
    @State private var group: IconPreviewGroup = .network
    @State private var selected: IconPreviewScene?
    @State private var variant = 0
    @State private var hoveredGroup: IconPreviewGroup?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.comboPalette) private var palette

    private var snapshot: Snapshot { selected?.variants[variant].snapshot ?? store.snapshot(for: .live) }
    private var title: String { selected?.title ?? L("当前状态") }
    private var description: String {
        selected?.variants[variant].detail ?? selected?.detail
            ?? L("电量 \(snapshot.batteryText) · \(LKey(snapshot.network)) · 音量 \(snapshot.volumeText)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: close) { Label(L("返回外观"), systemImage: "chevron.left") }
                    .accessibilityIdentifier("icon-preview-back")
                Spacer()
                Button(L("当前状态")) { variant = 0; selected = nil }
                    .accessibilityAddTraits(selected == nil ? .isSelected : [])
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(palette.accent)
            HStack {
                Text(L("效果预览")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(L("33 种")).font(.system(size: 11)).foregroundStyle(palette.mutedText)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 20) {
                    ComboIcon(snapshot: snapshot, animate: selected == nil ? store.animate : true, size: 76)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Text(description).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let selected, selected.variants.count > 1 {
                            Picker(L("变体"), selection: $variant) {
                                ForEach(selected.variants.indices, id: \.self) { index in
                                    Text(selected.variants[index].title).tag(index)
                                }
                            }.pickerStyle(.menu).controlSize(.small).fixedSize()
                                .accessibilityIdentifier("icon-preview-variant")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 92).padding(.horizontal, 6).padding(.bottom, 14)
                VStack(spacing: 6) {
                    HStack(spacing: 14) {
                        Text("Combo").font(.system(size: 11, weight: .semibold))
                        Spacer(minLength: 0)
                        ComboIcon(snapshot: snapshot, animate: selected == nil ? store.animate : true, size: 22)
                            .accessibilityLabel(L("菜单栏实际大小"))
                        Text(Date(), format: .dateTime.weekday(.abbreviated).hour().minute()).font(.system(size: 11)).monospacedDigit()
                    }.padding(.horizontal, 12).padding(.vertical, 6).frame(width: 280)
                        .background(palette.previewSurface, in: RoundedRectangle(cornerRadius: 9))
                    Text(L("实际大小")).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                }.frame(maxWidth: .infinity).padding(.bottom, 16)
                separator
                groups.padding(.vertical, 10)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 3) {
                        ForEach(group.scenes) { scene in
                            Button { variant = 0; selected = scene } label: {
                                HStack(spacing: 10) {
                                    Image(nsImage: IconRenderer.image(scene.variants[0].snapshot, animate: true, size: 30, phase: 0.3, dark: colorScheme == .dark))
                                        .frame(width: 30, height: 30).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(scene.title).font(.system(size: 11, weight: .medium))
                                        Text(scene.condition).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                                    }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                                }.frame(minHeight: 40)
                            }.buttonStyle(PanelRowButtonStyle())
                                .background(selected?.id == scene.id ? palette.accent.opacity(0.10) : .clear,
                                            in: RoundedRectangle(cornerRadius: 9))
                                .accessibilityAddTraits(selected?.id == scene.id ? .isSelected : [])
                                .accessibilityIdentifier("icon-preview-scene-\(scene.id)")
                        }
                    }.padding(2)
                }.scrollBounceBehavior(.basedOnSize).id(group).frame(minHeight: 120)
                    .accessibilityIdentifier("icon-preview-scenes")
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.note)
                    Text(L("可预览未连接的设备；预览不改变菜单栏状态。"))
                }.font(.system(size: 11)).foregroundStyle(palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10).padding(.bottom, 14)
            }.padding(.horizontal, 16).padding(.top, 18)
                .background(palette.inset, in: RoundedRectangle(cornerRadius: 14))
        }.padding(.horizontal, 30).padding(.top, 19).padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityIdentifier("icon-preview")
    }

    @ViewBuilder private var separator: some View {
        if contrast == .increased { Divider() }
        else { Rectangle().fill(palette.separator).frame(height: 0.5) }
    }

    private var groups: some View {
        HStack(spacing: 3) {
            ForEach(IconPreviewGroup.allCases) { item in
                Button { group = item } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) { Text(item.title); Text(item.scenes.count.formatted()) }
                        VStack(spacing: 2) { Text(item.title); Text(item.scenes.count.formatted()) }
                    }.font(.system(size: 11)).frame(maxWidth: .infinity, minHeight: 33)
                        .foregroundStyle(group == item ? palette.primaryText : palette.mutedText)
                        .background(group == item ? palette.selected : hoveredGroup == item ? palette.field : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).onHover { hoveredGroup = $0 ? item : nil }
                    .accessibilityAddTraits(group == item ? .isSelected : [])
                    .accessibilityLabel(L("\(item.title)，\(item.scenes.count) 种效果"))
            }
        }.accessibilityElement(children: .contain).accessibilityLabel(L("效果分组"))
    }
}
