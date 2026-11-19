import Foundation
import BrawlCore

/// 메인 화면에 보여 줄 값. 상태 규칙은 BrawlCore.HomePresentation (테스트됨)
@MainActor
struct HomeViewModel {
    let app: AppState

    var presentation: HomePresentation { app.presentation }
    var result: EngineResult? { presentation.recommendation == nil ? nil : app.displayedResult }

    var dataLine: String {
        guard let c = app.catalog else { return "맵 데이터 없음" }
        var parts = ["\(c.hasLive ? "현재 맵 풀" : "활성 맵") \(c.maps.count)", "브롤러 \(c.brawlers.count)"]
        if let w = c.window { parts.append("실전 데이터 \(w)") }
        return parts.joined(separator: " · ")
    }

    var dataStatusLine: String? {
        switch app.dataStatus {
        case .idle: return nil
        case .loading: return "데이터 불러오는 중…"
        case .ready(let d): return "동기화 \(d.formatted(date: .omitted, time: .shortened))"
        case .offline(let d): return "API 응답 없음 · 저장본 사용 (\(d.formatted(date: .abbreviated, time: .shortened)))"
        case .failed(let m): return m
        }
    }

    var precomputeLine: String? {
        guard app.precomputeTotal > 0, app.precomputed < app.precomputeTotal else { return nil }
        return "추천 미리 계산 \(app.precomputed)/\(app.precomputeTotal) · 계산된 맵은 바로 인식됩니다"
    }

    /// 기기 검증용: 방송 확장이 Dynamic Island 를 직접 갱신했는지
    var extensionActivityLine: String? {
        guard let u = app.store?.read(ExtensionActivityUpdate.self, .extensionActivity) else {
            return AppGroup.pushRelayURL == nil ? "게임 중 Dynamic Island 갱신에는 푸시 중계 서버 설정이 필요합니다 (ios/README.md)" : nil
        }
        let time = u.at.formatted(date: .omitted, time: .standard)
        if u.succeeded {
            return u.path == .relay ? "Dynamic Island: 푸시 중계로 갱신 요청 성공 (\(time))" : "Dynamic Island: 방송 확장이 직접 갱신 (\(time))"
        }
        return "Dynamic Island: 게임 중 갱신 실패, 앱이 열릴 때 갱신 (\(u.error ?? "")) (\(time))"
    }

    var isFirstRun: Bool { !UserDefaults.standard.bool(forKey: "onboarding.done") }
}
