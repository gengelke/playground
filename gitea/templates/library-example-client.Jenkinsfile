pipeline {
  agent any
  stages {
    stage('Resolve Nexus Credentials from Vault') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

banner() {
  printf '\\n========== %s ==========%s' "$1" "\\n"
}

vault_addr="${VAULT_ADDR:-http://host.docker.internal:8200}"
vault_token="${VAULT_TOKEN:-}"
pypi_repo="${NEXUS_PYPI_REPO:-pypi-public}"

banner "Fetch Nexus Credentials From Vault"

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

banner "Write Resolved Nexus Environment"

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

    stage('Checkout Example Client Source') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

banner() {
  printf '\\n========== %s ==========%s' "$1" "\\n"
}

source_repo_url="${LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL:-https://github.com/gengelke/playground.git}"
source_branch="${LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH:-${LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH:-main}}"

banner "Prepare Workspace"

rm -rf playground

banner "Clone Source Repository"
echo "Cloning source repository ${source_repo_url} (branch ${source_branch})"
git clone --depth 1 --branch "$source_branch" "$source_repo_url" playground

banner "Validate Example Client Source"

if [[ ! -f playground/api/example-client/company.py ]]; then
  echo "Expected playground/api/example-client/company.py after checkout"
  exit 1
fi

banner "Validate Example Client CLI"
if ! (cd playground/api && example-client/company.py workflow --help >/dev/null 2>&1); then
  echo "The checked-out source at ${source_repo_url} branch ${source_branch} does not provide the workflow command in api/example-client/company.py."
  echo "Push the updated source to that branch or override LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL / LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH."
  exit 1
fi
'''
      }
    }

    stage('Start FastAPI Service') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

banner() {
  printf '\\n========== %s ==========%s' "$1" "\\n"
}

banner "Start FastAPI In Bare Mode"

cd playground/api
make up MODE=bare
'''
      }
    }

    stage('Install Package And Run Example Client') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

banner() {
  printf '\\n========== %s ==========%s' "$1" "\\n"
}

source .nexus.env

banner "Prepare Example Client Environment"

cd playground
rm -rf .venv-library-example-client
python3 -m venv .venv-library-example-client
source .venv-library-example-client/bin/activate

unset SSL_CERT_FILE
unset REQUESTS_CA_BUNDLE
unset CURL_CA_BUNDLE

python -m pip install --upgrade pip

nexus_simple_url="${NEXUS_URL%/}/repository/${NEXUS_PYPI_REPO}/simple"
nexus_host="$(printf '%s' "${NEXUS_URL}" | sed -E 's#^[a-zA-Z]+://([^/:]+).*#\\1#')"
package_spec="fastapi-graphql-client${FASTAPI_GRAPHQL_CLIENT_VERSION:+==${FASTAPI_GRAPHQL_CLIENT_VERSION}}"

banner "Install Package From Nexus"

pip install \
  --index-url https://pypi.org/simple \
  --extra-index-url "${nexus_simple_url}" \
  --trusted-host "${nexus_host}" \
  "$package_spec"

banner "Print Installed Package Version"

python - <<'PY'
from importlib.metadata import version

print(f"Installed fastapi-graphql-client {version('fastapi-graphql-client')}")
PY

banner "Run Example Client"

FORCE_COLOR=1 python api/example-client/company.py \
  --graphql-url "${LIBRARY_EXAMPLE_CLIENT_GRAPHQL_URL:-http://127.0.0.1:8000/graphql}" \
  workflow
'''
      }
    }
  }

  post {
    always {
      sh '''#!/usr/bin/env bash
printf "\\n========== Cleanup ==========\n"
if [[ -d playground/api ]]; then
  make -C playground/api down MODE=bare >/dev/null 2>&1 || true
fi
rm -f .nexus.env /tmp/nexus-create.out /tmp/nexus-pypi-health.out || true
rm -rf playground/.venv-library-example-client || true
'''
    }
  }
}
