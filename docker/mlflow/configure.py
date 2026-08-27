from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path
from time import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


API_PREFIX = "/api/3.0/mlflow"
SENSITIVE_KEYS = frozenset(
    {
        "api_key",
        "value",
        "secret",
        "secret_value",
        "token",
        "prompt",
        "response",
        "request",
        "request_preview",
        "response_preview",
        "messages",
        "input",
        "content",
        "embedding",
        "embeddings",
        "choices",
        "data",
    }
)
INLINE_SENSITIVE_ASSIGNMENT = re.compile(
    r"(?i)\b(?:api_key|value|secret|token|prompt|response|request(?:_preview)?|response_preview)\b"
    r"\s*[:=]\s*(?:\"[^\"]*\"|'[^']*'|[^,}\]\s]+)"
)


class GatewayHTTPError(RuntimeError):
    def __init__(self, method: str, path: str, status: int | None, response: object) -> None:
        self.method = method
        self.path = path
        self.status = status
        self.response = _redact(response)
        super().__init__(
            f"Gateway request failed: {method} {path} status={status} response={self.response}"
        )


class GatewayVerificationError(RuntimeError):
    """Raised when a live Gateway probe cannot prove a required capability."""


def _redact(value: object) -> object:
    if isinstance(value, dict):
        redacted_count = sum(
            isinstance(key, str) and key.lower() in SENSITIVE_KEYS for key in value
        )
        sanitized = {
            key: _redact(item)
            for key, item in value.items()
            if not isinstance(key, str) or key.lower() not in SENSITIVE_KEYS
        }
        if redacted_count:
            sanitized["redacted_fields"] = redacted_count
        return sanitized
    if isinstance(value, list):
        return [_redact(item) for item in value]
    if isinstance(value, str):
        return INLINE_SENSITIVE_ASSIGNMENT.sub("<redacted>", value)
    return value


def _decode_json(payload: bytes) -> object:
    if not payload:
        return {}
    try:
        return json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return {"body": "<non-json response>"}


class GatewayClient:
    def __init__(self, base_url: str) -> None:
        self.base_url = base_url.rstrip("/")

    def request(
        self, method: str, path: str, payload: dict[str, object] | None = None
    ) -> dict[str, object]:
        method = method.upper()
        url = f"{self.base_url}{path}"
        body: bytes | None = None
        if method == "GET" and payload:
            url = f"{url}?{urlencode(payload)}"
        elif payload is not None:
            body = json.dumps(payload).encode("utf-8")

        request = Request(
            url,
            data=body,
            method=method,
            headers={"Content-Type": "application/json", "Accept": "application/json"},
        )
        try:
            with urlopen(request, timeout=15) as response:  # noqa: S310 -- base URL is operator supplied.
                decoded = _decode_json(response.read())
        except HTTPError as error:
            decoded = _decode_json(error.read())
            error.close()
            raise GatewayHTTPError(method, path, error.code, decoded) from error
        except URLError as error:
            raise GatewayHTTPError(method, path, None, {"error": str(error.reason)}) from error

        if not isinstance(decoded, dict):
            raise GatewayHTTPError(method, path, None, {"body": "<unexpected JSON response>"})
        return decoded


def _load_manifest(manifest_path: Path) -> list[dict[str, object]]:
    text = manifest_path.read_text(encoding="utf-8")
    try:
        import yaml
    except ModuleNotFoundError:
        try:
            document = json.loads(text)
        except json.JSONDecodeError as error:
            raise RuntimeError(
                "PyYAML is required to load a YAML manifest; use the pinned MLflow image."
            ) from error
    else:
        document = yaml.safe_load(text)

    if not isinstance(document, dict) or not isinstance(document.get("endpoints"), list):
        raise ValueError("Manifest must contain an endpoints list.")
    endpoints = document["endpoints"]
    if not all(isinstance(endpoint, dict) for endpoint in endpoints):
        raise ValueError("Every manifest endpoint must be an object.")
    return endpoints


def _is_not_found(error: GatewayHTTPError) -> bool:
    return error.status == 404


def _get_named_secret(client: GatewayClient, name: str) -> dict[str, object] | None:
    # MLflow 3.12.0's get endpoint requires secret_id even though its protocol
    # also exposes secret_name. List metadata and select by name instead.
    response = client.request("GET", f"{API_PREFIX}/gateway/secrets/list")
    matches = [
        item
        for item in response.get("secrets", [])
        if isinstance(item, dict) and item.get("secret_name") == name
    ]
    if len(matches) > 1:
        raise RuntimeError(f"Multiple Gateway secrets are named {name!r}.")
    return matches[0] if matches else None


def _reconcile_secret(client: GatewayClient, provider: str, api_base: str) -> str:
    secret_name = "ollama-local"
    secret_value = {"api_key": "ollama"}
    auth_config = {"api_base": api_base}
    existing = _get_named_secret(client, secret_name)
    if existing is None:
        response = client.request(
            "POST",
            f"{API_PREFIX}/gateway/secrets/create",
            {
                "secret_name": secret_name,
                "secret_value": secret_value,
                "provider": provider,
                "auth_config": auth_config,
            },
        )
        return str(response["secret"]["secret_id"])  # type: ignore[index]

    if existing.get("provider") != provider:
        raise RuntimeError(
            f"Gateway secret {secret_name!r} has provider {existing.get('provider')!r}, "
            f"not {provider!r}; MLflow does not support changing a secret provider in place."
        )
    masked_values = existing.get("masked_values")
    matches = (
        existing.get("auth_config") == auth_config
        and isinstance(masked_values, dict)
        and isinstance(masked_values.get("api_key"), str)
        and bool(masked_values["api_key"])
    )
    if matches:
        return str(existing["secret_id"])

    # Values are intentionally masked by MLflow. A present mask proves the managed
    # key exists but cannot reveal whether its value differs; rotate it only when
    # the observable configuration drifts or MLflow cannot confirm the key exists.
    response = client.request(
        "POST",
        f"{API_PREFIX}/gateway/secrets/update",
        {
            "secret_id": existing["secret_id"],
            "secret_value": secret_value,
            "auth_config": auth_config,
        },
    )
    return str(response["secret"]["secret_id"])  # type: ignore[index]


def _reconcile_model_definition(
    client: GatewayClient, endpoint: dict[str, object], secret_id: str
) -> str:
    name = str(endpoint["name"])
    desired = {
        "name": name,
        "secret_id": secret_id,
        "provider": str(endpoint["provider"]),
        "model_name": str(endpoint["model_name"]),
    }
    listed = client.request("GET", f"{API_PREFIX}/gateway/model-definitions/list")
    matches = [
        item
        for item in listed.get("model_definitions", [])
        if isinstance(item, dict) and item.get("name") == name
    ]
    if len(matches) > 1:
        raise RuntimeError(f"Multiple Gateway model definitions are named {name!r}.")
    if not matches:
        created = client.request("POST", f"{API_PREFIX}/gateway/model-definitions/create", desired)
        return str(created["model_definition"]["model_definition_id"])  # type: ignore[index]

    existing = matches[0]
    if all(existing.get(key) == value for key, value in desired.items()):
        return str(existing["model_definition_id"])

    updated = client.request(
        "POST",
        f"{API_PREFIX}/gateway/model-definitions/update",
        {"model_definition_id": existing["model_definition_id"], **desired},
    )
    return str(updated["model_definition"]["model_definition_id"])  # type: ignore[index]


def _endpoint_matches(endpoint: dict[str, object], model_definition_id: str) -> bool:
    mappings = endpoint.get("model_mappings")
    if endpoint.get("usage_tracking") is not True or not isinstance(mappings, list):
        return False
    if len(mappings) != 1 or not isinstance(mappings[0], dict):
        return False
    mapping = mappings[0]
    return (
        mapping.get("model_definition_id") == model_definition_id
        and mapping.get("linkage_type") == "PRIMARY"
        and mapping.get("weight") == 1.0
    )


def _reconcile_endpoint(
    client: GatewayClient, endpoint: dict[str, object], model_definition_id: str
) -> None:
    name = str(endpoint["name"])
    model_configs = [
        {
            "model_definition_id": model_definition_id,
            "linkage_type": "PRIMARY",
            "weight": 1.0,
        }
    ]
    try:
        existing = client.request(
            "GET", f"{API_PREFIX}/gateway/endpoints/get", {"name": name}
        )["endpoint"]  # type: ignore[assignment]
    except GatewayHTTPError as error:
        if not _is_not_found(error):
            raise
        client.request(
            "POST",
            f"{API_PREFIX}/gateway/endpoints/create",
            {"name": name, "model_configs": model_configs, "usage_tracking": True},
        )
        return

    if not isinstance(existing, dict):
        raise RuntimeError(f"Gateway endpoint {name!r} returned an invalid response.")
    if _endpoint_matches(existing, model_definition_id):
        return
    client.request(
        "POST",
        f"{API_PREFIX}/gateway/endpoints/update",
        {
            "endpoint_id": existing["endpoint_id"],
            "name": name,
            "model_configs": model_configs,
            "usage_tracking": True,
        },
    )


def reconcile_manifest(base_url: str, manifest_path: Path) -> None:
    endpoints = _load_manifest(manifest_path)
    required = {"name", "provider", "model_name", "api_base", "usage_tracking"}
    for endpoint in endpoints:
        missing = required - endpoint.keys()
        if missing:
            raise ValueError(f"Manifest endpoint is missing {sorted(missing)}.")
        if endpoint["provider"] != "ollama" or endpoint["usage_tracking"] is not True:
            raise ValueError("Only usage-tracked Ollama endpoints are supported by this manifest.")
    api_bases = {str(endpoint["api_base"]) for endpoint in endpoints}
    if len(api_bases) != 1:
        raise ValueError("All Ollama endpoints must use one shared api_base.")

    client = GatewayClient(base_url)
    secret_id = _reconcile_secret(client, "ollama", api_bases.pop())
    for endpoint in endpoints:
        model_definition_id = _reconcile_model_definition(client, endpoint, secret_id)
        _reconcile_endpoint(client, endpoint, model_definition_id)


def _gateway_endpoint(client: GatewayClient, name: str) -> dict[str, object]:
    response = client.request("GET", f"{API_PREFIX}/gateway/endpoints/get", {"name": name})
    endpoint = response.get("endpoint")
    if not isinstance(endpoint, dict):
        raise GatewayVerificationError(f"Gateway availability failure: endpoint {name!r} is invalid.")
    return endpoint


def _response_shape(condition: bool, message: str) -> None:
    if not condition:
        raise GatewayVerificationError(f"Gateway response-shape failure: {message}")


def _has_assistant_content(response: dict[str, object]) -> bool:
    choices = response.get("choices")
    if not isinstance(choices, list) or not choices:
        return False
    return all(
        isinstance(choice, dict)
        and isinstance(choice.get("message"), dict)
        and choice["message"].get("role") == "assistant"
        and isinstance(choice["message"].get("content"), str)
        and bool(choice["message"]["content"].strip())
        for choice in choices
    )


def _has_numeric_embeddings(response: dict[str, object]) -> bool:
    data = response.get("data")
    if not isinstance(data, list) or not data:
        return False
    for item in data:
        if not isinstance(item, dict):
            return False
        vector = item.get("embedding")
        if not isinstance(vector, list) or not vector:
            return False
        if not all(
            isinstance(value, (int, float))
            and not isinstance(value, bool)
            and math.isfinite(value)
            for value in vector
        ):
            return False
    return True


def _gateway_call(client: GatewayClient, path: str, payload: dict[str, object]) -> dict[str, object]:
    try:
        return client.request("POST", path, payload)
    except GatewayHTTPError as error:
        if error.status in {502, 504}:
            raise GatewayVerificationError(f"Upstream Ollama failure: {error}") from error
        raise GatewayVerificationError(f"Gateway availability failure: {error}") from error


def _search_trace_endpoint_ids(
    client: GatewayClient, endpoints: dict[str, dict[str, object]], started_at_ms: int
) -> set[str]:
    locations = [
        {"type": "MLFLOW_EXPERIMENT", "mlflow_experiment": {"experiment_id": endpoint["experiment_id"]}}
        for endpoint in endpoints.values()
        if endpoint.get("experiment_id") is not None
    ]
    if len(locations) != len(endpoints):
        raise GatewayVerificationError("Missing traces: a usage-tracked endpoint has no experiment.")
    response = client.request(
        "POST",
        f"{API_PREFIX}/traces/search",
        {"locations": locations, "filter": f"trace.timestamp_ms >= {started_at_ms}", "max_results": 100},
    )
    seen: set[str] = set()
    for trace in response.get("traces", []):
        if not isinstance(trace, dict):
            continue
        metadata = trace.get("trace_metadata")
        if isinstance(metadata, list):
            for entry in metadata:
                if (
                    isinstance(entry, dict)
                    and entry.get("key") == "mlflow.gateway.endpointId"
                    and isinstance(entry.get("value"), str)
                ):
                    seen.add(entry["value"])
        elif isinstance(metadata, dict):
            endpoint_id = metadata.get("mlflow.gateway.endpointId")
            if isinstance(endpoint_id, str):
                seen.add(endpoint_id)
    return seen


def verify_gateway(
    base_url: str, chat_endpoint: str, embedding_endpoint: str, experiment_name: str
) -> None:
    client = GatewayClient(base_url)
    try:
        endpoints = {
            chat_endpoint: _gateway_endpoint(client, chat_endpoint),
            embedding_endpoint: _gateway_endpoint(client, embedding_endpoint),
        }
    except GatewayHTTPError as error:
        raise GatewayVerificationError(f"Gateway availability failure: {error}") from error

    started_at_ms = int(time() * 1000)
    chat = _gateway_call(
        client,
        "/gateway/mlflow/v1/chat/completions",
        {
            "model": chat_endpoint,
            "messages": [{"role": "user", "content": "Reply with OK."}],
            "max_tokens": 512,
            "temperature": 0,
        },
    )
    _response_shape(
        _has_assistant_content(chat),
        "chat completion has no assistant message content.",
    )
    embeddings = _gateway_call(
        client,
        "/gateway/openai/v1/embeddings",
        {"model": embedding_endpoint, "input": "mlflow gateway verification"},
    )
    _response_shape(
        _has_numeric_embeddings(embeddings),
        "embedding response has no numeric vectors.",
    )

    required_ids = {str(endpoint["endpoint_id"]) for endpoint in endpoints.values()}
    for attempt in range(10):
        try:
            seen_ids = _search_trace_endpoint_ids(client, endpoints, started_at_ms)
        except GatewayHTTPError as error:
            raise GatewayVerificationError(f"Gateway availability failure: {error}") from error
        if required_ids <= seen_ids:
            return
        if attempt < 9:
            from time import sleep

            sleep(1)
    missing = [name for name, endpoint in endpoints.items() if str(endpoint["endpoint_id"]) not in seen_ids]
    raise GatewayVerificationError(
        f"Missing traces for {', '.join(missing)} in {experiment_name!r}."
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Reconcile MLflow Gateway endpoints.")
    parser.add_argument("--base-url", default="http://127.0.0.1:5000")
    parser.add_argument("--manifest", type=Path, default=Path(__file__).with_name("endpoints.yml"))
    args = parser.parse_args()
    reconcile_manifest(args.base_url, args.manifest)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (GatewayHTTPError, RuntimeError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
