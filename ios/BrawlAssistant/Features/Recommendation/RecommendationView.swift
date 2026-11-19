import SwiftUI
import BrawlCore

/// BEST TEAM 카드. 값은 모두 엔진 결과 그대로 (점수·추정 승률·근거·역할·픽 순서·표시 문자열)
/// 디자인: 바탕·라벨은 무채색, 색은 브롤러 아트(순간)와 종합 점수(강조색 하나)에만. 글자는 Dynamic Type 텍스트 스타일
struct RecommendationView: View {
    let recommendation: Recommendation
    let result: EngineResult?
    let store: SharedStore?

    private var many: Bool { recommendation.brawlers.count > 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 맵 · 모드
            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.mapName).font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                Text("\(recommendation.gameMode), \(recommendation.mapNameEn)").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }

            // BEST TEAM: 화면의 '순간' (브롤러 아트가 색을 담당)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("BEST TEAM").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text(recommendation.archetype).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                HStack(alignment: .top, spacing: many ? 4 : 12) {
                    ForEach(recommendation.brawlers) { b in
                        BrawlerCell(member: b, store: store, size: many ? 56 : 88).frame(maxWidth: .infinity)
                    }
                }
            }

            // 점수: 강조색은 종합 점수 하나
            VStack(alignment: .leading, spacing: 8) {
                Hairline()
                HStack(spacing: 0) {
                    Metric(title: "종합 점수", value: "\(recommendation.score)", suffix: "/100", highlight: true)
                    MetricDivider()
                    Metric(title: "추정 승률", value: recommendation.estimatedWinRate, suffix: "%")
                    if let r = result {
                        MetricDivider()
                        Metric(title: "시뮬레이션", value: r.countText, suffix: "조합")
                    }
                }
                .padding(.vertical, 8)
                Hairline()
                Text("종합 점수와 추정 승률은 Draft Room 엔진의 계산값이며 공식 통계가 아닙니다")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }

            // 추천 근거
            VStack(alignment: .leading, spacing: 12) {
                Text("추천 근거").font(.headline).foregroundStyle(Theme.text)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(recommendation.reasons.enumerated()), id: \.offset) { _, r in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").font(.subheadline).foregroundStyle(Theme.secondaryText)
                            Text(r).font(.subheadline).foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            // 다른 순위
            if let r = result, r.teams.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("다른 순위").font(.headline).foregroundStyle(Theme.text)
                    VStack(spacing: 0) {
                        ForEach(r.teams.dropFirst(), id: \.rank) { t in
                            HStack(spacing: 12) {
                                Text("\(t.rank)").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondaryText).frame(width: 20, alignment: .leading)
                                Text(t.members.map(\.ko).joined(separator: ", ")).font(.subheadline).foregroundStyle(Theme.text).lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(t.score)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text)
                            }
                            .frame(minHeight: 44)
                            if t.rank != r.teams.last?.rank { Hairline() }
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
    var size: CGFloat = 88

    var body: some View {
        VStack(spacing: 8) {
            BrawlerPortrait(id: member.id, url: member.img, store: store)
                .frame(width: size, height: size)
                // 고유 디테일: 드래프트 픽 순서 태그 (웹 Draft Room 의 픽 배지)
                .overlay(alignment: .topLeading) {
                    if let p = member.pick { PickTag(pick: p).padding(4) }
                }
            VStack(spacing: 2) {
                Text(member.ko).font(size > 64 ? .subheadline.weight(.semibold) : .footnote.weight(.semibold))
                    .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                if let role = member.role {
                    Text(role).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
                }
                if let e = member.eff, let text = member.effPct {
                    // 표시 문자열은 엔진(웹과 같은 toFixed) 값 그대로
                    Text("실전 \(text)%p").font(.caption.monospacedDigit())
                        .foregroundStyle(e >= 0 ? Theme.positive : Theme.error)
                }
                if member.estimatedProfile { Text("추정 프로필").font(.caption).foregroundStyle(Theme.secondaryText) }
            }
        }
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
            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
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
                Text(value).font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(highlight ? Theme.accent : Theme.text).lineLimit(1).minimumScaleFactor(0.6)
                Text(suffix).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MetricDivider: View {
    var body: some View { Rectangle().fill(Theme.divider).frame(width: 0.5, height: 32) }
}

/// 얇은 구분선 (무채색)
struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.divider).frame(height: 0.5) }
}
