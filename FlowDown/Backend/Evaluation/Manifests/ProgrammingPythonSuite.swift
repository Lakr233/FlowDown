//
//  ProgrammingPythonSuite.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import ChatClientKit
import Foundation

extension EvaluationManifest.Suite {
    static var programmingPython: EvaluationManifest.Suite {
        EvaluationManifest.Suite(
            title: "Python Capabilities",
            description: "Tests Python code generation.",
            cases: [
                .init(
                    title: "Python Hello World",
                    content: [
                        .init(type: .request, textRepresentation: "Print 'Hello World' in Python."),
                    ],
                    verifier: [.contains(pattern: "print("), .contains(pattern: "Hello World")],
                ),
                .init(
                    title: "Python Greet Function",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a Python function 'greet' that takes 'name'."
                        ),
                    ],
                    verifier: [.contains(pattern: "def greet(name):")],
                ),
                .init(
                    title: "Python List Comprehension",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Create a list comprehension in Python to square numbers 0-9. Use 'x' as iterator and use range(10)."
                        ),
                    ],
                    // 拆分以防止 spaces (x**2 vs x ** 2) 造成误判
                    verifier: [.contains(pattern: "x**2"), .contains(pattern: "for x in range(10)")],
                ),
                .init(
                    title: "Python Dictionary",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Create a dictionary with keys 'a', 'b' and values 1, 2 in Python. Use single quotes."
                        ),
                    ],
                    verifier: [.contains(pattern: "'a': 1"), .contains(pattern: "'b': 2")],
                ),
                .init(
                    title: "Python Import JSON",
                    content: [
                        .init(type: .request, textRepresentation: "Import the json module in Python."),
                    ],
                    verifier: [.contains(pattern: "import json")],
                ),
                .init(
                    title: "Python Dog Class",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a Python class 'Dog' with an __init__ method."
                        ),
                    ],
                    verifier: [.contains(pattern: "class Dog:"), .contains(pattern: "def __init__(self")],
                ),
                .init(
                    title: "Python F-String",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Use an f-string to interpolate variable 'name' in Python."
                        ),
                    ],
                    verifier: [.contains(pattern: "f\"{name}\"")],
                ),
                .init(
                    title: "Python Try-Except",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Write a try-except block catching ValueError in Python."
                        ),
                    ],
                    verifier: [.contains(pattern: "try:"), .contains(pattern: "except ValueError:")],
                ),
                .init(
                    title: "Python Lambda",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Create a lambda function in Python that adds 1 to argument 'x'."
                        ),
                    ],
                    verifier: [.contains(pattern: "lambda x:"), .contains(pattern: "x + 1")],
                ),
                .init(
                    title: "Python With Open",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Open 'test.txt' for writing using 'with' statement in Python. Use double quotes for the filename."
                        ),
                    ],
                    verifier: [.contains(pattern: "with open(\"test.txt\", \"w\")")],
                ),
                .init(
                    title: "Python Main Block",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Check if the script is being run directly using __name__ in Python."
                        ),
                    ],
                    verifier: [.contains(pattern: "if __name__ == \"__main__\":")],
                ),
                .init(
                    title: "Python List Slicing",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Slice a list 'lst' to get the first 3 elements in Python."
                        ),
                    ],
                    verifier: [.contains(pattern: "lst[:3]")],
                ),
                .init(
                    title: "Python Decorator",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Apply a decorator @my_decorator to function 'func' in Python."
                        ),
                    ],
                    verifier: [.contains(pattern: "@my_decorator"), .contains(pattern: "def func")],
                ),
                .init(
                    title: "Python Generator",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Write a generator function that yields numbers 1, 2, 3 in Python."
                        ),
                    ],
                    verifier: [.contains(pattern: "yield 1"), .contains(pattern: "yield 2")],
                ),
                .init(
                    title: "Python Set",
                    content: [
                        .init(type: .request, textRepresentation: "Create a set with values 1, 2, 3 in Python."),
                    ],
                    verifier: [.contains(pattern: "{1, 2, 3}")],
                ),
                .init(
                    title: "Python Async Def",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define an asynchronous function 'fetch_data' in Python."
                        ),
                    ],
                    verifier: [.contains(pattern: "async def fetch_data")],
                ),
                .init(
                    title: "Python Dataclass",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a dataclass 'Point' with x and y as int in Python."
                        ),
                    ],
                    verifier: [.contains(pattern: "dataclass"), .contains(pattern: "class Point:")],
                ),
                .init(
                    title: "Python Type Hints",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a function 'add' taking (a: int, b: int) -> int in Python."
                        ),
                    ],
                    verifier: [.contains(pattern: "def add(a: int, b: int) -> int:")],
                ),
                .init(
                    title: "Python Enumerate",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Iterate over a list with index using enumerate in Python. Use 'i' for index and 'item' for value."
                        ),
                    ],
                    verifier: [.contains(pattern: "for i, item in enumerate")],
                ),
                .init(
                    title: "Python Pass",
                    content: [
                        .init(type: .request, textRepresentation: "Use 'pass' in an empty function body in Python."),
                    ],
                    verifier: [.contains(pattern: "pass")],
                ),
            ],
        )
    }
}
