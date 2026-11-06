@testable import CmuxSwiftRenderUI
import CoreGraphics
import Testing

@MainActor
struct SceneRowFrameReporterTests {
    private func meta(_ key: String, inset: CGFloat = 0) -> SceneRowFrameReporter.RowMeta {
        SceneRowFrameReporter.RowMeta(key: key, leadingInset: inset, cornerRadius: 6)
    }

    @Test func hitTestsReportedRowsByKey() {
        let reporter = SceneRowFrameReporter()
        reporter.recordFrame(nodeId: "n1", slot: CGRect(x: 0, y: 0, width: 200, height: 30), meta: meta("h:g"))
        reporter.recordFrame(nodeId: "n2", slot: CGRect(x: 0, y: 30, width: 200, height: 30), meta: meta("ws"))
        #expect(reporter.row(at: CGPoint(x: 50, y: 10))?.key == "h:g")
        #expect(reporter.row(at: CGPoint(x: 50, y: 45))?.key == "ws")
        #expect(reporter.row(at: CGPoint(x: 50, y: 75)) == nil)
    }

    @Test func leadingInsetNarrowsTheVisualBox() {
        let reporter = SceneRowFrameReporter()
        reporter.recordFrame(nodeId: "n", slot: CGRect(x: 0, y: 0, width: 200, height: 30), meta: meta("ws", inset: 16))
        #expect(reporter.row(at: CGPoint(x: 8, y: 10)) == nil)
        #expect(reporter.row(at: CGPoint(x: 20, y: 10))?.frame == CGRect(x: 16, y: 0, width: 184, height: 30))
    }

    @Test func metaUpdateAndRemoval() {
        let reporter = SceneRowFrameReporter()
        reporter.recordFrame(nodeId: "n", slot: CGRect(x: 0, y: 0, width: 100, height: 20), meta: meta("a"))
        reporter.updateMeta(nodeId: "n", meta: meta("a:edit"))
        #expect(reporter.rows.map(\.key) == ["a:edit"])
        reporter.remove(nodeId: "n")
        #expect(reporter.rows.isEmpty)
    }
}
