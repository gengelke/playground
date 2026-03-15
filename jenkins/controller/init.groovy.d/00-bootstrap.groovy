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
import jenkins.model.JenkinsLocationConfiguration

import java.util.LinkedList

def env = System.getenv()
def jenkins = Jenkins.get()

def instanceName = env.getOrDefault("JENKINS_INSTANCE_NAME", "jenkins")
def pipelineRepoUrl = env.getOrDefault("PIPELINE_REPO_URL", "https://github.com/example/jenkins-pipelines.git")
def pipelineBranch = env.getOrDefault("PIPELINE_BRANCH", "main")
def pipelineScriptPath = env.getOrDefault("PIPELINE_SCRIPT_PATH", "Jenkinsfile")
def pipelineJobName = env.getOrDefault("PIPELINE_JOB_NAME", "example-pipeline")
def pipelineAuthToken = env.getOrDefault("PIPELINE_AUTH_TOKEN", "example-pipeline-auth-token")
def pipelineAutoTrigger = env.getOrDefault("PIPELINE_AUTO_TRIGGER", "true")
def pipelineGitCredentialsId = env.getOrDefault("PIPELINE_GIT_CREDENTIALS_ID", "").trim()
def pipelineGitUsername = env.getOrDefault("PIPELINE_GIT_USERNAME", "").trim()
def pipelineGitPassword = env.getOrDefault("PIPELINE_GIT_PASSWORD", "")
def generateLibraryPipelineRepoUrl = env.getOrDefault("GENERATE_LIBRARY_PIPELINE_REPO_URL", "http://host.docker.internal:3000/myuser/generate-library")
def generateLibraryPipelineBranch = env.getOrDefault("GENERATE_LIBRARY_PIPELINE_BRANCH", pipelineBranch)
def generateLibraryPipelineAutoTrigger = env.getOrDefault("GENERATE_LIBRARY_PIPELINE_AUTO_TRIGGER", "false")
def libraryExampleClientPipelineRepoUrl = env.getOrDefault("LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL", "http://host.docker.internal:3000/myuser/library-example-client")
def libraryExampleClientPipelineBranch = env.getOrDefault("LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH", pipelineBranch)
def libraryExampleClientPipelineJobName = env.getOrDefault("LIBRARY_EXAMPLE_CLIENT_PIPELINE_JOB_NAME", "library-example-client")
def libraryExampleClientPipelineAuthToken = env.getOrDefault("LIBRARY_EXAMPLE_CLIENT_PIPELINE_AUTH_TOKEN", "")
def libraryExampleClientPipelineAutoTrigger = env.getOrDefault("LIBRARY_EXAMPLE_CLIENT_PIPELINE_AUTO_TRIGGER", "false")
def agentCount = (env.getOrDefault("AGENT_COUNT", "2") as Integer)
def agentExecutors = (env.getOrDefault("AGENT_EXECUTORS", "1") as Integer)
def agentRemoteFs = env.getOrDefault("AGENT_REMOTE_FS", "/home/jenkins/agent")
def adminUser = env.getOrDefault("JENKINS_ADMIN_USER", "admin")
def adminPassword = env.getOrDefault("JENKINS_ADMIN_PASSWORD", "password")
def regularUser = env.getOrDefault("JENKINS_REGULAR_USER", "user")
def regularPassword = env.getOrDefault("JENKINS_REGULAR_PASSWORD", "password")
def directoryBrowserCsp = env.getOrDefault("JENKINS_CSP", "").trim()
def jenkinsRootUrl = env.getOrDefault("JENKINS_ROOT_URL", env.getOrDefault("JENKINS_URL", "")).trim()
def managedDescription = "Managed by repository automation"

println("[bootstrap] configuring ${instanceName}")

if (directoryBrowserCsp && System.getProperty("hudson.model.DirectoryBrowserSupport.CSP") != directoryBrowserCsp) {
  System.setProperty("hudson.model.DirectoryBrowserSupport.CSP", directoryBrowserCsp)
  println("[bootstrap] configured Directory Browser CSP override")
}

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

def parseBooleanEnv = { String value, boolean defaultValue ->
  if (value == null) {
    return defaultValue
  }

  switch (value.trim().toLowerCase()) {
    case "1":
    case "true":
    case "yes":
    case "on":
      return true
    case "0":
    case "false":
    case "no":
    case "off":
      return false
    default:
      println("[bootstrap] invalid boolean value '${value}', using default ${defaultValue}")
      return defaultValue
  }
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

if (jenkinsRootUrl) {
  def normalizedRootUrl = jenkinsRootUrl.endsWith("/") ? jenkinsRootUrl : "${jenkinsRootUrl}/"
  def locationConfig = JenkinsLocationConfiguration.get()
  if (locationConfig.getUrl() != normalizedRootUrl) {
    locationConfig.setUrl(normalizedRootUrl)
    locationConfig.save()
    println("[bootstrap] configured Jenkins root URL ${normalizedRootUrl}")
  }
}

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
    def ensureManagedGitCredentials = { String credentialId, String username, String password, String credentialLabel ->
      if (!credentialId?.trim()) {
        return
      }
      if (!username?.trim() || !password?.trim()) {
        println("[bootstrap] using existing git credentials id ${credentialId}")
        return
      }

      if (systemCredentialsProviderClass && domainClass && credentialsScopeClass && usernamePasswordCredentialsImplClass) {
        try {
          def provider = systemCredentialsProviderClass.getInstance()
          def store = provider.getStore()
          def globalDomain = domainClass.global()

          def existing = provider.getCredentials()
            .find { credential ->
              try {
                return credential.getId() == credentialId
              } catch (Exception ignored) {
                return false
              }
            }

          if (existing != null) {
            store.removeCredentials(globalDomain, existing)
          }

          def managedGitCredential = usernamePasswordCredentialsImplClass.newInstance(
            credentialsScopeClass.GLOBAL,
            credentialId,
            "${managedDescription} (${instanceName} ${credentialLabel})",
            username,
            password
          )
          store.addCredentials(globalDomain, managedGitCredential)
          provider.save()
          println("[bootstrap] ensured git credentials ${credentialId}")
        } catch (Exception credentialsError) {
          println("[bootstrap] failed to manage git credentials: ${credentialsError.class.simpleName}: ${credentialsError.message}")
        }
      } else {
        println("[bootstrap] credentials plugin classes unavailable; cannot manage git credentials")
      }
    }

    def configurePipelineJob = { Map config ->
      def jobName = config.jobName
      def repoUrl = config.repoUrl
      def branch = config.branch
      def scriptPath = config.scriptPath
      def authToken = config.authToken
      def autoTrigger = config.autoTrigger
      def gitCredentialsId = config.gitCredentialsId
      def gitUsername = config.gitUsername
      def gitPassword = config.gitPassword

      if (!jobName?.trim()) {
        println("[bootstrap] skipped pipeline configuration due to empty job name")
        return
      }
      if (!repoUrl?.trim()) {
        println("[bootstrap] skipped pipeline '${jobName}' because repository URL is empty")
        return
      }

      def pipelineJob = jenkins.getItemByFullName(jobName, workflowJobClass)
      if (pipelineJob == null) {
        pipelineJob = jenkins.createProject(workflowJobClass, jobName)
        println("[bootstrap] created pipeline job ${jobName}")
      }

      def effectiveGitCredentialsId = gitCredentialsId?.trim()
      if (!effectiveGitCredentialsId && gitUsername?.trim() && gitPassword?.trim()) {
        effectiveGitCredentialsId = "${instanceName}-${jobName}-git".replaceAll("[^A-Za-z0-9._-]", "-")
        println("[bootstrap] using generated git credentials id ${effectiveGitCredentialsId}")
      }

      ensureManagedGitCredentials(effectiveGitCredentialsId, gitUsername, gitPassword, "${jobName} pipeline git")

      def scmRepoUrl = repoUrl
      if (effectiveGitCredentialsId?.trim()) {
        scmRepoUrl = stripUserInfo(scmRepoUrl)
      }
      def displayRepoUrl = maskUserInfo(scmRepoUrl)

      def scm = gitScmClass.newInstance(
        [userRemoteConfigClass.newInstance(scmRepoUrl, null, null, effectiveGitCredentialsId ?: null)],
        [branchSpecClass.newInstance("*/${branch}")],
        false,
        [],
        null,
        null,
        []
      )

      def definition = cpsScmFlowDefinitionClass.newInstance(scm, scriptPath)
      definition.setLightweight(true)

      pipelineJob.setDefinition(definition)
      pipelineJob.setDescription(
        """${managedDescription}
Pipeline repository: ${displayRepoUrl}
Pipeline branch: ${branch}
Pipeline script path: ${scriptPath}
""".stripIndent()
      )

      if (authToken?.trim()) {
        try {
          def configuredToken = pipelineJob.getAuthToken()?.getToken()
          if (configuredToken != authToken) {
            def authTokenField = pipelineJob.getClass().getDeclaredField("authToken")
            authTokenField.setAccessible(true)
            authTokenField.set(pipelineJob, new BuildAuthorizationToken(authToken))
            println("[bootstrap] configured remote trigger token for ${jobName}")
          }
        } catch (Exception tokenError) {
          println("[bootstrap] failed to set remote trigger token: ${tokenError.class.simpleName}: ${tokenError.message}")
        }
      }

      pipelineJob.save()

      def autoTriggerEnabled = parseBooleanEnv(autoTrigger?.toString(), true)
      if (autoTriggerEnabled) {
        def lastBuild = pipelineJob.getLastBuild()
        if (!pipelineJob.isBuilding() && (lastBuild == null || lastBuild.getResult() != hudson.model.Result.SUCCESS)) {
          pipelineJob.scheduleBuild2(0)
          println("[bootstrap] triggered initial build for ${jobName}")
        }
      } else {
        println("[bootstrap] auto trigger disabled for ${jobName}")
      }
    }

    configurePipelineJob([
      jobName: pipelineJobName,
      repoUrl: pipelineRepoUrl,
      branch: pipelineBranch,
      scriptPath: pipelineScriptPath,
      authToken: pipelineAuthToken,
      autoTrigger: pipelineAutoTrigger,
      gitCredentialsId: pipelineGitCredentialsId,
      gitUsername: pipelineGitUsername,
      gitPassword: pipelineGitPassword
    ])

    configurePipelineJob([
      jobName: "generate-library",
      repoUrl: generateLibraryPipelineRepoUrl,
      branch: generateLibraryPipelineBranch,
      scriptPath: pipelineScriptPath,
      authToken: "",
      autoTrigger: generateLibraryPipelineAutoTrigger,
      gitCredentialsId: pipelineGitCredentialsId,
      gitUsername: pipelineGitUsername,
      gitPassword: pipelineGitPassword
    ])

    configurePipelineJob([
      jobName: libraryExampleClientPipelineJobName,
      repoUrl: libraryExampleClientPipelineRepoUrl,
      branch: libraryExampleClientPipelineBranch,
      scriptPath: pipelineScriptPath,
      authToken: libraryExampleClientPipelineAuthToken,
      autoTrigger: libraryExampleClientPipelineAutoTrigger,
      gitCredentialsId: pipelineGitCredentialsId,
      gitUsername: pipelineGitUsername,
      gitPassword: pipelineGitPassword
    ])
  } catch (Exception e) {
    println("[bootstrap] pipeline job configuration skipped due to error: ${e.class.simpleName}: ${e.message}")
  }
} else {
  println("[bootstrap] pipeline plugins are not installed; skipping pipeline job configuration")
}

jenkins.save()
println("[bootstrap] ${instanceName} ready")
