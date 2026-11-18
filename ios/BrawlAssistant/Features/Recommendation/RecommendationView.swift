import SwiftUI
import BrawlCore

/// BEST TEAM 카드. 값은 모두 엔진 결과 그대로 (점수·추정 승률·근거·역할·픽 순서·표시 문자열)
struct RecommendationView: View {
    let recommendation: Recommendation
    let result: EngineResult?
    let store: SharedStore?

    private var many: Bool { recommendation.brawlers.count > 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 맵 · 모드
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(recommendation.mapName).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text)
                    Text("\(recommendation.gameMode) · \(recommendation.mapNameEn)").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
                Text(recommendation.archetype)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.secondaryBackground, in: Capsule())
            }

            // BEST TEAM
            VStack(alignment: .leading, spacing: 12) {
                Text("BEST TEAM").font(.system(size: 12, weight: .heavy)).tracking(2).foregroundStyle(Theme.accent)
                HStack(alignment: .top, spacing: many ? 6 : 10) {
                    ForEach(recommendation.brawlers) { b in
                        BrawlerCell(member: b, store: store, size: many ? 52 : 80).frame(maxWidth: .infinity)
                    }
                }
            }

            // 점수
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    Metric(title: "종합 점수", value: "\(recommendation.score)", suffix: "/100", highlight: true)
                    MetricDivider()
                    Metric(title: "추정 승률", value: recommendation.estimatedWinRate, suffix: "%")
                    if let r = result {
                        MetricDivider()
                        Metric(title: "시뮬레이션", value: r.countText, suffix: "조합")
                    }
                }
                .padding(.vertical, 12)
                .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("종합 점수·추정 승률은 Draft Room 엔진의 계산값이며 공식 통계가 아닙니다.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }

            // 추천 근거
            VStack(alignment: .leading, spacing: 10) {
                Text("추천 근거").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                ForEach(Array(recommendation.reasons.enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Theme.secondaryText).frame(width: 3, height: 3).offset(y: -3)
                        Text(r).font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                            .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // 다른 순위
            if let r = result, r.teams.count > 1 {
                VStack(alignment: .leading, spacing: 0) {
                    Text("다른 순위").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).padding(.bottom, 8)
                    ForEach(r.teams.dropFirst(), id: \.rank) { t in
                        HStack(spacing: 10) {
                            Text("\(t.rank)").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.secondaryText).frame(width: 18, alignment: .leading)
                            Text(t.members.map(\.ko).joined(separator: " · ")).font(.system(size: 14)).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(t.score)").font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
                        }
                        .frame(height: 40)
                        if t.rank != r.teams.last?.rank { Rectangle().fill(Theme.divider).frame(height: 0.5) }
                    }
                }
            }
        }
    }
}

struct BrawlerCell: View {
    let member: TeamMember
    let store: SharedStore?
    var size: CGFloat = 80

    var body: some View {
        VStack(spacing: 6) {
            BrawlerPortrait(id: member.id, url: member.img, store: store)
                .frame(width: size, height: size)
            Text(member.ko).font(.system(size: size > 60 ? 15 : 13, weight: .bold)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let role = member.role {
                Text(role).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(spacing: 4) {
                if let p = member.pick { Text("\(p)픽").foregroundStyle(Theme.secondaryText) }
                if let e = member.eff, let text = member.effPct {
                    // 표시 문자열은 엔진(웹과 같은 toFixed) 값 그대로
                    Text("\(text)%p").foregroundStyle(e >= 0 ? Theme.positive : Theme.error)
                }
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            if member.estimatedProfile { Text("추정 프로필").font(.system(size: 10)).foregroundStyle(Theme.secondaryText) }
        }
    }
}

/// 브롤러 초상화: App Group 에 저장된 작은 이미지 → 없으면 네트워크 이미지
struct BrawlerPortrait: View {
    let id: Int
    let url: String?
    let store: SharedStore?

    var body: some View {
        ZStack {
            Theme.secondaryBackground
            if let path = store?.portraitURL(brawlerID: id).path, let img = UIImage(contentsOfFile: path) {
                Image(uiImage: img).resizable().scaledToFit().padding(4)
            } else if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { $0.resizable().scaledToFit().padding(4) } placeholder: { Color.clear }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct Metric: View {
    let title: String
    let value: String
    let suffix: String
    var highlight = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(highlight ? Theme.accent : Theme.text).lineLimit(1).minimumScaleFactor(0.6)
                Text(suffix).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondaryText)
            }
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MetricDivider: View {
    var body: some View { Rectangle().fill(Theme.divider).frame(width: 0.5, height: 32) }
}
