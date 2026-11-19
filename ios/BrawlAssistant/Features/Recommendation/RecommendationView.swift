import SwiftUI
import BrawlCore

/// 추천 카드: 순위별 조합을 한 줄씩 (캐릭터 → 오른쪽에 추정 승률). 줄을 누르면 그 조합의 역할·픽 순서·근거를 아래에 보여 준다.
/// 값은 모두 엔진 결과 그대로 (점수·추정 승률·근거·역할·픽 순서·표시 문자열)
/// 디자인: 바탕·라벨은 무채색, 색은 브롤러 아트와 1위 추정 승률(강조색 하나)에만. 글자는 Dynamic Type 텍스트 스타일
struct RecommendationView: View {
    let recommendation: Recommendation
    let result: EngineResult?
    let store: SharedStore?
    @State private var selectedRank = 1

    /// 엔진 결과가 없으면(예외적) 1위 추천만 한 줄로
    private var teams: [TeamResult] { result?.teams ?? [] }
    private var selected: TeamResult? { teams.first { $0.rank == selectedRank } ?? teams.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 맵 · 모드
            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.mapName).font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                Text("\(recommendation.gameMode), \(recommendation.mapNameEn)").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }

            // 순위별 조합 리스트
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("추천 조합").font(.headline).foregroundStyle(Theme.text)
                    Text("종합 점수 순").font(.footnote).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text("추정 승률").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                VStack(spacing: 4) {
                    if teams.isEmpty {
                        TeamRankRow(rank: 1, members: recommendation.brawlers, winRate: recommendation.estimatedWinRate,
                                    score: recommendation.score, store: store, selected: true)
                    }
                    ForEach(teams, id: \.rank) { t in
                        Button { withAnimation(.easeOut(duration: 0.2)) { selectedRank = t.rank } } label: {
                            TeamRankRow(rank: t.rank, members: t.members, winRate: t.estimatedWinRate, score: t.score,
                                        store: store, selected: t.rank == (selected?.rank ?? 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(t.rank)위 \(t.members.map(\.ko).joined(separator: ", ")), 추정 승률 \(t.estimatedWinRate)%")
                    }
                }
                if let r = result {
                    Text("\(r.countText)개 조합을 계산한 결과입니다. 추정 승률과 종합 점수는 Draft Room 엔진의 계산값이며 공식 통계가 아닙니다")
                        .font(.caption).foregroundStyle(Theme.secondaryText).padding(.top, 4)
                }
            }

            // 선택한 조합의 자세한 내용
            if let t = selected {
                TeamDetail(team: t, store: store)
            } else {
                TeamDetail(members: recommendation.brawlers, title: "BEST TEAM", archetype: recommendation.archetype,
                           reasons: recommendation.reasons, store: store)
            }
        }
        .onChange(of: recommendation.mapID) { _, _ in selectedRank = 1 }
    }
}

/// 리스트 한 줄: 순위 · 캐릭터(초상화+이름) · 오른쪽 추정 승률과 종합 점수
struct TeamRankRow: View {
    let rank: Int
    let members: [TeamMember]
    let winRate: String
    let score: Int
    let store: SharedStore?
    let selected: Bool

    private var size: CGFloat { members.count > 3 ? 32 : 44 }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)").font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(rank == 1 ? Theme.text : Theme.secondaryText).frame(width: 16)
            HStack(alignment: .top, spacing: members.count > 3 ? 4 : 8) {
                ForEach(members) { m in
                    VStack(spacing: 4) {
                        BrawlerPortrait(id: m.id, url: m.img, store: store, radius: size * 0.25)
                            .frame(width: size, height: size)
                        if members.count <= 3 {
                            Text(m.ko).font(.caption2).foregroundStyle(Theme.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .frame(width: members.count > 3 ? size : size + 12)
                }
            }
            Spacer(minLength: 8)
            // 숫자는 줄바꿈되거나 줄어들지 않게 고정 (좁으면 캐릭터 쪽이 양보)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(winRate).font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(rank == 1 ? Theme.accent : Theme.text)
                    Text("%").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                Text("종합 \(score)").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(selected ? Theme.secondaryBackground : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// 선택한 조합: 역할·픽 순서·실전 승률 효과, 추천 근거
struct TeamDetail: View {
    let members: [TeamMember]
    let title: String
    let archetype: String
    let reasons: [String]
    let store: SharedStore?

    init(team: TeamResult, store: SharedStore?) {
        members = team.members
        title = team.rank == 1 ? "BEST TEAM" : "\(team.rank)위 조합"
        archetype = team.archetype
        reasons = team.plainReasons
        self.store = store
    }

    init(members: [TeamMember], title: String, archetype: String, reasons: [String], store: SharedStore?) {
        self.members = members; self.title = title; self.archetype = archetype; self.reasons = reasons; self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text(archetype).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                VStack(spacing: 0) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { i, m in
                        MemberRow(member: m, store: store)
                        if i < members.count - 1 { Hairline().padding(.leading, 56) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("추천 근거").font(.headline).foregroundStyle(Theme.text)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(reasons.enumerated()), id: \.offset) { _, r in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").font(.subheadline).foregroundStyle(Theme.secondaryText)
                            Text(r).font(.subheadline).foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

/// 조합 멤버 한 줄: 초상화 · 이름과 역할 · 오른쪽에 픽 순서와 실전 승률 효과
struct MemberRow: View {
    let member: TeamMember
    let store: SharedStore?

    var body: some View {
        HStack(spacing: 12) {
            BrawlerPortrait(id: member.id, url: member.img, store: store, radius: 10)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.ko).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text([member.role, member.estimatedProfile ? "추정 프로필" : nil].compactMap { $0 }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let p = member.pick { PickTag(pick: p) }
                if let e = member.eff, let text = member.effPct {
                    // 표시 문자열은 엔진(웹과 같은 toFixed) 값 그대로
                    Text("실전 \(text)%p").font(.caption.monospacedDigit()).foregroundStyle(e >= 0 ? Theme.positive : Theme.error)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

/// 픽 순서 태그 (작은 키캡)
struct PickTag: View {
    let pick: Int
    var body: some View {
        Text("\(pick)픽")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// 브롤러 초상화: App Group 에 저장된 작은 이미지 → 없으면 네트워크 이미지
struct BrawlerPortrait: View {
    let id: Int
    let url: String?
    let store: SharedStore?
    var radius: CGFloat = 16

    var body: some View {
        ZStack {
            Theme.secondaryBackground
            if let path = store?.portraitURL(brawlerID: id).path, let img = UIImage(contentsOfFile: path) {
                Image(uiImage: img).resizable().scaledToFit().padding(2)
            } else if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { $0.resizable().scaledToFit().padding(2) } placeholder: { Color.clear }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// 얇은 구분선 (무채색)
struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.divider).frame(height: 0.5) }
}
