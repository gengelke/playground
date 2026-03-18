import groovy.json.JsonOutput
import groovy.json.JsonSlurperClassic

def graphqlUrl = binding.hasVariable('GRAPHQL_URL') ? binding.getVariable('GRAPHQL_URL')?.toString()?.trim() : ''
if (!graphqlUrl) {
  graphqlUrl = System.getenv('EMPLOYEE_SELECTION_GRAPHQL_URL') ?:
    System.getenv('PRINT_EMPLOYEE_GRAPHQL_URL') ?:
    'http://host.docker.internal:8000/graphql'
}

def requestBody = JsonOutput.toJson([
  query: '''
    query JenkinsEmployeeSelection {
      employees {
        employeeId
        name
        surname
        role
      }
    }
  '''
])

def connection = new URL(graphqlUrl).openConnection()
connection.setRequestMethod('POST')
connection.setDoOutput(true)
connection.setConnectTimeout(5000)
connection.setReadTimeout(5000)
connection.setRequestProperty('Accept', 'application/json')
connection.setRequestProperty('Content-Type', 'application/json')
connection.outputStream.withCloseable { output ->
  output.write(requestBody.getBytes('UTF-8'))
}

def payload = connection.inputStream.withCloseable { it.getText('UTF-8') }
def parsed = new JsonSlurperClassic().parseText(payload)
def employees = parsed?.data?.employees instanceof List ? parsed.data.employees : []
def choices = employees.collect { employee ->
  def employeeId = employee?.employeeId
  def name = employee?.name ?: ''
  def surname = employee?.surname ?: ''
  def role = employee?.role ?: ''
  employeeId == null ? null : "${employeeId} - ${name} ${surname} (${role})"
}.findAll { it }

return choices ?: ['No employees found']
