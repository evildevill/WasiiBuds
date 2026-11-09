import BudsDomain
import BudsWidgetData
import Foundation
import WidgetKit

@MainActor
enum WidgetStatusPublisher {
    static func publish(battery: BudBattery, mode: ANCMode?, connected: Bool) {
        let previous = WidgetSnapshotStore.load() ?? WidgetSnapshot()
        var snapshot = previous
        snapshot.update(left: battery.left, right: battery.right,
                        caseLevel: battery.caseLevel, mode: mode?.rawValue,
                        connected: connected, at: Date())
        guard snapshot != previous, WidgetSnapshotStore.save(snapshot) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "WasiiBudsStatus")
    }
}
