pipeline {
  agent any
  stages {
    stage('Checkout Source') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

banner() {
  printf '\\n========== %s ==========%s' "$1" "\\n"
}

source_repo_url="${ADD_EMPLOYEE_SOURCE_REPO_URL:-https://github.com/gengelke/playground.git}"
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
if ! (cd playground/api && example-client/company.py add-employee --help 2>&1 | grep -q -- '--employee-role'); then
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

          withEnv([
            "EFFECTIVE_ADD_EMPLOYEE_FASTAPI_ROLES_URL=${rolesUrl}",
            "EFFECTIVE_ADD_EMPLOYEE_GRAPHQL_URL=${graphqlUrl}",
          ]) {
            sh '''#!/usr/bin/env bash
set -euo pipefail

banner() {
  printf '\\n========== %s ==========%s' "$1" "\\n"
}

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

banner "Run Example Client"
cd playground/api
FORCE_COLOR=1 example-client/company.py \
  --graphql-url "$graphql_url" \
  add-employee \
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
'''
    }
  }
}
