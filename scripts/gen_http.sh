#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR=${OUT_DIR:-"$ROOT_DIR/gen"}
OPENAPI_DIR=${OPENAPI_DIR:-"$ROOT_DIR/openapi"}
THIRD_PARTY_DIR="$ROOT_DIR/third_party"
GOOGLE_API_DIR="$THIRD_PARTY_DIR/google/api"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing command: $1" >&2
    return 1
  fi
}

ensure_google_api() {
  mkdir -p "$GOOGLE_API_DIR"
  if [ ! -f "$GOOGLE_API_DIR/annotations.proto" ]; then
    echo "Downloading google/api/annotations.proto..."
    curl -fsSL -o "$GOOGLE_API_DIR/annotations.proto" \
      https://raw.githubusercontent.com/googleapis/googleapis/master/google/api/annotations.proto
  fi
  if [ ! -f "$GOOGLE_API_DIR/http.proto" ]; then
    echo "Downloading google/api/http.proto..."
    curl -fsSL -o "$GOOGLE_API_DIR/http.proto" \
      https://raw.githubusercontent.com/googleapis/googleapis/master/google/api/http.proto
  fi
}

main() {
  need_cmd protoc || {
    echo "Install protoc first (e.g., brew install protobuf)" >&2
    exit 1
  }
  # Optional plugins; we check and hint if missing
  missing=()
  command -v protoc-gen-go >/dev/null 2>&1 || missing+=("google.golang.org/protobuf/cmd/protoc-gen-go@latest")
  command -v protoc-gen-go-grpc >/dev/null 2>&1 || missing+=("google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest")
  command -v protoc-gen-go-http >/dev/null 2>&1 || missing+=("github.com/go-kratos/kratos/cmd/protoc-gen-go-http@latest")
  command -v protoc-gen-openapi >/dev/null 2>&1 || missing+=("github.com/google/gnostic/cmd/protoc-gen-openapi@latest")

  if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing protoc plugins:" >&2
    for m in "${missing[@]}"; do
      echo "  go install $m" >&2
    done
    echo "Run the above go install commands, then re-run this script." >&2
    exit 1
  fi

  ensure_google_api

  mkdir -p "$OUT_DIR" "$OPENAPI_DIR"

  # Collect proto files from api/ and common/ (compatible with macOS bash 3.2)
  PROTO_FILES=$(find "$ROOT_DIR/api" "$ROOT_DIR/common" -type f -name '*.proto')
  if [ -z "$PROTO_FILES" ]; then
    echo "No proto files found under api/ or common/" >&2
    exit 1
  fi

  echo "Generating Go types, gRPC, and Kratos HTTP..."
  protoc -I "$ROOT_DIR" -I "$THIRD_PARTY_DIR" \
    --go_out="$OUT_DIR" --go_opt=paths=source_relative \
    --go-grpc_out="$OUT_DIR" --go-grpc_opt=paths=source_relative \
    --go-http_out="$OUT_DIR" --go-http_opt=paths=source_relative \
    $PROTO_FILES

  echo "Generating OpenAPI YAML via gnostic plugin..."
  protoc -I "$ROOT_DIR" -I "$THIRD_PARTY_DIR" \
    --openapi_out=fq_schema_naming=true,default_response=false:"$OPENAPI_DIR" \
    $PROTO_FILES

  echo "Done. Outputs:"
  echo "  Go code:   $OUT_DIR"
  echo "  OpenAPI:   $OPENAPI_DIR (openapi.yaml files)"
}

main "$@"