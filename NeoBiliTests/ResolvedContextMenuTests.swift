import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class ResolvedContextMenuTests: XCTestCase {
    func testConsecutiveMenusUseOnlyTheirCardAndKeepActionsAndPreviewsBound() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }

        let registry = ResolvedMenuRegistry<Int>()
        var performed: [Int] = []
        let menu: (Int) -> UIMenu = { id in
            UIMenu(children: [registry.action("删除", systemImage: "trash", id: id) { performed.append($0) }])
        }
        let host = UIHostingController(rootView: ScrollView {
            VStack(spacing: 12) {
                ForEach(1...2, id: \.self) { id in
                    LibraryVideoCardButton(id: id, registry: registry, isSelecting: true, isSelected: id == 1) {} label: {
                        Text("视频 \(id)").frame(width: 200, height: 64)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                }
            }
            .background { ResolvedMenuInstaller(registry: registry, menu: menu) }
        })
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await TestWindowTransition.wait(for: host)
        try await Task.sleep(for: .milliseconds(100))
        let views = descendants(of: host.view)
        let installer = try XCTUnwrap(views.compactMap { $0 as? ResolvedMenuInstaller<Int>.Host }.first)
        let coordinator = try XCTUnwrap(installer.coordinator)
        let interaction = try XCTUnwrap(views.flatMap(\.interactions).compactMap { $0 as? UIContextMenuInteraction }
            .first { $0.delegate === coordinator })
        let scroll = try XCTUnwrap(interaction.view)
        let cards = views.compactMap { $0 as? ResolvedMenuMarkerView<Int> }
        func cardRect(_ id: Int) throws -> CGRect {
            let card = try XCTUnwrap(cards.first { $0.id == id })
            let rect = card.convert(card.bounds, to: scroll)
            XCTAssertEqual(rect.width, 200, accuracy: 1)
            XCTAssertEqual(rect.height, 64, accuracy: 1)
            return rect
        }
        func configuration(at point: CGPoint) -> UIContextMenuConfiguration? {
            coordinator.contextMenuInteraction(interaction, configurationForMenuAtLocation: point)
        }
        let first = try cardRect(1), second = try cardRect(2)
        let a = try XCTUnwrap(configuration(at: CGPoint(x: first.midX, y: first.midY)))
        XCTAssertNil(configuration(at: CGPoint(x: first.midX, y: (first.maxY + second.minY) / 2)))
        XCTAssertNil(configuration(at: CGPoint(x: first.minX - 10, y: first.midY)), "多选勾选框位于卡面外")
        XCTAssertNil(configuration(at: CGPoint(x: first.minX + 0.2, y: first.minY + 0.2)))
        let b = try XCTUnwrap(configuration(at: CGPoint(x: second.midX, y: second.midY)))
        let bPreview = try XCTUnwrap(coordinator.contextMenuInteraction(interaction, previewForHighlightingMenuWithConfiguration: b))
        let aPreview = try XCTUnwrap(coordinator.contextMenuInteraction(interaction, previewForDismissingMenuWithConfiguration: a))
        XCTAssertEqual(bPreview.target.center.y, second.midY, accuracy: 1)
        XCTAssertEqual(aPreview.target.center.y, first.midY, accuracy: 1)
        XCTAssertEqual(bPreview.size.width, second.width, accuracy: 1)
        XCTAssertEqual(bPreview.size.height, second.height, accuracy: 1)
        XCTAssertEqual(bPreview.parameters.backgroundColor, UIColor.secondarySystemGroupedBackground)
        let path = try XCTUnwrap(bPreview.parameters.visiblePath)
        XCTAssertFalse(path.contains(CGPoint(x: 0.2, y: 0.2)))
        XCTAssertTrue(path.contains(CGPoint(x: 7, y: 1)))
        let aAction = try XCTUnwrap(menu(1).children.first as? UIAction)
        let bAction = try XCTUnwrap(menu(2).children.first as? UIAction)
        for action in [aAction, bAction] {
            UIButton(primaryAction: action).sendActions(for: .primaryActionTriggered)
        }
        XCTAssertEqual(performed, [1, 2])
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants(of:))
    }
}
