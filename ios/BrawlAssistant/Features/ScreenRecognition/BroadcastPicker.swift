import SwiftUI
import ReplayKit

/// ReplayKit 방송 시트. 화면 방송은 반드시 사용자가 이 시트에서 직접 시작·종료한다.
/// RPSystemBroadcastPickerView 를 보이지 않게 두고, 앱의 버튼이 그 안의 버튼을 눌러 시트를 연다.
/// (내부 버튼을 찾는 방식은 공개 API 만 쓰지만 시스템 구현에 기대므로 기기에서 확인 필요)
final class BroadcastPickerHolder: ObservableObject {
    let picker: RPSystemBroadcastPickerView = {
        let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        v.preferredExtension = AppGroup.broadcastExtensionBundleID
        v.showsMicrophoneButton = false
        return v
    }()

    /// 방송 시트 열기. 방송 중이면 같은 시트에 '방송 중단'이 나온다
    func present() {
        for case let b as UIButton in picker.subviews { b.sendActions(for: .touchUpInside); return }
    }
}

struct BroadcastPickerHost: UIViewRepresentable {
    let holder: BroadcastPickerHolder
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView { holder.picker }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
