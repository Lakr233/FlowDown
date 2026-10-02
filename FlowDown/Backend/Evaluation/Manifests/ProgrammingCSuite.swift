//
//  ProgrammingCSuite.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import ChatClientKit
import Foundation

extension EvaluationManifest.Suite {
    static var programmingC: EvaluationManifest.Suite {
        EvaluationManifest.Suite(
            title: "C/C++ Capabilities",
            description: "Tests C and C++ programming generation.",
            cases: [
                // C Cases
                .init(
                    title: "C Hello World",
                    content: [
                        .init(type: .request, textRepresentation: "Write a Hello World program in C."),
                    ],
                    verifier: [
                        .contains(pattern: "printf"),
                        .contains(pattern: "Hello World"),
                        .contains(pattern: "main")
                    ],
                ),
                .init(
                    title: "C Add Function",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Write a C function 'add' that takes two integers 'a' and 'b', and returns their sum."
                        ),
                    ],
                    verifier: [.contains(pattern: "int add("), .contains(pattern: "return")],
                ),
                .init(
                    title: "C Swap Pointers",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Write a function 'swap' that swaps two integers using pointers in C."
                        ),
                    ],
                    verifier: [.contains(pattern: "void swap("), .contains(pattern: "int *"), .contains(pattern: "*")],
                ),
                .init(
                    title: "C Person Struct",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a C struct named 'Person' with a char array 'name' and int 'age'."
                        ),
                    ],
                    verifier: [
                        .contains(pattern: "struct Person"),
                        .contains(pattern: "char name"),
                        .contains(pattern: "int age")
                    ],
                ),
                .init(
                    title: "C For Loop",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Write a for loop in C that counts from 0 to 9 using variable 'i'."
                        ),
                    ],
                    verifier: [.contains(pattern: "for"), .contains(pattern: "i < 10"), .contains(pattern: "++")],
                ),
                .init(
                    title: "C If Statement",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Write an if-statement in C to check if variable 'x' is greater than 10."
                        ),
                    ],
                    // 分拆验证，兼容 if(x>10) 和 if (x > 10)
                    verifier: [.contains(pattern: "if"), .contains(pattern: "x > 10")],
                ),
                .init(
                    title: "C Malloc",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Allocate memory for an integer pointer 'p' using malloc in C."
                        ),
                    ],
                    verifier: [.contains(pattern: "malloc(sizeof(int))")],
                ),
                .init(
                    title: "C Macro",
                    content: [
                        .init(type: .request, textRepresentation: "Define a C macro PI with value 3.14."),
                    ],
                    verifier: [.contains(pattern: "#define PI 3.14")],
                ),
                .init(
                    title: "C Switch Statement",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Write a switch statement in C for variable 'grade'. Case 'A' prints 'Excellent'."
                        ),
                    ],
                    verifier: [
                        .contains(pattern: "switch"),
                        .contains(pattern: "grade"),
                        .contains(pattern: "case 'A':")
                    ],
                ),
                .init(
                    title: "C Include",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Include only the standard I/O library <stdio.h> in C."
                        ),
                    ],
                    verifier: [.contains(pattern: "#include <stdio.h>")],
                ),
                // C++ Cases
                .init(
                    title: "C++ Hello World",
                    content: [
                        .init(type: .request, textRepresentation: "Write a Hello World program in C++."),
                    ],
                    verifier: [.contains(pattern: "std::cout"), .contains(pattern: "Hello World")],
                ),
                .init(
                    title: "C++ Car Class",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a class 'Car' in C++ with a public method 'drive'."
                        ),
                    ],
                    verifier: [
                        .contains(pattern: "class Car"),
                        .contains(pattern: "public:"),
                        .contains(pattern: "void drive()")
                    ],
                ),
                .init(
                    title: "C++ String greeting",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Declare a std::string variable named 'greeting' in C++. Do not use 'using namespace std'."
                        ),
                    ],
                    verifier: [.contains(pattern: "std::string greeting")],
                ),
                .init(
                    title: "C++ Vector",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Create a std::vector of integers named 'vec' in C++."
                        ),
                    ],
                    verifier: [.contains(pattern: "std::vector<int>")],
                ),
                .init(
                    title: "C++ Template max",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Write a template function 'max' in C++. Use 'typename T'."
                        ),
                    ],
                    verifier: [.contains(pattern: "template"), .contains(pattern: "typename T")],
                ),
                .init(
                    title: "C++ Cin",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Read an integer 'x' from standard input using cin in C++."
                        ),
                    ],
                    verifier: [.contains(pattern: "std::cin >>")],
                ),
                .init(
                    title: "C++ Using Namespace",
                    content: [
                        .init(type: .request, textRepresentation: "Use the standard namespace in C++."),
                    ],
                    verifier: [.contains(pattern: "using namespace std;")],
                ),
                .init(
                    title: "C++ Pass By Reference",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Pass an integer by reference to a function 'update' in C++. Use argument name 'val'."
                        ),
                    ],
                    verifier: [.contains(pattern: "void update(int"), .contains(pattern: "&")],
                ),
                .init(
                    title: "C++ Point Constructor",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Define a constructor for class 'Point' that takes two integers 'x' and 'y' in C++."
                        ),
                    ],
                    verifier: [.contains(pattern: "Point(int x, int y)")],
                ),
                .init(
                    title: "C++ Inheritance Dog",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Create a class 'Dog' that publicly inherits from 'Animal' in C++."
                        ),
                    ],
                    verifier: [.contains(pattern: "class Dog"), .contains(pattern: ": public Animal")],
                ),
            ],
        )
    }
}
