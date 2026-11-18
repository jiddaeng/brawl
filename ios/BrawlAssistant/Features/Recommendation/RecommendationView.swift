import SwiftUI
import BrawlCore

/// BEST TEAM 카드. 값은 모두 엔진 결과 그대로 (점수·추정 승률·근거·역할·픽 순서)
struct RecommendationView: View {
    let recommendation: Recommendation
    let result: EngineResult?
    let store: SharedStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.mapName).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                    Text("\(recommendation.gameMode) · \(recommendation.mapNameEn)").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Text(recommendation.archetype).font(.caption).foregroundStyle(Theme.secondaryText)
            }

            Text("BEST TEAM").font(.caption.weight(.heavy)).tracking(2).foregroundStyle(Theme.accent)
            HStack(alignment: .top, spacing: 10) {
                ForEach(recommendation.brawlers) { b in BrawlerCell(member: b, store: store).frame(maxWidth: .infinity) }
            }

            HStack(spacing: 28) {
                Metric(title: "종합 점수", value: "\(recommendation.score)", suffix: "/100", highlight: true)
                Metric(title: "추정 승률", value: recommendation.estimatedWinRate, suffix: "%")
                if let r = result { Metric(title: "시뮬레이션", value: r.countText, suffix: "") }
            }
            Text("종합 점수·추정 승률은 Draft Room 엔진의 계산값이며 공식 통계가 아닙니다.")
                .font(.caption2).foregroundStyle(Theme.secondaryText)

            Divider().overlay(Theme.divider)
            VStack(alignment: .leading, spacing: 8) {
                Text("추천 근거").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                ForEach(Array(recommendation.reasons.enumerated()), id: \.offset) { _, r in
                    Text("· " + r).font(.footnote).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }

            if let r = result, r.teams.count > 1 {
                Divider().overlay(Theme.divider)
                VStack(alignment: .leading, spacing: 10) {
                    Text("다른 순위").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    ForEach(r.teams.dropFirst(), id: \.rank) { t in
                        HStack {
                            Text("#\(t.rank)").font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondaryText).frame(width: 28, alignment: .leading)
                            Text(t.members.map(\.ko).joined(separator: " · ")).font(.footnote).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer()
                            Text("\(t.score)").font(.footnote.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.text)
                        }
                    }
                }
            }
        }
    }
}

struct BrawlerCell: View {
    let member: TeamMember
    let store: SharedStore?

    var body: some View {
        VStack(spacing: 6) {
            BrawlerPortrait(id: member.id, url: member.img, store: store)
                .frame(width: 72, height: 72)
            Text(member.ko).font(.subheadline.weight(.bold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
            if let role = member.role { Text(role).font(.caption2).foregroundStyle(Theme.secondaryText).lineLimit(1).minimumScaleFactor(0.7) }
            HStack(spacing: 4) {
                if let p = member.pick { Text("\(p)픽").font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondaryText) }
                if let e = member.eff, let text = member.effPct {
                    // 표시 문자열은 엔진(웹과 같은 toFixed) 값 그대로
                    Text("\(text)%p").font(.caption2.monospacedDigit()).foregroundStyle(e >= 0 ? Theme.positive : Theme.error)
                }
            }
            if member.estimatedProfile { Text("추정 프로필").font(.caption2).foregroundStyle(Theme.secondaryText) }
        }
    }
}

/// 브롤러 초상화: App Group 에 저장된 작은 이미지 → 없으면 네트워크 이미지
struct BrawlerPortrait: View {
    let id: Int
    let url: String?
    let store: SharedStore?

    var body: some View {
        Group {
            if let path = store?.portraitURL(brawlerID: id).path, let img = UIImage(contentsOfFile: path) {
                Image(uiImage: img).resizable().scaledToFit()
            } else if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { Theme.secondaryBackground }
            } else {
                Theme.secondaryBackground
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct Metric: View {
    let title: String
    let value: String
    let suffix: String
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 28, weight: .bold).monospacedDigit()).foregroundStyle(highlight ? Theme.accent : Theme.text)
                Text(suffix).font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
