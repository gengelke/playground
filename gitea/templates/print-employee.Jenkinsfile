pipeline {
  agent any
  stages {
    stage('Print Selected Employee') {
      steps {
        script {
          def graphqlUrl = (env.PRINT_EMPLOYEE_GRAPHQL_URL ?: '').trim()
          if (!graphqlUrl) {
            graphqlUrl = 'http://host.docker.internal:8000/graphql'
          }
          def fastapiBasicAuthUser = (env.FASTAPI_BASIC_AUTH_USERNAME ?: 'admin').trim()
          def fastapiBasicAuthPassword = env.FASTAPI_BASIC_AUTH_PASSWORD ?: 'password'

          withEnv([
            "EFFECTIVE_PRINT_EMPLOYEE_GRAPHQL_URL=${graphqlUrl}",
            "FASTAPI_BASIC_AUTH_USERNAME=${fastapiBasicAuthUser}",
            "FASTAPI_BASIC_AUTH_PASSWORD=${fastapiBasicAuthPassword}",
          ]) {
            sh '''#!/usr/bin/env bash
set -euo pipefail

banner() {
  printf '\\n========== %s ==========%s' "$1" "\\n"
}

selection="${EMPLOYEE_SELECTION:-}"
graphql_url="${EFFECTIVE_PRINT_EMPLOYEE_GRAPHQL_URL}"
auth_user="${FASTAPI_BASIC_AUTH_USERNAME:-admin}"
auth_password="${FASTAPI_BASIC_AUTH_PASSWORD:-password}"

banner "Validate Build Parameters"
if [[ -z "$selection" ]]; then
  echo "EMPLOYEE_SELECTION is required."
  exit 1
fi

employee_id="$(printf '%s' "$selection" | sed -nE 's/^([0-9]+).*/\\1/p')"
if [[ -z "$employee_id" ]]; then
  echo "EMPLOYEE_SELECTION must start with a numeric employee id."
  echo "Received: $selection"
  exit 1
fi

echo "Using GraphQL endpoint: ${graphql_url}"
echo "Selected employee entry: ${selection}"

banner "Fetch Employees From GraphQL"
graphql_payload="$(python3 - <<'PY'
import json

print(json.dumps({
    "query": """
      query JenkinsEmployeeSelection {
        employees {
          employeeId
          name
          surname
          role
        }
      }
    """
}))
PY
)"

graphql_response="$(curl -fsS \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  -u "${auth_user}:${auth_password}" \
  --data "$graphql_payload" \
  "$graphql_url")"

export GRAPHQL_RESPONSE="$graphql_response"
export SELECTED_EMPLOYEE_ID="$employee_id"

banner "Print Employee Data"
python3 - <<'PY'
import json
import os
import sys

response = json.loads(os.environ["GRAPHQL_RESPONSE"])
errors = response.get("errors") or []
if errors:
    print("GraphQL returned errors:", file=sys.stderr)
    print(json.dumps(errors, indent=2), file=sys.stderr)
    raise SystemExit(1)

employees = response.get("data", {}).get("employees") or []
selected_id = int(os.environ["SELECTED_EMPLOYEE_ID"])
employee = next((item for item in employees if item.get("employeeId") == selected_id), None)

if employee is None:
    print(f"Employee {selected_id} was not found in the GraphQL response.", file=sys.stderr)
    raise SystemExit(1)

print(json.dumps(employee, indent=2, sort_keys=True))
PY
'''
          }
        }
      }
    }
  }
}
