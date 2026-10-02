//
//  ProgrammingWebSuite.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import ChatClientKit
import Foundation

extension EvaluationManifest.Suite {
    static var programmingWeb: EvaluationManifest.Suite {
        EvaluationManifest.Suite(
            title: "JavaScript/TypeScript Capabilities",
            description: "Tests JS/TS code generation.",
            cases: [
                .init(
                    title: "JS Console Log",
                    content: [
                        .init(type: .request, textRepresentation: "Log 'Hello' to the console in JavaScript."),
                    ],
                    verifier: [.contains(pattern: "console.log(\"Hello\")")],
                ),
                .init(
                    title: "JS Arrow Function",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Write an arrow function 'add' in JS that adds two numbers, 'a' and 'b'."
                        ),
                    ],
                    verifier: [.contains(pattern: "const add = (a, b) =>")],
                ),
                .init(
                    title: "TS User Interface",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a TypeScript interface 'User' with name (string)."
                        ),
                    ],
                    verifier: [.contains(pattern: "interface User"), .contains(pattern: "name: string")],
                ),
                .init(
                    title: "JS Car Class",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a class 'Car' with a constructor in JavaScript."
                        ),
                    ],
                    verifier: [.contains(pattern: "class Car"), .contains(pattern: "constructor(")],
                ),
                .init(
                    title: "JS Promise",
                    content: [
                        .init(type: .request, textRepresentation: "Create a Promise that resolves to 'Success' in JS."),
                    ],
                    verifier: [.contains(pattern: "new Promise"), .contains(pattern: "resolve('Success')")],
                ),
                .init(
                    title: "JS Async Function",
                    content: [
                        .init(type: .request, textRepresentation: "Write an async function 'fetchData' in JS."),
                    ],
                    verifier: [.contains(pattern: "async function fetchData")],
                ),
                .init(
                    title: "JS Map",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Use map to double values in array 'arr' in JS. Use 'n' as the argument."
                        ),
                    ],
                    verifier: [.contains(pattern: "arr.map")],
                ),
                .init(
                    title: "JS Filter Even",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Filter even numbers from array 'arr' in JS. Use 'n' as the argument name and use strict equality."
                        ),
                    ],
                    // 放松对 n 括号的检查，同时检查严格相等
                    verifier: [.contains(pattern: "arr.filter"), .contains(pattern: "n % 2 === 0")],
                ),
                .init(
                    title: "JS Reduce Sum",
                    content: [
                        .init(type: .request, textRepresentation: "Use reduce to sum an array 'arr' in JS."),
                    ],
                    verifier: [.contains(pattern: "arr.reduce")],
                ),
                .init(
                    title: "JS Destructuring",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Destructure 'name' property from object 'user' in JS using const."
                        ),
                    ],
                    verifier: [.contains(pattern: "const { name } = user")],
                ),
                .init(
                    title: "JS Spread Arrays",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Use spread operator to combine two arrays 'arr1' and 'arr2' in JS inside a new array."
                        ),
                    ],
                    verifier: [.contains(pattern: "[...arr1, ...arr2]")],
                ),
                .init(
                    title: "JS Import React",
                    content: [
                        .init(type: .request, textRepresentation: "Import 'React' from 'react' in JS."),
                    ],
                    verifier: [.contains(pattern: "import React from 'react'")],
                ),
                .init(
                    title: "JS Select Item",
                    content: [
                        .init(type: .request, textRepresentation: "Select an element with id 'app' in JS."),
                    ],
                    verifier: [.contains(pattern: "document.getElementById('app')")],
                ),
                .init(
                    title: "JS Event Listener",
                    content: [
                        .init(type: .request, textRepresentation: "Add a click event listener to button 'btn' in JS."),
                    ],
                    verifier: [.contains(pattern: "btn.addEventListener('click',")],
                ),
                .init(
                    title: "JS Fetch API",
                    content: [
                        .init(type: .request, textRepresentation: "Use fetch API to get data from '/api' in JS."),
                    ],
                    verifier: [.contains(pattern: "fetch('/api')")],
                ),
                .init(
                    title: "JS JSON Parse",
                    content: [
                        .init(type: .request, textRepresentation: "Parse a JSON string 'str' in JS."),
                    ],
                    verifier: [.contains(pattern: "JSON.parse(str)")],
                ),
                .init(
                    title: "React Component App",
                    content: [
                        .init(type: .request, textRepresentation: "Create a functional React component named 'App'."),
                    ],
                    verifier: [.contains(pattern: "function App()"), .contains(pattern: "return")],
                ),
                .init(
                    title: "React useState",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Use useState hook for a counter in React. Use 'count' and 'setCount' initialized to 0."
                        ),
                    ],
                    verifier: [.contains(pattern: "const [count, setCount] = useState(0)")],
                ),
                .init(
                    title: "TS Type Alias",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a type alias 'ID' as string or number in TS."
                        ),
                    ],
                    verifier: [.contains(pattern: "type ID = string | number")],
                ),
                .init(
                    title: "TS Generic Identity",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Create a generic function 'identity' in TS that takes 'arg' of type 'T'."
                        ),
                    ],
                    verifier: [.contains(pattern: "function identity<T>(arg: T): T")],
                ),
            ],
        )
    }
}
