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

    stage('Start FastAPI Service') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

banner() {
  printf '\\n========== %s ==========%s' "$1" "\\n"
}

banner "Start FastAPI In Bare Mode"
make -C playground/api up MODE=bare
'''
      }
    }

    stage('Add Employee') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail

banner() {
  printf '\\n========== %s ==========%s' "$1" "\\n"
}

employee_role="${EMPLOYEE_ROLE:-}"
graphql_url="${ADD_EMPLOYEE_GRAPHQL_URL:-http://127.0.0.1:8000/graphql}"

banner "Validate Selected Role"
if [[ -z "$employee_role" ]]; then
  echo "EMPLOYEE_ROLE is required."
  exit 1
fi
echo "Using role: ${employee_role}"

banner "Run Example Client"
cd playground/api
FORCE_COLOR=1 example-client/company.py \
  --graphql-url "$graphql_url" \
  add-employee \
  --employee-name Hans \
  --employee-surname Wurst \
  --employee-role "$employee_role"
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
'''
    }
  }
}
