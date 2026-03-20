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

    stage('Checkout Source') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

banner() {
  printf '\\n========== %s ==========%s' "$1" "\\n"
}

source_repo_url="${ADD_EMPLOYEE_SOURCE_REPO_URL:-http://host.docker.internal:3000/myuser/playground.git}"
source_branch="${ADD_EMPLOYEE_SOURCE_BRANCH:-${ADD_EMPLOYEE_PIPELINE_BRANCH:-main}}"

banner "Prepare Workspace"
rm -rf playground

banner "Clone Source Repository"
echo "Cloning source repository ${source_repo_url} (branch ${source_branch})"
git clone --depth 1 --branch "$source_branch" "$source_repo_url" playground

banner "Validate Source Layout"
if [[ ! -f playground/api/example-client/company.py ]]; then
  echo "Expected playground/api/example-client/company.py after checkout"
  exit 1
fi

banner "Validate Example Client CLI"
if ! (cd playground/api && example-client/company.py employee add --help 2>&1 | grep -q -- '--employee-role'); then
  echo "The checked-out source at ${source_repo_url} branch ${source_branch} does not provide role-based add-employee support in api/example-client/company.py."
  echo "Push the updated source to that branch or override ADD_EMPLOYEE_SOURCE_REPO_URL / ADD_EMPLOYEE_SOURCE_BRANCH."
  exit 1
fi
'''
      }
    }

    stage('Add Employee') {
      steps {
        script {
          def rolesUrl = (env.ADD_EMPLOYEE_FASTAPI_ROLES_URL ?: '').trim()
          if (!rolesUrl) {
            rolesUrl = 'http://host.docker.internal:8000/roles'
          }

          def graphqlUrl = (env.ADD_EMPLOYEE_GRAPHQL_URL ?: '').trim()
          if (!graphqlUrl) {
            graphqlUrl = rolesUrl.endsWith('/roles')
              ? "${rolesUrl[0..-7]}/graphql"
              : "${rolesUrl.replaceFirst('/+$', '')}/graphql"
          }
          def fastapiBasicAuthUser = (env.FASTAPI_BASIC_AUTH_USERNAME ?: 'admin').trim()
          def fastapiBasicAuthPassword = env.FASTAPI_BASIC_AUTH_PASSWORD ?: 'password'

          withEnv([
            "EFFECTIVE_ADD_EMPLOYEE_FASTAPI_ROLES_URL=${rolesUrl}",
            "EFFECTIVE_ADD_EMPLOYEE_GRAPHQL_URL=${graphqlUrl}",
            "FASTAPI_BASIC_AUTH_USERNAME=${fastapiBasicAuthUser}",
            "FASTAPI_BASIC_AUTH_PASSWORD=${fastapiBasicAuthPassword}",
          ]) {
            sh '''#!/usr/bin/env bash
set -euo pipefail

banner() {
  printf '\\n========== %s ==========%s' "$1" "\\n"
}

source .nexus.env

export FASTAPI_BASIC_AUTH_USERNAME="${FASTAPI_BASIC_AUTH_USERNAME:-admin}"
export FASTAPI_BASIC_AUTH_PASSWORD="${FASTAPI_BASIC_AUTH_PASSWORD:-password}"

employee_name="${EMPLOYEE_NAME:-}"
employee_surname="${EMPLOYEE_SURNAME:-}"
employee_role="${EMPLOYEE_ROLE:-}"
roles_url="${EFFECTIVE_ADD_EMPLOYEE_FASTAPI_ROLES_URL}"
graphql_url="${EFFECTIVE_ADD_EMPLOYEE_GRAPHQL_URL}"

banner "Validate Build Parameters"
if [[ -z "$employee_name" ]]; then
  echo "EMPLOYEE_NAME is required."
  exit 1
fi
if [[ -z "$employee_surname" ]]; then
  echo "EMPLOYEE_SURNAME is required."
  exit 1
fi
if [[ -z "$employee_role" ]]; then
  echo "EMPLOYEE_ROLE is required."
  exit 1
fi
echo "Using employee: ${employee_name} ${employee_surname}"
echo "Using role: ${employee_role}"
echo "Using GraphQL endpoint: ${graphql_url}"

banner "Prepare Example Client Environment"

cd playground
rm -rf .venv-add-employee
python3 -m venv .venv-add-employee
source .venv-add-employee/bin/activate

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

FORCE_COLOR=1 COMPANY_CLIENT_DISABLE_LOCAL_BOOTSTRAP=1 python api/example-client/company.py \
  --graphql-url "$graphql_url" \
  employee add \
  --employee-name "$employee_name" \
  --employee-surname "$employee_surname" \
  --employee-role "$employee_role"
'''
          }
        }
      }
    }
  }

  post {
    always {
      sh '''#!/usr/bin/env bash
printf "\\n========== Cleanup ==========\n"
rm -f .nexus.env /tmp/nexus-create.out /tmp/nexus-pypi-health.out || true
rm -rf playground/.venv-add-employee || true
'''
    }
  }
}
