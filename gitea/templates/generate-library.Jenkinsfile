pipeline {
  agent any
  stages {
    stage('Resolve Nexus Credentials from Vault') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

vault_addr="${VAULT_ADDR:-http://host.docker.internal:8200}"
vault_token="${VAULT_TOKEN:-}"
pypi_repo="${NEXUS_PYPI_REPO:-pypi-public}"

if [[ -z "$vault_token" ]]; then
  echo "VAULT_TOKEN is required for Vault authentication."
  exit 1
fi

vault_response="$(curl -fsS -H "X-Vault-Token: ${vault_token}" "${vault_addr%/}/v1/secret/data/services/nexus")"
nexus_url="$(printf '%s' "$vault_response" | jq -r '.data.data.url // empty')"
nexus_user="$(printf '%s' "$vault_response" | jq -r '.data.data.admin_user // empty')"
nexus_password="$(printf '%s' "$vault_response" | jq -r '.data.data.admin_password // empty')"

if [[ -z "$nexus_url" || -z "$nexus_user" || -z "$nexus_password" ]]; then
  echo "Failed to extract Nexus credentials from Vault path secret/data/services/nexus"
  exit 1
fi

nexus_url="$(printf '%s' "$nexus_url" | sed \
  -e 's#http://localhost#http://host.docker.internal#g' \
  -e 's#http://127.0.0.1#http://host.docker.internal#g' \
  -e 's#https://localhost#https://host.docker.internal#g' \
  -e 's#https://127.0.0.1#https://host.docker.internal#g')"

{
  echo "NEXUS_URL=${nexus_url}"
  echo "NEXUS_USER=${nexus_user}"
  echo "NEXUS_PASSWORD=${nexus_password}"
  echo "NEXUS_PYPI_REPO=${pypi_repo}"
} > .nexus.env
chmod 600 .nexus.env
'''
      }
    }

    stage('Ensure Nexus PyPI Repository') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail
source .nexus.env

repos_json="$(curl -fsS -u "${NEXUS_USER}:${NEXUS_PASSWORD}" "${NEXUS_URL%/}/service/rest/v1/repositories")"
if ! printf '%s' "$repos_json" | jq -e --arg repo "$NEXUS_PYPI_REPO" '.[] | select(.name == $repo)' >/dev/null; then
  create_payload="$(jq -nc --arg name "$NEXUS_PYPI_REPO" '{name:$name,online:true,storage:{blobStoreName:"default",strictContentTypeValidation:true,writePolicy:"ALLOW"}}')"
  create_status="$(curl -sS -o /tmp/nexus-create.out -w '%{http_code}' \
    -u "${NEXUS_USER}:${NEXUS_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -X POST \
    --data "$create_payload" \
    "${NEXUS_URL%/}/service/rest/v1/repositories/pypi/hosted" || true)"
  if [[ "$create_status" != "201" && "$create_status" != "204" && "$create_status" != "400" && "$create_status" != "409" ]]; then
    cat /tmp/nexus-create.out
    exit 1
  fi
fi
'''
      }
    }

    stage('Generate API Client') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

source_repo_url="${GENERATE_LIBRARY_SOURCE_REPO_URL:-https://github.com/gengelke/playground.git}"
source_branch="${GENERATE_LIBRARY_SOURCE_BRANCH:-${GENERATE_LIBRARY_PIPELINE_BRANCH:-main}}"

rm -rf playground

echo "Cloning source repository ${source_repo_url} (branch ${source_branch})"
git clone --depth 1 --branch "$source_branch" "$source_repo_url" playground
cd playground/api

if ! grep -Eq '(^|[[:space:]])library-generate([[:space:]:]|$)' Makefile; then
  echo "The checked-out source at ${source_repo_url} branch ${source_branch} does not provide 'make library-generate'."
  echo "Push the updated api/Makefile to that branch or override GENERATE_LIBRARY_SOURCE_REPO_URL / GENERATE_LIBRARY_SOURCE_BRANCH for Jenkins."
  exit 1
fi

make library-generate MODE=docker

if [[ ! -d graphql-library/generated/fastapi_graphql_client ]]; then
  echo "Expected graphql-library/generated/fastapi_graphql_client after library generation"
  exit 1
fi
'''
      }
    }

    stage('Build And Upload Package') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail
source .nexus.env

cd playground/api/graphql-library

if [[ ! -x .venv-build/bin/python3 ]]; then
  python3 -m venv .venv-build
fi

source .venv-build/bin/activate
pip install --upgrade pip build twine

python3 - "${BUILD_NUMBER:-}" <<'PY'
import datetime
import pathlib
import re
import sys

build_number = sys.argv[1].strip() if len(sys.argv) > 1 else ""
if not build_number:
    build_number = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")

pyproject = pathlib.Path("pyproject.toml")
content = pyproject.read_text()
match = re.search(r'^version = "([^"]+)"', content, re.MULTILINE)
if not match:
    raise SystemExit("Could not determine package version from pyproject.toml")

new_version = f'{match.group(1)}.post{build_number}'
updated = re.sub(
    r'^version = "[^"]+"',
    f'version = "{new_version}"',
    content,
    count=1,
    flags=re.MULTILINE,
)
pyproject.write_text(updated)
pathlib.Path(".package-version").write_text(f"{new_version}\\n")
print(f"Using package version {new_version}")
PY

python3 -m build

upload_url="${NEXUS_URL%/}/repository/${NEXUS_PYPI_REPO}/"

wait_attempts=24
for attempt in $(seq 1 "$wait_attempts"); do
  health_status="$(curl -sS -o /tmp/nexus-pypi-health.out -w '%{http_code}' \
    -u "${NEXUS_USER}:${NEXUS_PASSWORD}" \
    "$upload_url" || true)"
  if [[ "$health_status" == "200" ]]; then
    break
  fi
  if [[ "$attempt" -eq "$wait_attempts" ]]; then
    echo "Nexus PyPI endpoint is not ready at ${upload_url} (last HTTP ${health_status:-n/a})"
    cat /tmp/nexus-pypi-health.out || true
    exit 1
  fi
  echo "Waiting for Nexus PyPI endpoint ${upload_url} (HTTP ${health_status:-n/a}, attempt ${attempt}/${wait_attempts})"
  sleep 5
done

upload_attempts=6
for attempt in $(seq 1 "$upload_attempts"); do
  if twine upload \
    --non-interactive \
    --verbose \
    --repository-url "$upload_url" \
    -u "${NEXUS_USER}" \
    -p "${NEXUS_PASSWORD}" \
    dist/*; then
    break
  fi

  if [[ "$attempt" -eq "$upload_attempts" ]]; then
    echo "Twine upload failed after ${upload_attempts} attempts."
    exit 1
  fi
  echo "Twine upload attempt ${attempt}/${upload_attempts} failed; retrying in 10s."
  sleep 10
done
'''
      }
    }

    stage('Verify Uploaded Package') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail
source .nexus.env

cd playground/api/graphql-library

rm -rf .venv-verify/
python3 -m venv .venv-verify
source .venv-verify/bin/activate

unset SSL_CERT_FILE
unset REQUESTS_CA_BUNDLE
unset CURL_CA_BUNDLE

package_version="$(cat .package-version)"
nexus_simple_url="${NEXUS_URL%/}/repository/${NEXUS_PYPI_REPO}/simple"
nexus_host="$(printf '%s' "${NEXUS_URL}" | sed -E 's#^[a-zA-Z]+://([^/:]+).*#\\1#')"

pip install \
  --index-url https://pypi.org/simple \
  --extra-index-url "${nexus_simple_url}" \
  --trusted-host "${nexus_host}" \
  "fastapi-graphql-client==${package_version}"

python - <<'PY'
import fastapi_graphql_client

print(f"Imported package version from {fastapi_graphql_client.__file__}")
PY
'''
      }
    }
  }

  post {
    always {
      sh 'rm -f .nexus.env /tmp/nexus-create.out /tmp/nexus-pypi-health.out playground/api/graphql-library/.package-version || true'
    }
  }
}
