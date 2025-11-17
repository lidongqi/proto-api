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
  command -v protoc-gen-grpc-gateway >/dev/null 2>&1 || missing+=("github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway@latest")
  command -v protoc-gen-openapiv2 >/dev/null 2>&1 || missing+=("github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2@latest")

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

  find "$OUT_DIR" -type f -name '*_http.pb.go' -delete || true

  echo "Generating Go types, gRPC, and gRPC-Gateway..."
  protoc -I "$ROOT_DIR" -I "$THIRD_PARTY_DIR" \
    --go_out="$OUT_DIR" --go_opt=paths=source_relative \
    --go-grpc_out="$OUT_DIR" --go-grpc_opt=paths=source_relative \
    --grpc-gateway_out="$OUT_DIR" --grpc-gateway_opt=paths=source_relative,generate_unbound_methods=true \
    $PROTO_FILES

  echo "Generating OpenAPI JSON via grpc-gateway openapiv2 plugin..."
  protoc -I "$ROOT_DIR" -I "$THIRD_PARTY_DIR" \
    --openapiv2_out=logtostderr=true,allow_merge=true,merge_file_name=openapi.json,disable_default_errors=true:"$OPENAPI_DIR" \
    $PROTO_FILES

  echo "Done. Outputs:"
  echo "  Go code:   $OUT_DIR"
  echo "  OpenAPI:   $OPENAPI_DIR (openapi.json)"
}

main "$@"