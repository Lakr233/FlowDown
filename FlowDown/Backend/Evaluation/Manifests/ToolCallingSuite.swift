//
//  ToolCallingSuite.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import ChatClientKit
import Foundation

extension EvaluationManifest.Suite {
    static var toolCalling: EvaluationManifest.Suite {
        EvaluationManifest.Suite(
            title: "Tool Calling",
            description: "Tests the model's ability to invoke tools with correct parameters based on user instructions.",
            cases: [
                // Case 1: Weather
                .init(
                    title: "Weather Tokyo",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "get_weather",
                                description: "Get the current weather for a city.",
                                parameters: ["city": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "What is the weather in Tokyo?"),
                    ],
                    verifier: [.tool(parameter: "city", value: .init(stringLiteral: "Tokyo"))],
                ),
                // Case 2: Calculation
                .init(
                    title: "Calculate Expression",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "calculate",
                                description: "Evaluate a mathematical expression.",
                                parameters: ["expression": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Calculate 23 * 45"),
                    ],
                    verifier: [.tool(parameter: "expression", value: .init(stringLiteral: "23 * 45"))],
                ),
                // Case 3: Search
                .init(
                    title: "Web Search",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "search",
                                description: "Search the web for a query.",
                                parameters: ["query": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Search for 'DeepMind'"),
                    ],
                    verifier: [.tool(parameter: "query", value: .init(stringLiteral: "DeepMind"))],
                ),
                // Case 4: Email
                .init(
                    title: "Send Email",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "send_email",
                                description: "Send an email to a recipient.",
                                parameters: ["to": .init(stringLiteral: "string"), "subject": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Send an email to alice@example.com with subject 'Hi'"),
                    ],
                    verifier: [
                        .tool(parameter: "to", value: .init(stringLiteral: "alice@example.com")),
                        .tool(parameter: "subject", value: .init(stringLiteral: "Hi")),
                    ],
                ),
                // Case 5: Alarm
                .init(
                    title: "Set Alarm",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "set_alarm",
                                description: "Set an alarm for a specific time.",
                                parameters: ["time": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Wake me up at 08:00"),
                    ],
                    verifier: [.tool(parameter: "time", value: .init(stringLiteral: "08:00"))],
                ),
                // Case 6: Smart Home
                .init(
                    title: "Turn On Light",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "turn_on_light",
                                description: "Turn on the light in a specific room.",
                                parameters: ["room": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Turn on the kitchen lights"),
                    ],
                    verifier: [.tool(parameter: "room", value: .init(stringLiteral: "kitchen"))],
                ),
                // Case 7: Music
                .init(
                    title: "Play Music",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "play_music",
                                description: "Play a specific song.",
                                parameters: ["song": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Play 'Happy'"),
                    ],
                    verifier: [.tool(parameter: "song", value: .init(stringLiteral: "Happy"))],
                ),
                // Case 8: Translation
                .init(
                    title: "Translate Text",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "translate",
                                description: "Translate text to a target language.",
                                parameters: ["text": .init(stringLiteral: "string"), "target_language": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Translate 'Hello' to Spanish"),
                    ],
                    verifier: [
                        .tool(parameter: "text", value: .init(stringLiteral: "Hello")),
                        .tool(parameter: "target_language", value: .init(stringLiteral: "Spanish")),
                    ],
                ),
                // Case 9: Currency
                .init(
                    title: "Convert Currency",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "convert_currency",
                                description: "Convert amount from one currency to another.",
                                parameters: ["amount": .init(stringLiteral: "number"), "from": .init(stringLiteral: "string"), "to": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Convert 100 USD to EUR"),
                    ],
                    verifier: [
                        .tool(parameter: "amount", value: .init(integerLiteral: 100)),
                        .tool(parameter: "from", value: .init(stringLiteral: "USD")),
                        .tool(parameter: "to", value: .init(stringLiteral: "EUR")),
                    ],
                ),
                // Case 10: Stocks
                .init(
                    title: "Check Stock",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "check_stock",
                                description: "Check current stock price.",
                                parameters: ["symbol": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "What is the price of AAPL?"),
                    ],
                    verifier: [.tool(parameter: "symbol", value: .init(stringLiteral: "AAPL"))],
                ),
                // Case 11: Flight
                .init(
                    title: "Book Flight",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "book_flight",
                                description: "Book a flight to a destination.",
                                parameters: ["destination": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Book a flight to Paris"),
                    ],
                    verifier: [.tool(parameter: "destination", value: .init(stringLiteral: "Paris"))],
                ),
                // Case 12: Calendar
                .init(
                    title: "Create Event",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "create_event",
                                description: "Create a calendar event.",
                                parameters: ["title": .init(stringLiteral: "string"), "date": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Schedule a 'Meeting' on 2025-01-01"),
                    ],
                    verifier: [
                        .tool(parameter: "title", value: .init(stringLiteral: "Meeting")),
                        .tool(parameter: "date", value: .init(stringLiteral: "2025-01-01")),
                    ],
                ),
                // Case 13: Recipe
                .init(
                    title: "Find Recipe",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "find_recipe",
                                description: "Find a recipe for a dish.",
                                parameters: ["dish": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "How do I make Pasta?"),
                    ],
                    verifier: [.tool(parameter: "dish", value: .init(stringLiteral: "Pasta"))],
                ),
                // Case 14: Reminder
                .init(
                    title: "Set Reminder",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "remind_me",
                                description: "Set a reminder for a task.",
                                parameters: ["task": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Remind me to 'Buy milk'"),
                    ],
                    verifier: [.tool(parameter: "task", value: .init(stringLiteral: "Buy milk"))],
                ),
                // Case 15: Dice
                .init(
                    title: "Roll Dice",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "roll_dice",
                                description: "Roll a die with N sides.",
                                parameters: ["sides": .init(stringLiteral: "integer")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Roll a 20-sided die"),
                    ],
                    verifier: [.tool(parameter: "sides", value: .init(integerLiteral: 20))],
                ),
                // Case 16: Coin
                .init(
                    title: "Flip Coin",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "flip_coin",
                                description: "Flip a coin.",
                                parameters: [:],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Flip a coin"),
                    ],
                    verifier: [.toolCalled(name: "flip_coin")],
                ),
                // Case 17: Volume
                .init(
                    title: "Set Volume",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "set_volume",
                                description: "Set the volume level.",
                                parameters: ["level": .init(stringLiteral: "integer")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Set volume to 50"),
                    ],
                    verifier: [.tool(parameter: "level", value: .init(integerLiteral: 50))],
                ),
                // Case 18: Brightness
                .init(
                    title: "Set Brightness",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "set_brightness",
                                description: "Set the screen brightness.",
                                parameters: ["percent": .init(stringLiteral: "integer")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Set brightness to 80%"),
                    ],
                    verifier: [.tool(parameter: "percent", value: .init(integerLiteral: 80))],
                ),
                // Case 19: Navigation
                .init(
                    title: "Navigate Location",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "navigate",
                                description: "Navigate to a location.",
                                parameters: ["location": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Navigate to 'Home'"),
                    ],
                    verifier: [.tool(parameter: "location", value: .init(stringLiteral: "Home"))],
                ),
                // Case 20: Note
                .init(
                    title: "Create Note",
                    content: [
                        .init(
                            type: .toolDefinition,
                            toolRepresentation: .init(
                                name: "create_note",
                                description: "Create a new note.",
                                parameters: ["content": .init(stringLiteral: "string")],
                            ),
                        ),
                        .init(type: .request, textRepresentation: "Note: 'Meeting at 5pm'"),
                    ],
                    verifier: [.tool(parameter: "content", value: .init(stringLiteral: "Meeting at 5pm"))],
                ),
            ],
        )
    }
}
