from __future__ import annotations

import argparse
import sys

from configure import GatewayHTTPError, GatewayVerificationError, verify_gateway


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe MLflow Gateway chat, embeddings, and traces.")
    parser.add_argument("--base-url", default="http://127.0.0.1:5000")
    parser.add_argument("--chat-endpoint", default="ollama-chat-default")
    parser.add_argument("--embedding-endpoint", default="ollama-embedding-default")
    parser.add_argument("--experiment-name", default="gateway/ollama-chat-default")
    args = parser.parse_args()
    verify_gateway(args.base_url, args.chat_endpoint, args.embedding_endpoint, args.experiment_name)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (GatewayHTTPError, GatewayVerificationError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
