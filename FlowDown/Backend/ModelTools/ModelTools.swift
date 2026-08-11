//
//  ModelTools.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/27/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation
import UIKit

class ModelTool: NSObject, @unchecked Sendable {
    var functionName: String {
        guard case let .function(name, _, _, _) = definition else {
            assertionFailure()
            return UUID().uuidString
        }
        return name
    }

    var interfaceName: String {
        fatalError("must be overriden")
    }

    var interfaceIcon: String {
        Self.controlObject.icon
    }

    var definition: ChatRequestBody.Tool {
        fatalError("must be overridden")
    }

    class var controlObject: ConfigurableObject {
        fatalError("must be overridden")
    }

    nonisolated func createConfigurableObjectView() -> UIView {
        MainActor.assumeIsolated {
            Self.controlObject.createView()
        }
    }

    var isEnabled: Bool {
        get { ConfigurableKit.value(forKey: Self.controlObject.key) ?? true }
        set { ConfigurableKit.set(value: newValue, forKey: Self.controlObject.key) }
    }

    nonisolated func execute(with input: String, anchorTo _: UIView) async throws -> String {
        _ = input
        throw NSError()
    }
}
