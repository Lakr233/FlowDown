#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


class FixtureStore:
    def __init__(
        self,
        fixture_dir: Path,
        mode: str,
        upstream_endpoint: str | None,
        upstream_model: str | None,
        api_key: str | None,
    ) -> None:
        self.case_dir = fixture_dir / "cases"
        self.mode = mode
        self.upstream_endpoint = upstream_endpoint
        self.upstream_model = upstream_model
        self.api_key = api_key
        self.case_dir.mkdir(parents=True, exist_ok=True)

    def response_for(self, body: dict[str, Any]) -> tuple[int, str, bytes]:
        key = scenario_key(body)
        stream = bool(body.get("stream", False))

        if self.mode == "record":
            status, content_type, data = self.record(key, body, stream)
            return status, content_type, data

        return self.replay(key, stream)

    def record(self, key: str, body: dict[str, Any], stream: bool) -> tuple[int, str, bytes]:
        if not self.upstream_endpoint or not self.upstream_model or not self.api_key:
            return self.error_response(500, "record mode requires upstream endpoint, model, and api key")

        request_body = dict(body)
        request_body["model"] = self.upstream_model
        status, data = self.capture_with_curl(request_body)
        content_type = "text/event-stream" if stream else "application/json"

        suffix = "sse" if stream else "json"
        response_path = self.case_dir / f"{key}.response.{suffix}"
        request_path = self.case_dir / f"{key}.request.json"
        metadata_path = self.case_dir / f"{key}.meta.json"

        request_path.write_text(
            json.dumps(request_body, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        response_path.write_bytes(data)
        metadata_path.write_text(
            json.dumps(
                {
                    "key": key,
                    "status": status,
                    "content_type": content_type,
                    "stream": stream,
                    "upstream_endpoint": self.upstream_endpoint,
                    "upstream_model": self.upstream_model,
                },
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            ) + "\n",
            encoding="utf-8",
        )

        return status, content_type, data

    def replay(self, key: str, stream: bool) -> tuple[int, str, bytes]:
        suffix = "sse" if stream else "json"
        response_path = self.case_dir / f"{key}.response.{suffix}"
        metadata_path = self.case_dir / f"{key}.meta.json"

        if not response_path.exists() or not metadata_path.exists():
            return self.error_response(503, f"missing captured online e2e fixture: {key}")

        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        status = int(metadata["status"])
        content_type = str(metadata["content_type"])
        return status, content_type, response_path.read_bytes()

    def capture_with_curl(self, body: dict[str, Any]) -> tuple[int, bytes]:
        with tempfile.TemporaryDirectory(prefix="flowdown-e2e-capture.") as directory:
            directory_path = Path(directory)
            request_path = directory_path / "request.json"
            header_path = directory_path / "headers.txt"
            response_path = directory_path / "response.body"
            request_path.write_text(
                json.dumps(body, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
                encoding="utf-8",
            )
            header_path.write_text(
                f"Authorization: Bearer {self.api_key}\nContent-Type: application/json\n",
                encoding="utf-8",
            )

            command = [
                "curl",
                "--silent",
                "--show-error",
                "--no-buffer",
                "--output",
                str(response_path),
                "--write-out",
                "%{http_code}",
                "--request",
                "POST",
                "--url",
                self.upstream_endpoint or "",
                "--header",
                f"@{header_path}",
                "--data",
                f"@{request_path}",
            ]
            result = subprocess.run(
                command,
                check=False,
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                message = result.stderr.strip() or "curl capture failed"
                raise RuntimeError(message)

            status = int(result.stdout.strip() or "0")
            return status, response_path.read_bytes()

    def error_response(self, status: int, message: str) -> tuple[int, str, bytes]:
        payload = json.dumps({"error": message}, separators=(",", ":")).encode("utf-8")
        return status, "application/json", payload


class FixtureHandler(BaseHTTPRequestHandler):
    store: FixtureStore

    def do_POST(self) -> None:
        if self.path != "/v1/chat/completions":
            self.send_error(404)
            return

        length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(length)
        try:
            body = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError:
            self.send_error(400, "invalid json")
            return

        try:
            status, content_type, data = self.store.response_for(body)
        except Exception as error:
            status, content_type, data = self.store.error_response(500, str(error))

        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args: Any) -> None:
        return


def scenario_key(body: dict[str, Any]) -> str:
    messages = body.get("messages", [])
    tools = body.get("tools") or []
    text = flatten_messages(messages).lower()
    names = tool_names(tools)

    if not body.get("stream", False):
        return "cache_usage"

    reminder_key = reminder_tool_key(names)
    if reminder_key is not None:
        return reminder_key

    if {"lookup_population", "add_numbers"}.issubset(names):
        return f"tool_population_round_{len(tool_outputs(messages))}"

    if "add_numbers" in names:
        return "tool_add_numbers_call"

    if "add_numbers" in text and "42" in text:
        return "tool_add_numbers_final"

    if "generate conversation metadata" in text:
        return "conversation_metadata"

    if "professional conversation summarization assistant" in text or "project atlas ships" in text:
        return "conversation_compression"

    if "template_generation" in text:
        return "template_generation"

    if "current template:" in text and "weekly status" in text:
        return "template_rewrite"

    if "five words or fewer" in text:
        return "reasoning_sky_short"

    if "why the sky is blue" in text:
        return "reasoning_sky"

    if "favorite drink" in text and "answer with just the drink" in text:
        return "memory_drink"

    if "what did i tell you my name was" in text:
        return "memory_name"

    if "my name is priya" in text:
        return "memory_ack"

    if "say hello" in text:
        return "reasoning_hello"

    raise ValueError("unclassified online e2e request; add an explicit scenario key before recording")


def reminder_tool_key(names: set[str]) -> str | None:
    for name in [
        "add_reminder",
        "query_reminders",
        "update_reminder",
        "delete_reminder",
        "complete_reminder",
    ]:
        if name in names:
            return f"reminder_{name}"
    return None


def flatten_messages(messages: list[dict[str, Any]]) -> str:
    values: list[str] = []
    for message in messages:
        content = message.get("content")
        if isinstance(content, str):
            values.append(content)
        elif isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and isinstance(part.get("text"), str):
                    values.append(part["text"])
    return "\n".join(values)


def tool_outputs(messages: list[dict[str, Any]]) -> list[str]:
    return [
        message.get("content", "")
        for message in messages
        if message.get("role") == "tool" and isinstance(message.get("content"), str)
    ]


def tool_names(tools: list[dict[str, Any]]) -> set[str]:
    names: set[str] = set()
    for tool in tools:
        function = tool.get("function")
        if isinstance(function, dict) and isinstance(function.get("name"), str):
            names.add(function["name"])
    return names


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--port-file", required=True)
    parser.add_argument("--fixture-dir", required=True)
    parser.add_argument("--mode", choices=["replay", "record"], default="replay")
    parser.add_argument("--upstream-endpoint", default="https://api.fireworks.ai/inference/v1/chat/completions")
    parser.add_argument("--upstream-model")
    args = parser.parse_args()

    api_key = os.environ.get("FIREWORKS_API_KEY")
    FixtureHandler.store = FixtureStore(
        fixture_dir=Path(args.fixture_dir),
        mode=args.mode,
        upstream_endpoint=args.upstream_endpoint,
        upstream_model=args.upstream_model,
        api_key=api_key,
    )
    server = ThreadingHTTPServer((args.host, args.port), FixtureHandler)
    host, port = server.server_address
    Path(args.port_file).write_text(f"http://{host}:{port}/v1/chat/completions\n", encoding="utf-8")
    server.serve_forever()


if __name__ == "__main__":
    main()
