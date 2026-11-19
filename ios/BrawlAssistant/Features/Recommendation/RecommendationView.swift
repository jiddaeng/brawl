import SwiftUI
import BrawlCore

/// 추천 카드: 웹 Draft Room 결과 화면과 같은 구성
/// MAP INTEL 머리 → 순위별 조합 리스트(웹 .alt 줄) → 선택한 조합의 S-TIER 카드(브롤러 카드·점수·KPI·평가 막대·근거·픽 순서·천적)
/// 값은 모두 엔진 결과 그대로 (점수·추정 승률·근거·역할·픽 순서·표시 문자열)
struct RecommendationView: View {
    let recommendation: Recommendation
    let result: EngineResult?
    let store: SharedStore?
    @State private var selectedRank = 1

    private var teams: [TeamResult] { result?.teams ?? [] }
    private var selected: TeamResult? { teams.first { $0.rank == selectedRank } ?? teams.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MapIntelHeader(recommendation: recommendation, size: result?.map.size)
            rankList
            if let t = selected {
                TeamDetail(team: t, countText: result?.countText, store: store)
            } else {
                TeamDetail(members: recommendation.brawlers, rank: 1, archetype: recommendation.archetype,
                           reasons: recommendation.reasons, score: recommendation.score,
                           winRate: recommendation.estimatedWinRate, store: store)
            }
        }
        .onChange(of: recommendation.mapID) { _, _ in selectedRank = 1 }
    }

    private var rankList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("추천 조합").font(Theme.ko(20)).foregroundStyle(Theme.text)
                Text("종합 점수 순").font(Theme.mono(11)).foregroundStyle(Theme.secondaryText)
                Spacer()
                Text("추정 승률").font(Theme.mono(11)).foregroundStyle(Theme.secondaryText)
            }
            VStack(spacing: 8) {
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
                Text("\(r.countText)개 조합 시뮬레이션. 추정 승률과 종합 점수는 Draft Room 엔진 계산값이며 공식 통계가 아닙니다")
                    .font(.caption2).foregroundStyle(Theme.secondaryText).padding(.top, 2)
            }
        }
    }
}

/// 웹 .hinfo: MAP INTEL 눈썹 · 큰 맵 이름(그림자) · 영문 이름 · 모드 칩
struct MapIntelHeader: View {
    let recommendation: Recommendation
    let size: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MAP INTEL · \(recommendation.gameModeEn.uppercased())")
                .font(Theme.mono(11).weight(.bold)).tracking(2).foregroundStyle(Theme.accent)
            Text(recommendation.mapName)
                .font(Theme.ko(32, relativeTo: .largeTitle)).foregroundStyle(Theme.text)
                .shadow(color: .black, radius: 0, x: 0, y: 3)
                .lineLimit(2).minimumScaleFactor(0.6)
            Text(recommendation.mapNameEn).font(Theme.mono(12)).foregroundStyle(Theme.secondaryText)
            HStack(spacing: 6) {
                Chip { Text(recommendation.gameMode).foregroundStyle(Theme.text) }
                if let n = size { Chip { Text(n == 1 ? "솔로" : "\(n)인 팀") } }
                Chip {
                    Circle().fill(Theme.positive).frame(width: 6, height: 6)
                    Text("현재 맵 풀").foregroundStyle(Theme.positive)
                }
            }
            .padding(.top, 2)
        }
    }
}

/// 리스트 한 줄 (웹 .alt): 순위 · 캐릭터 · 오른쪽 추정 승률과 종합 점수. 선택한 줄은 금색 테두리
struct TeamRankRow: View {
    let rank: Int
    let members: [TeamMember]
    let winRate: String
    let score: Int
    let store: SharedStore?
    let selected: Bool

    private var size: CGFloat { members.count > 3 ? 30 : 42 }
    private var isBest: Bool { rank == 1 }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)").font(Theme.display(26)).foregroundStyle(isBest ? Theme.accent : Theme.secondaryText)
                .frame(width: 22)
            portraits
            Spacer(minLength: 6)
            numbers.fixedSize().layoutPriority(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(Theme.deep, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Theme.accent : Theme.line, lineWidth: selected ? 1.5 : 1))
        .shadow(color: selected ? Theme.accent.opacity(0.25) : .clear, radius: 10)
        .contentShape(Rectangle())
    }

    private var portraits: some View {
        HStack(alignment: .top, spacing: members.count > 3 ? 4 : 6) {
            ForEach(members) { m in
                VStack(spacing: 3) {
                    BrawlerPortrait(id: m.id, url: m.img, store: store, rarity: m.rarity, radius: size * 0.28)
                        .frame(width: size, height: size)
                    if members.count <= 3 {
                        Text(m.ko).font(Theme.ko(11)).foregroundStyle(Theme.text.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .frame(width: members.count > 3 ? size : size + 10)
            }
        }
    }

    private var numbers: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(winRate).font(Theme.display(26)).foregroundStyle(isBest ? Theme.accent : Theme.text)
                Text("%").font(Theme.display(14)).foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            Text("종합 \(score)").font(Theme.mono(11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
    }
}

/// 선택한 조합 (웹 .card.best): S-TIER 태그 · 브롤러 카드 · 점수와 KPI · 평가 막대 · 근거 · 드래프트 순서 · 천적
struct TeamDetail: View {
    let members: [TeamMember]
    let rank: Int
    let archetype: String
    let reasons: [String]
    let score: Int
    let winRate: String
    var countText: String? = nil
    var counterPercent: Int? = nil
    var factors: [Factor] = []
    var threats: [TeamMember] = []
    let store: SharedStore?

    init(team: TeamResult, countText: String?, store: SharedStore?) {
        members = team.members
        rank = team.rank
        archetype = team.archetype
        reasons = team.plainReasons
        score = team.score
        winRate = team.estimatedWinRate
        self.countText = countText
        counterPercent = team.counterPercent
        factors = team.factors.filter { $0.percent != nil }
        threats = team.threats
        self.store = store
    }

    init(members: [TeamMember], rank: Int, archetype: String, reasons: [String], score: Int, winRate: String, store: SharedStore?) {
        self.members = members; self.rank = rank; self.archetype = archetype; self.reasons = reasons
        self.score = score; self.winRate = winRate; self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            title
            BrawlerCardRow(members: members, store: store)
            ScoreBlock(score: score, winRate: winRate, countText: countText, counterPercent: counterPercent)
            if !factors.isEmpty { FactorBars(factors: factors) }
            InfoBox(title: "왜 이 조합인가") { BulletList(items: reasons) }
            if members.count > 1, members.contains(where: { $0.pick != nil }) {
                InfoBox(title: "드래프트 순서") { DraftOrderList(members: members) }
            }
            if !threats.isEmpty {
                InfoBox(title: "밴 추천 · 이 조합의 천적") {
                    ThreatChips(threats: threats, store: store)
                    Text("상위 메타 브롤러 중 이 조합을 가장 강하게 카운터하는 순서입니다")
                        .font(.caption2).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(16)
        .background(Theme.cardGradient, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.accent.opacity(rank == 1 ? 1 : 0.5), lineWidth: 1.5))
        .shadow(color: Theme.accent.opacity(rank == 1 ? 0.22 : 0.08), radius: 18)
    }

    private var title: some View {
        HStack(alignment: .center, spacing: 8) {
            GoldTag(text: rank == 1 ? "S-TIER" : "#\(rank)")
            Text(rank == 1 ? "BEST TEAM" : "\(rank)위 조합")
                .font(rank == 1 ? Theme.display(22) : Theme.ko(20))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 4)
            Text(archetype).font(Theme.ko(14)).foregroundStyle(Theme.accent).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

/// 브롤러 카드 줄 (3명 이하는 한 줄, 5명은 3열 그리드)
struct BrawlerCardRow: View {
    let members: [TeamMember]
    let store: SharedStore?
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: min(3, max(1, members.count)))
    }
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(members) { m in BrawlerCard(member: m, store: store) }
        }
    }
}

/// 웹 .br: 희귀도 색 빛 바탕 + 같은 색 테두리, 픽 순서 태그, 이름(Black Han Sans), 영문·포지션(모노), 역할 알약, 실전 효과
struct BrawlerCard: View {
    let member: TeamMember
    let store: SharedStore?
    private var rc: Color { Theme.rarity(member.rarity) }

    var body: some View {
        VStack(spacing: 4) {
            PortraitImage(id: member.id, url: member.img, store: store)
                .frame(width: 62, height: 62)
                .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 4)
                .padding(.top, 6)
            Text(member.ko).font(Theme.ko(17)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
            Text(enLine).font(Theme.mono(9)).foregroundStyle(Theme.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
            if let role = member.role {
                Text(role).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            if let e = member.eff, let text = member.effPct {
                Text("실전 \(text)%p").font(Theme.mono(11).weight(.bold)).foregroundStyle(e >= 0 ? Theme.positive : Theme.error)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 6).padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(rc, lineWidth: 2))
        .overlay(alignment: .topLeading) {
            if let p = member.pick { PickTag(pick: p, color: rc).padding(6) }
        }
        .accessibilityElement(children: .combine)
    }

    private var enLine: String { "\(member.name) · \(member.positionKo)" }

    private var cardBackground: some View {
        ZStack {
            Theme.deep
            RadialGradient(colors: [rc.opacity(0.85), .clear], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 90)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 웹 .score: 큰 점수(Lilita, 금색, 갈색 그림자) + KPI 세 개
struct ScoreBlock: View {
    let score: Int
    let winRate: String
    let countText: String?
    let counterPercent: Int?

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(score)").font(Theme.display(58)).foregroundStyle(Theme.goldGradient)
                    .shadow(color: Theme.goldShadow, radius: 0, x: 0, y: 4)
                Text("/ 100").font(Theme.display(16)).foregroundStyle(Theme.secondaryText)
            }
            .fixedSize()
            Spacer(minLength: 0)
            Kpi(label: "추정 승률", value: "\(winRate)%")
            if let c = countText { Kpi(label: "시뮬레이션", value: c) }
            if let c = counterPercent { Kpi(label: "카운터 내성", value: "\(c)") }
        }
    }
}

struct Kpi: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            Text(value).font(Theme.display(22)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// 웹 .bars: 평가 항목 막대 (높으면 금색, 낮으면 빨강, 보통은 바이올렛→블루)
struct FactorBars: View {
    let factors: [Factor]
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(factors, id: \.key) { f in FactorBar(factor: f) }
        }
    }
}

struct FactorBar: View {
    let factor: Factor
    private var pct: Int { factor.percent ?? 0 }
    private var v: Double { factor.value ?? 0 }
    private var fill: LinearGradient { v > 0.72 ? Theme.barHigh : (v < 0.4 ? Theme.barLow : Theme.barGradient) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(factor.label).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text("\(pct)").font(Theme.mono(11).weight(.bold)).foregroundStyle(Theme.text)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(fill).frame(width: g.size.width * CGFloat(min(100, max(0, pct))) / 100)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(factor.label) \(pct)")
    }
}

/// 웹 .box: 진한 바탕 + 금색 Black Han Sans 제목
struct InfoBox<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.ko(15)).foregroundStyle(Theme.accent)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.deep, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct BulletList: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("▸").font(Theme.mono(11)).foregroundStyle(Theme.accent)
                    Text(r).font(.footnote).foregroundStyle(Theme.text.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// 엔진이 정한 픽 순서 그대로. 설명 문구는 웹 드래프트 순서 박스와 같다
struct DraftOrderList: View {
    let members: [TeamMember]
    private var ordered: [TeamMember] { members.filter { $0.pick != nil }.sorted { ($0.pick ?? 0) < ($1.pick ?? 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { i, m in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(i + 1)픽").font(Theme.mono(12).weight(.bold)).foregroundStyle(Theme.accent)
                    Text("\(m.ko) — \(note(i))").font(.footnote).foregroundStyle(Theme.text.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func note(_ i: Int) -> String {
        if i == 0 { return "카운터가 적어 블라인드 픽으로 안전" }
        if i == ordered.count - 1 { return "카운터당하기 쉬워 마지막에 상대를 보고 확정" }
        return "중간 픽, 상대 첫 픽에 맞춰 교체 가능"
    }
}

/// 웹 .mini: 둥근 초상화 + 이름 알약
struct ThreatChips: View {
    let threats: [TeamMember]
    let store: SharedStore?
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 6, alignment: .leading)]
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(threats) { t in
                HStack(spacing: 5) {
                    PortraitImage(id: t.id, url: t.img, store: store)
                        .frame(width: 24, height: 24)
                        .background(Color.black, in: Circle()).clipShape(Circle())
                    Text(t.ko).font(.system(size: 12)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.leading, 2).padding(.trailing, 8).padding(.vertical, 2)
                .background(Theme.panel, in: Capsule())
            }
        }
    }
}

/// 픽 순서 태그 (웹 .pk: 모노, 검은 바탕, 희귀도 색 테두리)
struct PickTag: View {
    let pick: Int
    var color: Color = Theme.line
    var body: some View {
        Text("\(pick)픽")
            .font(Theme.mono(10).weight(.bold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(color, lineWidth: 1))
    }
}

/// 초상화 이미지만 (App Group 에 저장된 작은 이미지 → 없으면 네트워크 이미지)
struct PortraitImage: View {
    let id: Int
    let url: String?
    let store: SharedStore?
    var body: some View {
        if let path = store?.portraitURL(brawlerID: id).path, let img = UIImage(contentsOfFile: path) {
            Image(uiImage: img).resizable().scaledToFit()
        } else if let s = url, let u = URL(string: s) {
            AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
        } else {
            Color.clear
        }
    }
}

/// 작은 초상화 타일: 희귀도 색 빛 바탕 + 테두리 (웹 .br 축소판)
struct BrawlerPortrait: View {
    let id: Int
    let url: String?
    let store: SharedStore?
    var rarity: String? = nil
    var radius: CGFloat = 16

    var body: some View {
        let rc = Theme.rarity(rarity)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            Theme.deep
            RadialGradient(colors: [rc.opacity(0.75), .clear], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 30)
            PortraitImage(id: id, url: url, store: store).padding(2)
        }
        .clipShape(shape)
        .overlay(shape.stroke(rc, lineWidth: 1.5))
    }
}

/// 얇은 구분선
struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1) }
}
