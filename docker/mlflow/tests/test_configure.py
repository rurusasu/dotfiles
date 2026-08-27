from __future__ import annotations

import json
import sys
import tempfile
import threading
import unittest
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


MLFLOW_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MLFLOW_DIR))

from configure import (  # noqa: E402
    GatewayClient,
    GatewayHTTPError,
    GatewayVerificationError,
    reconcile_manifest,
    verify_gateway,
)


class GatewayFixture:
    def __init__(self) -> None:
        self.secrets: dict[str, dict[str, object]] = {}
        self.models: dict[str, dict[str, object]] = {}
        self.endpoints: dict[str, dict[str, object]] = {}
        self.calls: Counter[tuple[str, str]] = Counter()
        self.requests: list[tuple[str, str, dict[str, str], dict[str, object]]] = []
        self.failure_response: dict[str, object] = {
            "api_key": "never-print-me",
            "value": "also-secret",
        }
        self.chat_response: dict[str, object] = {
            "choices": [{"message": {"role": "assistant", "content": "ok"}}]
        }
        self.embedding_response: dict[str, object] = {
            "data": [{"embedding": [0.0], "index": 0}]
        }
        self.record_traces = True
        self.trace_records: list[dict[str, object]] = []
        self.trace_search_status: int | None = None
        self.next_id = 1
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), self._handler())
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def url(self) -> str:
        host, port = self.server.server_address
        return f"http://{host}:{port}/"

    def start(self) -> None:
        self.thread.start()

    def close(self) -> None:
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()

    def _new_id(self, prefix: str) -> str:
        value = f"{prefix}-{self.next_id}"
        self.next_id += 1
        return value

    def _handler(self):
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802
                self._dispatch()

            def do_POST(self) -> None:  # noqa: N802
                self._dispatch()

            def log_message(self, format: str, *args: object) -> None:
                return

            def _dispatch(self) -> None:
                parsed = urlparse(self.path)
                fixture.calls[(self.command, parsed.path)] += 1
                if parsed.path == "/failure":
                    self._send(503, fixture.failure_response)
                    return
                if parsed.path == "/api/3.0/mlflow/traces/search" and fixture.trace_search_status:
                    self._send(fixture.trace_search_status, {"message": "trace search unavailable"})
                    return

                query = {key: values[0] for key, values in parse_qs(parsed.query).items()}
                body = self._body()
                fixture.requests.append((self.command, parsed.path, query, body))
                try:
                    response = self._route(parsed.path, query, body)
                except KeyError:
                    self._send(404, {"message": "missing"})
                    return
                self._send(200, response)

            def _body(self) -> dict[str, object]:
                length = int(self.headers.get("Content-Length", "0"))
                return json.loads(self.rfile.read(length) or b"{}")

            def _route(
                self, path: str, query: dict[str, str], body: dict[str, object]
            ) -> dict[str, object]:
                if path.endswith("/secrets/get"):
                    secret = fixture.secrets[query["secret_name"]]
                    return {"secret": fixture._secret_info(secret)}
                if path.endswith("/secrets/list"):
                    return {"secrets": [fixture._secret_info(secret) for secret in fixture.secrets.values()]}
                if path.endswith("/secrets/create"):
                    secret = {
                        "secret_id": fixture._new_id("secret"),
                        "secret_name": body["secret_name"],
                        "provider": body["provider"],
                        "auth_config": body["auth_config"],
                        "secret_value": body["secret_value"],
                    }
                    fixture.secrets[str(secret["secret_name"])] = secret
                    return {"secret": fixture._secret_info(secret)}
                if path.endswith("/secrets/update"):
                    secret = fixture._find(fixture.secrets, "secret_id", body["secret_id"])
                    secret["auth_config"] = body["auth_config"]
                    secret["secret_value"] = body["secret_value"]
                    return {"secret": fixture._secret_info(secret)}
                if path.endswith("/model-definitions/list"):
                    return {"model_definitions": list(fixture.models.values())}
                if path.endswith("/model-definitions/create"):
                    model = dict(body)
                    model["model_definition_id"] = fixture._new_id("model")
                    fixture.models[str(model["name"])] = model
                    return {"model_definition": model}
                if path.endswith("/model-definitions/update"):
                    model = fixture._find(
                        fixture.models, "model_definition_id", body["model_definition_id"]
                    )
                    model.update(body)
                    return {"model_definition": model}
                if path.endswith("/endpoints/get"):
                    return {"endpoint": fixture.endpoints[query["name"]]}
                if path.endswith("/endpoints/create"):
                    endpoint = dict(body)
                    endpoint["endpoint_id"] = fixture._new_id("endpoint")
                    endpoint["experiment_id"] = f"experiment-{endpoint['name']}"
                    endpoint["model_mappings"] = [
                        {
                            "mapping_id": fixture._new_id("mapping"),
                            "endpoint_id": endpoint["endpoint_id"],
                            "model_definition_id": model["model_definition_id"],
                            "linkage_type": model["linkage_type"],
                            "weight": model["weight"],
                        }
                        for model in body["model_configs"]
                    ]
                    fixture.endpoints[str(endpoint["name"])] = endpoint
                    return {"endpoint": endpoint}
                if path.endswith("/endpoints/update"):
                    endpoint = fixture._find(
                        fixture.endpoints, "endpoint_id", body["endpoint_id"]
                    )
                    endpoint.update(body)
                    endpoint["model_mappings"] = [
                        {
                            "mapping_id": fixture._new_id("mapping"),
                            "endpoint_id": endpoint["endpoint_id"],
                            "model_definition_id": model["model_definition_id"],
                            "linkage_type": model["linkage_type"],
                            "weight": model["weight"],
                        }
                        for model in body["model_configs"]
                    ]
                    return {"endpoint": endpoint}
                if path == "/gateway/mlflow/v1/chat/completions":
                    fixture._record_trace(body)
                    return fixture.chat_response
                if path == "/gateway/openai/v1/embeddings":
                    fixture._record_trace(body)
                    return fixture.embedding_response
                if path == "/api/3.0/mlflow/traces/search":
                    return {"traces": fixture.trace_records}
                raise KeyError(path)

            def _send(self, status: int, response: dict[str, object]) -> None:
                encoded = json.dumps(response).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)

        return Handler

    def _record_trace(self, body: dict[str, object]) -> None:
        if not self.record_traces:
            return
        endpoint = self.endpoints[str(body["model"])]
        self.trace_records.append(
            {
                "trace_metadata": [
                    {
                        "key": "mlflow.gateway.endpointId",
                        "value": endpoint["endpoint_id"],
                    }
                ],
                "request_preview": json.dumps(body),
            }
        )

    @staticmethod
    def _secret_info(secret: dict[str, object]) -> dict[str, object]:
        return {
            "secret_id": secret["secret_id"],
            "secret_name": secret["secret_name"],
            "provider": secret["provider"],
            "auth_config": secret["auth_config"],
            "masked_values": {"api_key": "********"},
        }

    @staticmethod
    def _find(
        resources: dict[str, dict[str, object]], field: str, value: object
    ) -> dict[str, object]:
        return next(resource for resource in resources.values() if resource[field] == value)


class ConfigureGatewayTest(unittest.TestCase):
    def setUp(self) -> None:
        self.gateway = GatewayFixture()
        self.gateway.start()
        self.addCleanup(self.gateway.close)
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.manifest = Path(self.temporary_directory.name) / "endpoints.json"
        self.manifest.write_text(
            json.dumps(
                {
                    "endpoints": [
                        {
                            "name": "ollama-chat-default",
                            "provider": "ollama",
                            "model_name": "qwen3.6:35b",
                            "api_base": "http://host.docker.internal:11434/v1",
                            "capability": "chat",
                            "usage_tracking": True,
                        },
                        {
                            "name": "ollama-embedding-default",
                            "provider": "ollama",
                            "model_name": "qwen3-embedding:0.6b",
                            "api_base": "http://host.docker.internal:11434/v1",
                            "capability": "embeddings",
                            "usage_tracking": True,
                        },
                    ]
                }
            )
        )

    def test_reconciliation_is_idempotent_and_repairs_drift_without_duplicates(self) -> None:
        reconcile_manifest(self.gateway.url, self.manifest)

        self.assertEqual(set(self.gateway.secrets), {"ollama-local"})
        self.assertGreater(
            self.gateway.calls[("GET", "/api/3.0/mlflow/gateway/secrets/list")], 0
        )
        self.assertEqual(
            self.gateway.calls[("GET", "/api/3.0/mlflow/gateway/secrets/get")], 0
        )
        self.assertEqual(set(self.gateway.models), {"ollama-chat-default", "ollama-embedding-default"})
        self.assertEqual(
            set(self.gateway.endpoints), {"ollama-chat-default", "ollama-embedding-default"}
        )
        self.assertTrue(self.gateway.endpoints["ollama-chat-default"]["usage_tracking"])

        self.assertEqual(
            self.gateway.endpoints["ollama-chat-default"]["model_configs"][0]["linkage_type"],
            "PRIMARY",
        )

        creates = Counter(
            {
                key: count
                for key, count in self.gateway.calls.items()
                if key[1].endswith("/create")
            }
        )
        reconcile_manifest(self.gateway.url, self.manifest)

        self.assertEqual(
            creates,
            Counter(
                {
                    key: count
                    for key, count in self.gateway.calls.items()
                    if key[1].endswith("/create")
                }
            ),
        )
        self.assertEqual(
            self.gateway.calls[("POST", "/api/3.0/mlflow/gateway/secrets/update")], 0
        )
        self.assertEqual(
            self.gateway.calls[("POST", "/api/3.0/mlflow/gateway/endpoints/update")], 0
        )
        self.assertEqual(
            self.gateway.calls[("POST", "/api/3.0/mlflow/gateway/model-definitions/update")], 0
        )

        self.gateway.secrets["ollama-local"]["auth_config"] = {"api_base": "http://drifted"}
        self.gateway.endpoints["ollama-chat-default"]["usage_tracking"] = False
        reconcile_manifest(self.gateway.url, self.manifest)

        self.assertEqual(
            self.gateway.calls[("POST", "/api/3.0/mlflow/gateway/secrets/update")], 1
        )
        self.assertEqual(
            self.gateway.calls[("POST", "/api/3.0/mlflow/gateway/endpoints/update")], 1
        )
        self.assertTrue(self.gateway.endpoints["ollama-chat-default"]["usage_tracking"])

    def test_manifest_requires_a_supported_capability(self) -> None:
        manifest = json.loads(self.manifest.read_text(encoding="utf-8"))
        del manifest["endpoints"][0]["capability"]
        self.manifest.write_text(json.dumps(manifest), encoding="utf-8")

        with self.assertRaisesRegex(ValueError, "capability"):
            reconcile_manifest(self.gateway.url, self.manifest)

    def test_http_errors_include_status_and_path_without_sensitive_content(self) -> None:
        client = GatewayClient(self.gateway.url)

        with self.assertRaises(GatewayHTTPError) as raised:
            client.request("POST", "/failure", {"api_key": "client-secret"})

        message = str(raised.exception)
        self.assertIn("POST /failure", message)
        self.assertIn("status=503", message)
        self.assertNotIn("api_key", message)
        self.assertNotIn("never-print-me", message)
        self.assertNotIn("also-secret", message)
        self.assertNotIn("client-secret", message)

    def test_http_error_redacts_payload_fields_and_inline_sensitive_assignments(self) -> None:
        self.gateway.failure_response = {
            "message": (
                "api_key=inline-key prompt=prompt-body response=reply-body "
                "request_preview=request-body response_preview=response-body"
            ),
            "secret": "field-secret",
            "secret_value": "field-secret-value",
            "prompt": "field-prompt",
            "response": "field-response",
            "request_preview": "field-request-preview",
            "response_preview": "field-response-preview",
        }

        with self.assertRaises(GatewayHTTPError) as raised:
            GatewayClient(self.gateway.url).request("POST", "/failure")

        message = str(raised.exception)
        for sensitive in (
            "inline-key",
            "prompt-body",
            "reply-body",
            "request-body",
            "response-body",
            "field-secret",
            "field-secret-value",
            "field-prompt",
            "field-response",
            "field-request-preview",
            "field-response-preview",
        ):
            self.assertNotIn(sensitive, message)

    def test_verification_sends_both_openai_requests_and_checks_gateway_trace_metadata(self) -> None:
        reconcile_manifest(self.gateway.url, self.manifest)

        verify_gateway(
            self.gateway.url,
            "ollama-chat-default",
            "ollama-embedding-default",
        )

        requests = {
            path: body
            for method, path, _query, body in self.gateway.requests
            if method == "POST"
        }
        self.assertEqual(
            requests["/gateway/mlflow/v1/chat/completions"]["model"], "ollama-chat-default"
        )
        self.assertEqual(
            requests["/gateway/mlflow/v1/chat/completions"]["max_tokens"], 512
        )
        self.assertEqual(
            requests["/gateway/openai/v1/embeddings"]["model"], "ollama-embedding-default"
        )
        self.assertEqual(len(self.gateway.trace_records), 2)
        trace_search = requests["/api/3.0/mlflow/traces/search"]
        self.assertEqual(len(trace_search["locations"]), 2)
        self.assertIn("trace.timestamp_ms >=", trace_search["filter"])

    def test_verification_rejects_chat_without_assistant_content(self) -> None:
        reconcile_manifest(self.gateway.url, self.manifest)
        self.gateway.chat_response = {"choices": [{}]}

        with self.assertRaisesRegex(GatewayVerificationError, "response-shape failure"):
            verify_gateway(
                self.gateway.url,
                "ollama-chat-default",
                "ollama-embedding-default",
            )

    def test_verification_rejects_mixed_valid_and_malformed_chat_choices(self) -> None:
        reconcile_manifest(self.gateway.url, self.manifest)
        self.gateway.chat_response = {
            "choices": [
                {"message": {"role": "assistant", "content": "ok"}},
                {},
            ]
        }

        with self.assertRaisesRegex(GatewayVerificationError, "response-shape failure"):
            verify_gateway(
                self.gateway.url,
                "ollama-chat-default",
                "ollama-embedding-default",
            )

    def test_verification_rejects_non_numeric_embedding_data(self) -> None:
        reconcile_manifest(self.gateway.url, self.manifest)
        self.gateway.embedding_response = {"data": ["error"]}

        with self.assertRaisesRegex(GatewayVerificationError, "response-shape failure"):
            verify_gateway(
                self.gateway.url,
                "ollama-chat-default",
                "ollama-embedding-default",
            )

    def test_verification_rejects_non_finite_embedding_values(self) -> None:
        reconcile_manifest(self.gateway.url, self.manifest)

        for value in (float("nan"), float("inf"), -float("inf")):
            with self.subTest(value=value):
                self.gateway.embedding_response = {"data": [{"embedding": [value]}]}
                with self.assertRaisesRegex(GatewayVerificationError, "response-shape failure"):
                    verify_gateway(
                        self.gateway.url,
                        "ollama-chat-default",
                        "ollama-embedding-default",
                    )

    def test_trace_search_http_failure_is_classified_as_gateway_availability(self) -> None:
        reconcile_manifest(self.gateway.url, self.manifest)
        self.gateway.trace_search_status = 503

        with self.assertRaisesRegex(GatewayVerificationError, "Gateway availability failure"):
            verify_gateway(
                self.gateway.url,
                "ollama-chat-default",
                "ollama-embedding-default",
            )

    def test_verification_rejects_missing_traces(self) -> None:
        reconcile_manifest(self.gateway.url, self.manifest)
        self.gateway.record_traces = False

        with self.assertRaisesRegex(GatewayVerificationError, "Missing traces"):
            verify_gateway(
                self.gateway.url,
                "ollama-chat-default",
                "ollama-embedding-default",
            )

    def test_verification_rejects_unrelated_traces(self) -> None:
        reconcile_manifest(self.gateway.url, self.manifest)
        self.gateway.record_traces = False
        self.gateway.trace_records = [
            {
                "trace_metadata": [
                    {
                        "key": "mlflow.gateway.endpointId",
                        "value": endpoint["endpoint_id"],
                    }
                ],
                "request_preview": json.dumps({"marker": "unrelated"}),
            }
            for endpoint in self.gateway.endpoints.values()
        ]

        with self.assertRaisesRegex(GatewayVerificationError, "Missing traces"):
            verify_gateway(
                self.gateway.url,
                "ollama-chat-default",
                "ollama-embedding-default",
            )


if __name__ == "__main__":
    unittest.main()
