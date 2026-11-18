import SwiftUI
import BrawlCore

/// 화면 인식이 안 될 때 맵을 직접 고르는 목록 (현재 맵 풀, 랭크 모드 먼저)
struct MapPickerView: View {
    let maps: [CatalogMap]
    let onPick: (CatalogMap) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [CatalogMap] {
        let q = query.lowercased()
        let list = q.isEmpty ? maps : maps.filter { $0.ko.lowercased().contains(q) || $0.name.lowercased().contains(q) || $0.modeKo.contains(q) }
        return list.filter(\.ranked) + list.filter { !$0.ranked }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { m in
                Button { onPick(m); dismiss() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.ko).foregroundStyle(Theme.text)
                        Text("\(m.modeKo) · \(m.name)").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $query, prompt: "맵 이름 (한글·영문)")
            .navigationTitle("맵 직접 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
