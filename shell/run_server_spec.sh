#!/bin/bash
set -e

cd ..
BASE_DIR="$(pwd)"

ansible-playbook -i "$BASE_DIR/inventory/hosts.yml" "$BASE_DIR/server-spec-playbook.yml"
