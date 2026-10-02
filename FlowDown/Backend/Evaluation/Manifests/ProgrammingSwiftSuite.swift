//
//  ProgrammingSwiftSuite.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import ChatClientKit
import Foundation

extension EvaluationManifest.Suite {
    static var programmingSwift: EvaluationManifest.Suite {
        EvaluationManifest.Suite(
            title: "Swift Capabilities",
            description: "Tests Swift code generation.",
            cases: [
                .init(
                    title: "Swift Print",
                    content: [
                        .init(type: .request, textRepresentation: "Print 'Hello World' in Swift."),
                    ],
                    verifier: [.contains(pattern: "print(\"Hello World\")")],
                ),
                .init(
                    title: "Swift Add Function",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a Swift function 'add' taking two Ints 'a' and 'b' and returning an Int."
                        ),
                    ],
                    verifier: [.contains(pattern: "func add(a: Int, b: Int) -> Int")],
                ),
                .init(
                    title: "Swift User Struct",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a Swift struct 'User' with a 'name' constant property."
                        ),
                    ],
                    verifier: [.contains(pattern: "struct User"), .contains(pattern: "let name: String")],
                ),
                .init(
                    title: "Swift Manager Class",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a Swift class 'Manager' that inherits from 'Employee'."
                        ),
                    ],
                    verifier: [.contains(pattern: "class Manager: Employee")],
                ),
                .init(
                    title: "Swift Protocol Playable",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a protocol 'Playable' with a 'play' function in Swift."
                        ),
                    ],
                    verifier: [.contains(pattern: "protocol Playable"), .contains(pattern: "func play()")],
                ),
                .init(
                    title: "Swift String Extension",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Extend String in Swift to add a 'length' property counting characters."
                        ),
                    ],
                    verifier: [.contains(pattern: "extension String"), .contains(pattern: "var length: Int")],
                ),
                .init(
                    title: "Swift Guard",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Use guard to check if 'x' is greater than 0 in Swift."
                        ),
                    ],
                    verifier: [.contains(pattern: "guard x > 0 else")],
                ),
                .init(
                    title: "Swift If Let",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Safely unwrap optional 'name' into variable 'name' using if let in Swift."
                        ),
                    ],
                    verifier: [.contains(pattern: "if let name = name")],
                ),
                .init(
                    title: "Swift Enum Direction",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define an enum 'Direction' with cases north and south in Swift."
                        ),
                    ],
                    verifier: [.contains(pattern: "enum Direction"), .contains(pattern: "case north")],
                ),
                .init(
                    title: "Swift @State",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Use @State property wrapper for a variable 'count' in Swift."
                        ),
                    ],
                    // 拆分以允许多种写法 (e.g. @State private var)
                    verifier: [.contains(pattern: "@State"), .contains(pattern: "var count")],
                ),
                .init(
                    title: "SwiftUI View",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Create a basic SwiftUI view 'ContentView' with Text."
                        ),
                    ],
                    verifier: [.contains(pattern: "struct ContentView: View"), .contains(pattern: "Text(")],
                ),
                .init(
                    title: "Swift Combine Subject",
                    content: [
                        .init(type: .request, textRepresentation: "Create a PassthroughSubject in Swift Combine."),
                    ],
                    verifier: [.contains(pattern: "PassthroughSubject<")],
                ),
                .init(
                    title: "Swift Result Type",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Return a Result type with String success and Error failure in Swift."
                        ),
                    ],
                    verifier: [.contains(pattern: "-> Result<String, Error>")],
                ),
                .init(
                    title: "Swift Do-Catch",
                    content: [
                        .init(type: .request, textRepresentation: "Use do-catch block to handle errors in Swift."),
                    ],
                    verifier: [.contains(pattern: "do {"), .contains(pattern: "catch")],
                ),
                .init(
                    title: "Swift Trailing Closure",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Call a function 'perform' with a trailing closure in Swift."
                        ),
                    ],
                    verifier: [.contains(pattern: "perform {")],
                ),
                .init(
                    title: "Swift Computed Property",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a computed property 'area' of type Double for a Rectangle struct in Swift."
                        ),
                    ],
                    verifier: [.contains(pattern: "var area: Double {")],
                ),
                .init(
                    title: "Swift Custom Init",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Write a custom initializer for class 'Car' in Swift."
                        ),
                    ],
                    verifier: [.contains(pattern: "init(")],
                ),
                .init(
                    title: "Swift Static Constant",
                    content: [
                        .init(type: .request, textRepresentation: "Define a static constant 'id' in Swift struct."),
                    ],
                    verifier: [.contains(pattern: "static let id")],
                ),
                .init(
                    title: "Swift Async Await",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Call an async function 'fetch()' using await in Swift."
                        ),
                    ],
                    verifier: [.contains(pattern: "await fetch()")],
                ),
                .init(
                    title: "Swift Actor Account",
                    content: [
                        .init(type: .request, textRepresentation: "Define an actor 'Account' in Swift."),
                    ],
                    verifier: [.contains(pattern: "actor Account")],
                ),
            ],
        )
    }
}
