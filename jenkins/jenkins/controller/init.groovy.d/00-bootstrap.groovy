import hudson.model.Node
import hudson.model.BuildAuthorizationToken
import hudson.model.User
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.HudsonPrivateSecurityRealm.Details
import hudson.security.csrf.DefaultCrumbIssuer
import hudson.slaves.DumbSlave
import hudson.slaves.JNLPLauncher
import hudson.slaves.RetentionStrategy
import jenkins.model.Jenkins

import java.util.LinkedList

def env = System.getenv()
def jenkins = Jenkins.get()

def instanceName = env.getOrDefault("JENKINS_INSTANCE_NAME", "jenkins")
def pipelineRepoUrl = env.getOrDefault("PIPELINE_REPO_URL", "https://github.com/example/jenkins-pipelines.git")
def pipelineBranch = env.getOrDefault("PIPELINE_BRANCH", "main")
def pipelineScriptPath = env.getOrDefault("PIPELINE_SCRIPT_PATH", "Jenkinsfile")
def pipelineJobName = env.getOrDefault("PIPELINE_JOB_NAME", "example-pipeline")
def pipelineAuthToken = env.getOrDefault("PIPELINE_AUTH_TOKEN", "example-pipeline-auth-token")
def pipelineGitCredentialsId = env.getOrDefault("PIPELINE_GIT_CREDENTIALS_ID", "").trim()
def pipelineGitUsername = env.getOrDefault("PIPELINE_GIT_USERNAME", "").trim()
def pipelineGitPassword = env.getOrDefault("PIPELINE_GIT_PASSWORD", "")
def agentCount = (env.getOrDefault("AGENT_COUNT", "2") as Integer)
def agentExecutors = (env.getOrDefault("AGENT_EXECUTORS", "1") as Integer)
def agentRemoteFs = env.getOrDefault("AGENT_REMOTE_FS", "/home/jenkins/agent")
def adminUser = env.getOrDefault("JENKINS_ADMIN_USER", "admin")
def adminPassword = env.getOrDefault("JENKINS_ADMIN_PASSWORD", "password")
def regularUser = env.getOrDefault("JENKINS_REGULAR_USER", "user")
def regularPassword = env.getOrDefault("JENKINS_REGULAR_PASSWORD", "password")
def managedDescription = "Managed by repository automation"

println("[bootstrap] configuring ${instanceName}")

def optionalClass = { String className ->
  try {
    return jenkins.pluginManager.uberClassLoader.loadClass(className)
  } catch (ClassNotFoundException ignored) {
    return null
  }
}

def stripUserInfo = { String repoUrl ->
  repoUrl?.replaceFirst("://[^/@]+@", "://")
}

def maskUserInfo = { String repoUrl ->
  repoUrl?.replaceFirst("://[^/@]+@", "://****@")
}

if (!adminPassword?.trim()) {
  throw new IllegalStateException("JENKINS_ADMIN_PASSWORD is required for bootstrap")
}

def securityRealm = jenkins.getSecurityRealm()
if (!(securityRealm instanceof HudsonPrivateSecurityRealm)) {
  securityRealm = new HudsonPrivateSecurityRealm(false, false, null)
}

def ensureManagedAccount = { String username, String password, String label ->
  if (!username?.trim() || !password?.trim()) {
    return
  }

  if (securityRealm.getUser(username) == null) {
    securityRealm.createAccount(username, password)
    println("[bootstrap] created ${label} user ${username}")
    return
  }

  def managedUser = User.getById(username, false)
  if (managedUser != null) {
    managedUser.addProperty(Details.fromPlainPassword(password))
    managedUser.save()
    println("[bootstrap] synced ${label} password for ${username}")
  }
}

ensureManagedAccount(adminUser, adminPassword, "admin")
if (regularUser?.trim() && regularPassword?.trim() && regularUser != adminUser) {
  ensureManagedAccount(regularUser, regularPassword, "regular")
}

jenkins.setSecurityRealm(securityRealm)

def authStrategy = new FullControlOnceLoggedInAuthorizationStrategy()
authStrategy.setAllowAnonymousRead(false)
jenkins.setAuthorizationStrategy(authStrategy)
jenkins.setCrumbIssuer(new DefaultCrumbIssuer(true))
jenkins.setNumExecutors(0)

Set<String> desiredNodeNames = new LinkedHashSet<>()
(1..agentCount).each { index ->
  def nodeName = "${instanceName}-agent-${index}".toString()
  desiredNodeNames << nodeName

  if (jenkins.getNode(nodeName) == null) {
    def node = new DumbSlave(
      nodeName,
      "${managedDescription} (${instanceName})",
      agentRemoteFs,
      "${agentExecutors}",
      Node.Mode.NORMAL,
      "${instanceName} linux",
      new JNLPLauncher(),
      RetentionStrategy.Always.INSTANCE,
      new LinkedList<>()
    )
    jenkins.addNode(node)
    println("[bootstrap] created node ${nodeName}")
  }
}

jenkins.getNodes()
  .findAll { node ->
    node.nodeName?.startsWith("${instanceName}-agent-".toString()) &&
    node.nodeDescription?.startsWith(managedDescription) &&
    !desiredNodeNames.contains(node.nodeName)
  }
  .each { staleNode ->
    jenkins.removeNode(staleNode)
    println("[bootstrap] removed stale node ${staleNode.nodeName}")
  }

def workflowJobClass = optionalClass("org.jenkinsci.plugins.workflow.job.WorkflowJob")
def cpsScmFlowDefinitionClass = optionalClass("org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition")
def gitScmClass = optionalClass("hudson.plugins.git.GitSCM")
def branchSpecClass = optionalClass("hudson.plugins.git.BranchSpec")
def userRemoteConfigClass = optionalClass("hudson.plugins.git.UserRemoteConfig")
def systemCredentialsProviderClass = optionalClass("com.cloudbees.plugins.credentials.SystemCredentialsProvider")
def domainClass = optionalClass("com.cloudbees.plugins.credentials.domains.Domain")
def credentialsScopeClass = optionalClass("com.cloudbees.plugins.credentials.CredentialsScope")
def usernamePasswordCredentialsImplClass = optionalClass("com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl")

if (workflowJobClass && cpsScmFlowDefinitionClass && gitScmClass && branchSpecClass && userRemoteConfigClass) {
  try {
    def pipelineJob = jenkins.getItemByFullName(pipelineJobName, workflowJobClass)
    if (pipelineJob == null) {
      pipelineJob = jenkins.createProject(workflowJobClass, pipelineJobName)
      println("[bootstrap] created pipeline job ${pipelineJobName}")
    }

    def effectiveGitCredentialsId = pipelineGitCredentialsId
    if (!effectiveGitCredentialsId && pipelineGitUsername && pipelineGitPassword) {
      effectiveGitCredentialsId = "${instanceName}-pipeline-git"
      println("[bootstrap] using generated git credentials id ${effectiveGitCredentialsId}")
    }

    if (effectiveGitCredentialsId && pipelineGitUsername && pipelineGitPassword) {
      if (systemCredentialsProviderClass && domainClass && credentialsScopeClass && usernamePasswordCredentialsImplClass) {
        try {
          def provider = systemCredentialsProviderClass.getInstance()
          def store = provider.getStore()
          def globalDomain = domainClass.global()

          def existing = provider.getCredentials()
            .find { credential ->
              try {
                return credential.getId() == effectiveGitCredentialsId
              } catch (Exception ignored) {
                return false
              }
            }

          if (existing != null) {
            store.removeCredentials(globalDomain, existing)
          }

          def managedGitCredential = usernamePasswordCredentialsImplClass.newInstance(
            credentialsScopeClass.GLOBAL,
            effectiveGitCredentialsId,
            "${managedDescription} (${instanceName} pipeline git)",
            pipelineGitUsername,
            pipelineGitPassword
          )
          store.addCredentials(globalDomain, managedGitCredential)
          provider.save()
          println("[bootstrap] ensured git credentials ${effectiveGitCredentialsId}")
        } catch (Exception credentialsError) {
          println("[bootstrap] failed to manage git credentials: ${credentialsError.class.simpleName}: ${credentialsError.message}")
        }
      } else {
        println("[bootstrap] credentials plugin classes unavailable; cannot manage git credentials")
      }
    } else if (effectiveGitCredentialsId) {
      println("[bootstrap] using existing git credentials id ${effectiveGitCredentialsId}")
    }

    def scmRepoUrl = pipelineRepoUrl
    if (effectiveGitCredentialsId?.trim()) {
      scmRepoUrl = stripUserInfo(scmRepoUrl)
    }
    def displayRepoUrl = maskUserInfo(scmRepoUrl)

    def scm = gitScmClass.newInstance(
      [userRemoteConfigClass.newInstance(scmRepoUrl, null, null, effectiveGitCredentialsId ?: null)],
      [branchSpecClass.newInstance("*/${pipelineBranch}")],
      false,
      [],
      null,
      null,
      []
    )

    def definition = cpsScmFlowDefinitionClass.newInstance(scm, pipelineScriptPath)
    definition.setLightweight(true)

    pipelineJob.setDefinition(definition)
    pipelineJob.setDescription(
      """${managedDescription}
Pipeline repository: ${displayRepoUrl}
Pipeline branch: ${pipelineBranch}
Pipeline script path: ${pipelineScriptPath}
""".stripIndent()
    )

    if (pipelineAuthToken?.trim()) {
      try {
        def configuredToken = pipelineJob.getAuthToken()?.getToken()
        if (configuredToken != pipelineAuthToken) {
          def authTokenField = pipelineJob.getClass().getDeclaredField("authToken")
          authTokenField.setAccessible(true)
          authTokenField.set(pipelineJob, new BuildAuthorizationToken(pipelineAuthToken))
          println("[bootstrap] configured remote trigger token for ${pipelineJobName}")
        }
      } catch (Exception tokenError) {
        println("[bootstrap] failed to set remote trigger token: ${tokenError.class.simpleName}: ${tokenError.message}")
      }
    }

    pipelineJob.save()

    def lastBuild = pipelineJob.getLastBuild()
    if (!pipelineJob.isBuilding() && (lastBuild == null || lastBuild.getResult() != hudson.model.Result.SUCCESS)) {
      pipelineJob.scheduleBuild2(0)
      println("[bootstrap] triggered initial build for ${pipelineJobName}")
    }
  } catch (Exception e) {
    println("[bootstrap] pipeline job configuration skipped due to error: ${e.class.simpleName}: ${e.message}")
  }
} else {
  println("[bootstrap] pipeline plugins are not installed; skipping pipeline job configuration")
}

jenkins.save()
println("[bootstrap] ${instanceName} ready")
