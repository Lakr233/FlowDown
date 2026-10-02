//
//  ProgrammingRustSuite.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import ChatClientKit
import Foundation

extension EvaluationManifest.Suite {
    static var programmingRust: EvaluationManifest.Suite {
        EvaluationManifest.Suite(
            title: "Rust Capabilities",
            description: "Tests Rust code generation.",
            cases: [
                .init(
                    title: "Rust Print",
                    content: [
                        .init(type: .request, textRepresentation: "Print 'Hello' to stdout in Rust."),
                    ],
                    verifier: [.contains(pattern: "println!(\"Hello\")")],
                ),
                .init(
                    title: "Rust Main Function",
                    content: [
                        .init(type: .request, textRepresentation: "Write the main function in Rust."),
                    ],
                    verifier: [.contains(pattern: "fn main()")],
                ),
                .init(
                    title: "Rust Point Struct",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a struct 'Point' with x and y fields of type i32 in Rust."
                        ),
                    ],
                    verifier: [
                        .contains(pattern: "struct Point"),
                        .contains(pattern: "x: i32"),
                        .contains(pattern: "y: i32")
                    ],
                ),
                .init(
                    title: "Rust Impl Point",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Implement a method 'new' for struct 'Point' in Rust."
                        ),
                    ],
                    verifier: [.contains(pattern: "impl Point"), .contains(pattern: "fn new(")],
                ),
                .init(
                    title: "Rust Option",
                    content: [
                        .init(type: .request, textRepresentation: "Use Option enum to handle nullable value in Rust."),
                    ],
                    verifier: [.contains(pattern: "Option<T>"), .contains(pattern: "Some(")],
                ),
                .init(
                    title: "Rust Match Option",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Use match expression on an Option in Rust. Use 'x' inside Some."
                        ),
                    ],
                    verifier: [.contains(pattern: "match option"), .contains(pattern: "Some(x) =>")],
                ),
                .init(
                    title: "Rust For Loop",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Loop 5 times using for loop in Rust. Use 'i' as loop variable and range 0..5."
                        ),
                    ],
                    verifier: [.contains(pattern: "for i in 0..5")],
                ),
                .init(
                    title: "Rust Vector New",
                    content: [
                        .init(type: .request, textRepresentation: "reate a new vector of integers in Rust."),
                    ],
                    verifier: [.contains(pattern: "Vec::new()")],
                ),
                .init(
                    title: "Rust String From",
                    content: [
                        .init(type: .request, textRepresentation: "Create a String from the literal \"text\" in Rust."),
                    ],
                    verifier: [.contains(pattern: "String::from(\"text\")")],
                ),
                .init(
                    title: "Rust Result",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Return a Result with unit success type and String error type in Rust."
                        ),
                    ],
                    verifier: [.contains(pattern: "-> Result<(), String>")],
                ),
                .init(
                    title: "Rust Trait Summary",
                    content: [
                        .init(type: .request, textRepresentation: "Define a trait 'Summary' in Rust."),
                    ],
                    verifier: [.contains(pattern: "trait Summary"), .contains(pattern: "fn summarize")],
                ),
                .init(
                    title: "Rust Generic Largest",
                    content: [
                        .init(type: .request, textRepresentation: "Write a generic function 'largest' in Rust."),
                    ],
                    verifier: [.contains(pattern: "fn largest<T>")],
                ),
                .init(
                    title: "Rust Lifetime",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Annotate lifetimes 'a for a struct 'Reference' in Rust."
                        ),
                    ],
                    verifier: [.contains(pattern: "struct Reference<'a>")],
                ),
                .init(
                    title: "Rust Thread Spawn",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Spawn a new thread in Rust using fully qualified std::thread::spawn."
                        ),
                    ],
                    verifier: [.contains(pattern: "std::thread::spawn")],
                ),
                .init(
                    title: "Rust Mutex",
                    content: [
                        .init(type: .request, textRepresentation: "Use a Mutex to protect data in Rust."),
                    ],
                    verifier: [.contains(pattern: "Mutex::new")],
                ),
                .init(
                    title: "Rust Async Fn",
                    content: [
                        .init(type: .request, textRepresentation: "Write an async function in Rust."),
                    ],
                    verifier: [.contains(pattern: "async fn")],
                ),
                .init(
                    title: "Rust Vec Macro",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Use vec! macro to create a vector with values 1, 2, 3 in Rust."
                        ),
                    ],
                    verifier: [.contains(pattern: "vec![1, 2, 3]")],
                ),
                .init(
                    title: "Rust String Slice",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Use a range 0..5 to slice a string variable 's' in Rust."
                        ),
                    ],
                    verifier: [.contains(pattern: "&s[0..5]")],
                ),
                .init(
                    title: "Rust HashMap",
                    content: [
                        .init(type: .request, textRepresentation: "Create a HashMap in Rust."),
                    ],
                    verifier: [.contains(pattern: "HashMap::new()")],
                ),
                .init(
                    title: "Rust Derive",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Derive Debug and Clone for a struct in Rust. Order: Debug, Clone."
                        ),
                    ],
                    verifier: [.contains(pattern: "#[derive(Debug, Clone)]")],
                ),
            ],
        )
    }
}
