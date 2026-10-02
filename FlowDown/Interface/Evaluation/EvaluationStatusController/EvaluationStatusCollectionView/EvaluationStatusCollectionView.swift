//
//  EvaluationStatusCollectionView.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import SnapKit
import UIKit

final class EvaluationStatusCollectionView: UIView {
    enum Section: Hashable {
        case suite(UUID)
    }

    struct Item: Hashable {
        let suiteID: UUID
        let caseID: UUID
    }

    let session: EvaluationSession

    private var outcomeFilter: EvaluationManifest.Suite.Case.Result.Outcome?

    var onSelectCase: ((EvaluationManifest.Suite.Case) -> Void)?

    static let suiteHeaderReuseIdentifier = "EvaluationSuiteHeaderView"

    lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        cv.backgroundColor = .clear
        cv.delegate = self
        cv.register(
            EvaluationSuiteHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: Self.suiteHeaderReuseIdentifier,
        )
        return cv
    }()

    lazy var dataSource: UICollectionViewDiffableDataSource<Section, Item> = createDataSource()

    private struct CaseDiffState: Equatable {
        let title: String
        let outcome: EvaluationManifest.Suite.Case.Result.Outcome
    }

    private struct SuiteHeaderDiffState: Equatable {
        let title: String
        let total: Int
        let completed: Int
        let passed: Int
        let failed: Int
        let awaitingJudging: Int
    }

    private var lastCaseStates: [UUID: CaseDiffState] = [:]
    private var lastSuiteHeaderStates: [UUID: SuiteHeaderDiffState] = [:]

    private struct SnapshotBuild {
        let snapshot: NSDiffableDataSourceSnapshot<Section, Item>
        let caseStates: [UUID: CaseDiffState]
        let suiteHeaderStates: [UUID: SuiteHeaderDiffState]
        let changedSections: [Section]
    }

    private struct PendingApply {
        var animated: Bool
        var build: SnapshotBuild
    }

    private var isApplyingSnapshot = false
    private var pendingApply: PendingApply?

    override var intrinsicContentSize: CGSize {
        .zero
    }

    init(session: EvaluationSession) {
        self.session = session
        super.init(frame: .zero)

        setupView()
        configureRegistrations()
        applySessionUpdate(animated: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func configureRegistrations() {
        collectionView.register(EvaluationStatusCell.self, forCellWithReuseIdentifier: "EvaluationStatusCell")
    }

    func applySessionUpdate(animated: Bool) {
        requestApplySnapshot(animated: animated)
    }

    func setOutcomeFilter(_ filter: EvaluationManifest.Suite.Case.Result.Outcome?) {
        outcomeFilter = filter
        applySessionUpdate(animated: false)
    }

    private func requestApplySnapshot(animated: Bool) {
        if Thread.isMainThread {
            enqueueApplySnapshot(animated: animated)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.enqueueApplySnapshot(animated: animated)
            }
        }
    }

    private func enqueueApplySnapshot(animated: Bool) {
        let build = buildSnapshot()

        if isApplyingSnapshot {
            if var pending = pendingApply {
                pending.animated = pending.animated || animated
                pending.build = build
                pendingApply = pending
            } else {
                pendingApply = .init(animated: animated, build: build)
            }
            return
        }

        apply(build: build, animated: animated)
    }

    private func apply(build: SnapshotBuild, animated: Bool) {
        isApplyingSnapshot = true

        dataSource.apply(build.snapshot, animatingDifferences: animated) { [weak self] in
            guard let self else { return }

            lastCaseStates = build.caseStates
            lastSuiteHeaderStates = build.suiteHeaderStates

            if !build.changedSections.isEmpty {
                updateVisibleHeaders(for: build.changedSections)
            }

            isApplyingSnapshot = false
            if let pending = pendingApply {
                pendingApply = nil
                apply(build: pending.build, animated: pending.animated)
            }
        }
    }

    private func buildSnapshot() -> SnapshotBuild {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()

        var newCaseStates: [UUID: CaseDiffState] = [:]
        var newSuiteHeaderStates: [UUID: SuiteHeaderDiffState] = [:]

        var changedItems: [Item] = []
        var changedSections: [Section] = []

        for manifest in session.manifests {
            for suite in manifest.suites {
                let section: Section = .suite(suite.id)

                let title = String(localized: suite.title)
                let total = suite.cases.count
                let completed = suite.cases.count(where: { caseItem in
                    guard let outcome = caseItem.results.last?.outcome else { return false }
                    return outcome != .notDetermined && outcome != .processing
                })
                let passed = suite.cases.count(where: { $0.results.last?.outcome == .pass })
                let failed = suite.cases.count(where: { $0.results.last?.outcome == .fail })
                let awaitingJudging = suite.cases.count(where: { $0.results.last?.outcome == .awaitingJudging })

                var items: [Item] = []
                items.reserveCapacity(suite.cases.count)
                for caseItem in suite.cases {
                    let outcome = caseItem.results.last?.outcome ?? .notDetermined
                    if let filter = outcomeFilter, outcome != filter { continue }

                    let state = CaseDiffState(title: caseItem.title, outcome: outcome)
                    newCaseStates[caseItem.id] = state

                    let item = Item(suiteID: suite.id, caseID: caseItem.id)
                    if let oldState = lastCaseStates[caseItem.id], oldState != state {
                        changedItems.append(item)
                    }
                    items.append(item)
                }

                guard !items.isEmpty else { continue }

                let suiteHeaderState = SuiteHeaderDiffState(
                    title: title,
                    total: total,
                    completed: completed,
                    passed: passed,
                    failed: failed,
                    awaitingJudging: awaitingJudging,
                )
                newSuiteHeaderStates[suite.id] = suiteHeaderState
                if let oldSuiteHeaderState = lastSuiteHeaderStates[suite.id], oldSuiteHeaderState != suiteHeaderState {
                    changedSections.append(section)
                }

                snapshot.appendSections([section])
                snapshot.appendItems(items, toSection: section)
            }
        }

        if !changedItems.isEmpty {
            snapshot.reconfigureItems(changedItems)
        }

        return .init(
            snapshot: snapshot,
            caseStates: newCaseStates,
            suiteHeaderStates: newSuiteHeaderStates,
            changedSections: changedSections,
        )
    }

    private func updateVisibleHeaders(for changedSections: [Section]) {
        let sectionIDs = Set(changedSections)
        let sectionIdentifiers = dataSource.snapshot().sectionIdentifiers

        UIView.performWithoutAnimation {
            for (index, section) in sectionIdentifiers.enumerated() where sectionIDs.contains(section) {
                let indexPath = IndexPath(item: 0, section: index)
                guard let suite = suite(for: section) else { continue }
                guard let view = collectionView.supplementaryView(
                    forElementKind: UICollectionView.elementKindSectionHeader,
                    at: indexPath,
                ) as? EvaluationSuiteHeaderView else {
                    continue
                }

                let completed = suite.cases.count(where: { caseItem in
                    guard let outcome = caseItem.results.last?.outcome else { return false }
                    return outcome != .notDetermined && outcome != .processing
                })
                let passed = suite.cases.count(where: { $0.results.last?.outcome == .pass })
                let failed = suite.cases.count(where: { $0.results.last?.outcome == .fail })
                let awaitingJudging = suite.cases.count(where: { $0.results.last?.outcome == .awaitingJudging })

                view.configure(
                    title: String(localized: suite.title),
                    total: suite.cases.count,
                    completed: completed,
                    passed: passed,
                    failed: failed,
                    awaitingJudging: awaitingJudging,
                )
                view.layoutIfNeeded()
            }
        }
    }

    func suite(for section: Section) -> EvaluationManifest.Suite? {
        guard case let .suite(suiteID) = section else { return nil }
        return suite(forSuiteID: suiteID)
    }

    private func suite(forSuiteID suiteID: UUID) -> EvaluationManifest.Suite? {
        for manifest in session.manifests {
            if let suite = manifest.suites.first(where: { $0.id == suiteID }) {
                return suite
            }
        }
        return nil
    }

    func caseItem(for item: Item) -> EvaluationManifest.Suite.Case? {
        for manifest in session.manifests {
            for suite in manifest.suites where suite.id == item.suiteID {
                return suite.cases.first(where: { $0.id == item.caseID })
            }
        }
        return nil
    }
}
