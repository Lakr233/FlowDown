//
//  HubModelDownloadProgressController.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import Combine
import UIKit

class HubModelDownloadProgressController: UIViewController {
    let model: HubModelDownloadController.RemoteModel
    private let progress = ModelManager.HubDownloadProgress()
    private var modelIsDownloaded = false
    private var task: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var onDismiss: () -> Void = {}

    // MARK: - UI Components

    private let containerStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 32
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 32
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let bottomStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 32
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let statusImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let progressContentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let progressHeaderStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let percentageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let speedLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17)
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let progressBarContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGray
        view.layer.cornerRadius = 2
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let progressBarFill: UIView = {
        let view = UIView()
        view.backgroundColor = .tintColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var progressBarFillWidthConstraint: NSLayoutConstraint?

    private let currentFileLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let keepRunningLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17)
        label.text = String(localized: "Download in progress, please keep app running in foreground.")
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let errorTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 17)
        label.textColor = .systemRed
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let errorMessageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17)
        label.textColor = .systemRed
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let completeTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 17)
        label.text = String(localized: "Model Download Complete")
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let oversizeWarningLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17)
        label.textColor = .systemRed
        label.text = String(localized: "This model is likely too large to fit in the available memory.")
        label.numberOfLines = 0
        label.textAlignment = .center
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        // Add underline
        let attributedString = NSMutableAttributedString(string: label.text ?? "")
        attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attributedString.length))
        label.attributedText = attributedString

        return label
    }()

    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(String(localized: "Cancel"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(String(localized: "Close"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let modelIdLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Initialization

    init(model: HubModelDownloadController.RemoteModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Downloading Model")
        modalTransitionStyle = .coverVertical
        modalPresentationStyle = .formSheet
        isModalInPresentation = true
        preferredContentSize = .init(width: 500, height: 500)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        setupUI()
        setupBindings()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task.detached { [weak self] in
            await self?.execute()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            onDismiss()
            onDismiss = {}
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        progress.onInterfaceDisappear()
        task?.cancel()
        task = nil
    }

    // MARK: - Setup

    private func setupUI() {
        // Setup progress bar
        progressBarContainer.addSubview(progressBarFill)
        progressBarFillWidthConstraint = progressBarFill.widthAnchor.constraint(equalTo: progressBarContainer.widthAnchor, multiplier: 0)

        progressBarFill.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
        }
        progressBarFillWidthConstraint?.isActive = true

        progressBarContainer.snp.makeConstraints { make in
            make.height.equalTo(4)
        }

        statusImageView.snp.makeConstraints { make in
            make.width.height.equalTo(48)
        }

        // Setup progress header
        progressHeaderStackView.addArrangedSubview(percentageLabel)
        progressHeaderStackView.addArrangedSubview(speedLabel)

        // Setup progress content
        progressContentStackView.addArrangedSubview(progressHeaderStackView)
        progressContentStackView.addArrangedSubview(progressBarContainer)
        progressContentStackView.addArrangedSubview(currentFileLabel)
        progressContentStackView.addArrangedSubview(keepRunningLabel)

        bottomStackView.addArrangedSubview(cancelButton)
        bottomStackView.addArrangedSubview(modelIdLabel)

        view.addSubview(containerStackView)
        view.addSubview(bottomStackView)
        view.addSubview(oversizeWarningLabel)

        containerStackView.snp.makeConstraints { make in
            make.centerX.centerY.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(32)
        }

        bottomStackView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(32)
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-32)
        }

        oversizeWarningLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(32)
            make.bottom.equalTo(bottomStackView.snp.top).offset(-16)
        }

        modelIdLabel.text = model.id

        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        updateContent()
    }

    private func setupBindings() {
        // Observe progress changes
        progress.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateProgress()
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        progress.isCancelled = true
        dismiss(animated: true)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - Update UI

    private func updateContent() {
        // Clear content stack
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if let errorText = progress.error?.localizedDescription {
            // Error state
            let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
            let imageName = modelIsDownloaded ? "checkmark.circle.badge.xmark" : "xmark.circle.fill"
            statusImageView.image = UIImage(systemName: imageName, withConfiguration: config)
            statusImageView.tintColor = .systemRed

            contentStackView.addArrangedSubview(statusImageView)

            if modelIsDownloaded {
                // Create a nested stack for the error titles with spacing 8
                let errorTitlesStack = UIStackView()
                errorTitlesStack.axis = .vertical
                errorTitlesStack.spacing = 8
                errorTitlesStack.alignment = .center

                errorTitleLabel.text = String(localized: "Model is downloaded, but there seems to be a problem loading it.")
                errorTitlesStack.addArrangedSubview(errorTitleLabel)

                let subtitleLabel = UILabel()
                subtitleLabel.font = .boldSystemFont(ofSize: 17)
                subtitleLabel.textColor = .systemRed
                subtitleLabel.text = String(localized: "Either model is corrupted or not supported.")
                subtitleLabel.numberOfLines = 0
                subtitleLabel.textAlignment = .center
                errorTitlesStack.addArrangedSubview(subtitleLabel)

                contentStackView.addArrangedSubview(errorTitlesStack)
            }

            errorMessageLabel.text = errorText
            errorMessageLabel.font = modelIsDownloaded ? .systemFont(ofSize: 13) : .systemFont(ofSize: 17)
            contentStackView.addArrangedSubview(errorMessageLabel)
            contentStackView.addArrangedSubview(closeButton)

            activityIndicator.stopAnimating()
            cancelButton.isHidden = true

        } else if modelIsDownloaded {
            // Complete state
            let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
            statusImageView.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)
            statusImageView.tintColor = .systemGreen

            contentStackView.addArrangedSubview(statusImageView)
            contentStackView.addArrangedSubview(completeTitleLabel)
            contentStackView.addArrangedSubview(closeButton)

            activityIndicator.stopAnimating()
            cancelButton.isHidden = true

        } else {
            // Progress state
            activityIndicator.startAnimating()
            contentStackView.addArrangedSubview(activityIndicator)
            contentStackView.addArrangedSubview(progressContentStackView)

            cancelButton.isHidden = false
            cancelButton.isEnabled = progress.cancellable
            cancelButton.alpha = progress.cancellable ? 1 : 0
        }

        containerStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        containerStackView.addArrangedSubview(contentStackView)

        updateOversizeWarning()
    }

    private func updateProgress() {
        let percentage = Int(progress.overall.fractionCompleted * 100)
        percentageLabel.text = "\(percentage)% " + String(localized: "Finished")
        speedLabel.text = progress.speed

        progressBarFillWidthConstraint?.isActive = false
        progressBarFillWidthConstraint = progressBarFill.widthAnchor.constraint(
            equalTo: progressBarContainer.widthAnchor,
            multiplier: progress.overall.fractionCompleted
        )
        progressBarFillWidthConstraint?.isActive = true

        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }

        currentFileLabel.text = String(
            format: String(localized: "Process %@..."),
            progress.currentFilename
        )

        cancelButton.isEnabled = progress.cancellable
        UIView.animate(withDuration: 0.2) {
            self.cancelButton.alpha = self.progress.cancellable ? 1 : 0
        }

        updateOversizeWarning()
    }

    private func updateOversizeWarning() {
        let ramSize = Double(ProcessInfo.processInfo.physicalMemory)
        let totalSize = Double(progress.overall.totalUnitCount)
        let isOversize = totalSize > ramSize * 0.8

        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [.curveEaseInOut]) {
            self.oversizeWarningLabel.alpha = isOversize ? 1 : 0
        }
    }

    // MARK: - Download Execution

    private func execute() async {
        do {
            try await ModelManager.shared.downloadModelFromHuggingFace(
                identifier: model.id,
                populateProgressTo: progress
            )
            await MainActor.run {
                UIView.animate(withDuration: 0.3) {
                    self.modelIsDownloaded = true
                    self.progress.cancellable = false
                    self.updateContent()
                }
            }
        } catch {
            await MainActor.run {
                UIView.animate(withDuration: 0.3) {
                    self.progress.error = error
                    self.progress.cancellable = false
                    self.updateContent()
                }
            }
        }
    }
}
