//
//  ProgrammingGoSuite.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import ChatClientKit
import Foundation

extension EvaluationManifest.Suite {
    static var programmingGo: EvaluationManifest.Suite {
        EvaluationManifest.Suite(
            title: "Go Capabilities",
            description: "Tests Go code generation.",
            cases: [
                .init(
                    title: "Go Hello World",
                    content: [
                        .init(type: .request, textRepresentation: "Write a Hello World program in Go."),
                    ],
                    verifier: [.contains(pattern: "fmt.Println(\"Hello World\")"), .contains(pattern: "package main")],
                ),
                .init(
                    title: "Go Add Function",
                    content: [
                        // 强制显式声明每个参数的类型，防止 'a, b int' 语法导致失败
                        .init(
                            type: .request,
                            textRepresentation: "Define a function 'add' in Go that takes two ints 'a' and 'b' and returns an int. Declare types explicitly for each parameter."
                        ),
                    ],
                    verifier: [.contains(pattern: "func add(a int, b int) int")],
                ),
                .init(
                    title: "Go Goroutine",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Start a goroutine that calls function 'doWork()' in Go."
                        ),
                    ],
                    verifier: [.contains(pattern: "go doWork()")],
                ),
                .init(
                    title: "Go Channel",
                    content: [
                        .init(type: .request, textRepresentation: "Create a channel of integers in Go."),
                    ],
                    verifier: [.contains(pattern: "make(chan int)")],
                ),
                .init(
                    title: "Go Map",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Create a map with string keys and int values in Go."
                        ),
                    ],
                    verifier: [.contains(pattern: "map[string]int")],
                ),
                .init(
                    title: "Go Slice",
                    content: [
                        .init(type: .request, textRepresentation: "Create a slice of strings in Go using make."),
                    ],
                    verifier: [.contains(pattern: "make([]string")],
                ),
                .init(
                    title: "Go Person Struct",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a struct 'Person' with 'Name' (string) and 'Age' (int) in Go."
                        ),
                    ],
                    verifier: [.contains(pattern: "type Person struct"), .contains(pattern: "Name string")],
                ),
                .init(
                    title: "Go Speaker Interface",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define an interface 'Speaker' with method 'Speak' in Go."
                        ),
                    ],
                    verifier: [.contains(pattern: "type Speaker interface"), .contains(pattern: "Speak()")],
                ),
                .init(
                    title: "Go Error Check",
                    content: [
                        .init(type: .request, textRepresentation: "Check if error 'err' is not nil in Go."),
                    ],
                    verifier: [.contains(pattern: "if err != nil")],
                ),
                .init(
                    title: "Go Defer",
                    content: [
                        .init(type: .request, textRepresentation: "Use defer to close a file 'f' in Go."),
                    ],
                    verifier: [.contains(pattern: "defer f.Close()")],
                ),
                .init(
                    title: "Go Range",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Iterate over a slice 'items' using range in Go. Ignore index, name value 'item'."
                        ),
                    ],
                    verifier: [.contains(pattern: "for _, item := range items")],
                ),
                .init(
                    title: "Go Select",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Use select statement to wait on channel 'ch' in Go."
                        ),
                    ],
                    verifier: [.contains(pattern: "select {"), .contains(pattern: "case <-ch:")],
                ),
                .init(
                    title: "Go Pointer",
                    content: [
                        .init(type: .request, textRepresentation: "Declare a pointer to an integer variable in Go."),
                    ],
                    verifier: [.contains(pattern: "*int")],
                ),
                .init(
                    title: "Go Import",
                    content: [
                        .init(type: .request, textRepresentation: "Import the 'fmt' package in Go."),
                    ],
                    verifier: [.contains(pattern: "import \"fmt\"")],
                ),
                .init(
                    title: "Go Person Method",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a method 'Greet' on struct 'Person' in Go. Use pointer receiver 'p'."
                        ),
                    ],
                    verifier: [.contains(pattern: "func (p *Person) Greet()")],
                ),
                .init(
                    title: "Go Constant",
                    content: [
                        .init(type: .request, textRepresentation: "Define a constant 'Pi' equal to 3.14 in Go."),
                    ],
                    verifier: [.contains(pattern: "const Pi =")],
                ),
                .init(
                    title: "Go WaitGroup",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Use sync.WaitGroup to wait for goroutines in Go. Use variable named 'wg'."
                        ),
                    ],
                    verifier: [.contains(pattern: "sync.WaitGroup"), .contains(pattern: "wg.Wait()")],
                ),
                .init(
                    title: "Go Struct Tag",
                    content: [
                        .init(type: .request, textRepresentation: "Add a JSON tag 'name' to struct field Name in Go."),
                    ],
                    verifier: [.contains(pattern: "`json:\"name\"`")],
                ),
                .init(
                    title: "Go Test Add",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Write a test function 'TestAdd' in Go. Use 't' as *testing.T."
                        ),
                    ],
                    verifier: [.contains(pattern: "func TestAdd(t *testing.T)")],
                ),
                .init(
                    title: "Go Person Literal",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Initialize a struct 'Person' literal with name 'Bob' in Go."
                        ),
                    ],
                    verifier: [.contains(pattern: "Person{Name: \"Bob\"}")],
                ),
            ],
        )
    }
}
