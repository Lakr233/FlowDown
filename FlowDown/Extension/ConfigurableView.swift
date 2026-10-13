//
//  ConfigurableView.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/28/25.
//

import ConfigurableKit
import UIKit

class ConfigurableInfoView: ConfigurableView {
    var valueLabel: EasyHitButton {
        contentView as! EasyHitButton
    }

    private var onTapBlock: ((ConfigurableInfoView) -> Void) = { _ in }

    override init() {
        super.init()
        valueLabel.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.titleLabel?.numberOfLines = 3
        valueLabel.titleLabel?.lineBreakMode = .byTruncatingMiddle
        valueLabel.titleLabel?.textAlignment = .right
        valueLabel.contentHorizontalAlignment = .right
        valueLabel.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        valueLabel.snp.makeConstraints { make in
            make.width.lessThanOrEqualTo(self.snp.width).dividedBy(2)
            make.edges.equalToSuperview()
        }
    }

    func configure(value: String, isDestructive: Bool = false) {
        let attrString = NSAttributedString(string: value, attributes: [
            .foregroundColor: isDestructive ? .red : UIColor.accent,
            .font: UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                weight: .semibold,
            ),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        valueLabel.setAttributedTitle(attrString, for: .normal)
    }

    @discardableResult
    func setTapBlock(_ block: @escaping (ConfigurableInfoView) -> Void) -> Self {
        onTapBlock = block
        return self
    }

    @objc private func tapped() {
        onTapBlock(self)
    }

    override class func createContentView() -> UIView {
        EasyHitButton()
    }

    func use(menu: @escaping () -> [UIMenuElement]) {
        valueLabel.removeTarget(self, action: #selector(tapped), for: .touchUpInside)
        valueLabel.showsMenuAsPrimaryAction = true
        valueLabel.menu = .init(children: [
            UIDeferredMenuElement.uncached { completion in completion(menu()) },
        ])
    }
}

class ConfigurableToggleActionView: ConfigurableView {
    var switchView: UISwitch {
        contentView as! UISwitch
    }

    var boolValue: Bool = false {
        didSet {
            guard switchView.isOn != boolValue else { return }
            switchView.setOn(boolValue, animated: false)
        }
    }

    var actionBlock: ((Bool) -> Void) = { _ in }

    override init() {
        super.init()
        switchView.onTintColor = .accent
        switchView.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
    }

    override open class func createContentView() -> UIView {
        UISwitch()
    }

    @objc open func valueChanged() {
        let newValue = switchView.isOn
        guard boolValue != newValue else { return }
        boolValue = newValue
        actionBlock(boolValue)
    }
}
