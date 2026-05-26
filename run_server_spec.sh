#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$BASE_DIR/output"
IMAGE_VERSION="1.0"
echo "======================================"
echo "1. Run Ansible server spec playbook"
echo "======================================"
cd "$BASE_DIR"
ansible-playbook -i inventory server-spec-playbook.yml

echo "======================================"
echo "2. Build Excel generator Docker image"
echo "======================================"

cd "$OUTPUT_DIR"
docker build -f server_spec.Dockerfile -t server-spec-excel:"$IMAGE_VERSION" .

echo "======================================"
echo "3. Generate Excel from JSON files"
echo "======================================"

docker run --rm \
  -v "$OUTPUT_DIR":/app \
  server-spec-excel:"$IMAGE_VERSION"
docker rmi server-spec-excel:"$IMAGE_VERSION" 

echo "======================================"
echo "4. Clean JSON files"
echo "======================================"

echo "PWD=$(pwd)"
echo "OUTPUT_DIR=$OUTPUT_DIR"
echo "DELETE_TARGET=$OUTPUT_DIR/json/*.json"

ls -lh "$OUTPUT_DIR"/json/*.json

rm -fv "$OUTPUT_DIR"/json/*.json

echo "After delete:"
ls -lh "$OUTPUT_DIR"/json || true

echo "======================================"
echo "5. Done"
echo "======================================"
ls -lh "$OUTPUT_DIR"/xlsx/*.xlsx
echo "Done"
