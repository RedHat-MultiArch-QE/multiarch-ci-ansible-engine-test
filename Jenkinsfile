properties(
  [
    pipelineTriggers(
      [
        [
          $class: 'CIBuildTrigger',
          noSquash: true,
          providerData:
            [
            $class: 'ActiveMQSubscriberProviderData',
            name: 'Red Hat UMB',
            overrides: [topic: 'Consumer.rh-jenkins-ci-plugin.a3d96a6e-b99e-43c1-b11d-a996e18a1b2d.VirtualTopic.eng.brew.>'],
            selector: 'name = \'ansible\' AND type = \'Tag\' AND tag LIKE \'ansible-%-rhel-%-candidate\'',
            timeout: null
          ]
        ]
      ]
    ),
    parameters(
      [
        [$class: 'ValidatingStringParameterDefinition',
         defaultValue: 'x86_64',
         description: 'A comma separated list of architectures to run the test on. Valid values include [x86_64, ppc64le, aarch64, s390x].',
         failedValidationMessage: 'Invalid architecture. Valid values are [x86_64, ppc64le, aarch64, s390x].',
         name: 'ARCHES',
         regex: '^(?:x86_64|ppc64le|aarch64|s390x)(?:,\\s*(?:x86_64|ppc64le|aarch64|s390x))*$'
        ],
        string(
          defaultValue: 'https://github.com/jaypoulz/multiarch-ci-libraries',
          description: 'Repo for shared libraries.',
          name: 'LIBRARIES_REPO'
        ),
        string(
          defaultValue: 'dev-v1.2.2',
          description: 'Git reference to the branch or tag of shared libraries.',
          name: 'LIBRARIES_REF'
        ),
        string(
          defaultValue: '',
          description: 'Repo for tests to run. If left blank, the current repo is assumed (*note* this default will only work for multibranch pipelines).',
          name: 'TEST_REPO'
        ),
        string(
          defaultValue: '',
          description: 'Git reference to the branch or tag of the tests repo.',
          name: 'TEST_REF'
        ),
        string(
          defaultValue: 'tests',
          description: 'Directory containing tests to run. Should at least one of the follow: an ansible-playbooks directory containing one or more test directories each of which having a playbook.yml, a scripts directory containing one or more test directories each of which having a run-test.sh',
          name: 'TEST_DIR'
        ),
        string(
          defaultValue: '',
          description: 'Contains the CI_MESSAGE for a message bus triggered build.',
          name: 'CI_MESSAGE'
        ),
        string(
          defaultValue: '19572674',
          description: 'Build task ID for which to run the pipeline',
          name: 'TASK_ID'
        ),
        string(
          defaultValue: 'RHEL-ALT-7.5',
          description: 'RHEL 7 distribution.',
          name: 'RHEL7_DISTRO'
        ),
        string(
          defaultValue: 'RHEL-8.0.0-20190129.1',
          description: 'RHEL 8 distribution.',
          name: 'RHEL8_DISTRO'
        ),
        string(
          defaultValue: 'jpoulin',
          description: 'Semi-colon delimited list of email notification recipients.',
          name: 'EMAIL_SUBSCRIBERS'
        )
      ]
    )
  ]
)

library(
  changelog: false,
  identifier: "multiarch-ci-libraries@${params.LIBRARIES_REF}",
  retriever: modernSCM([$class: 'GitSCMSource',remote: "${params.LIBRARIES_REPO}"])
)

// MACIT configuration
def errorMessages = ''
def config = MAQEAPI.v1.getProvisioningConfig(this)
config.installRhpkg = true
//config.mode = 'JNLP'

// Get build information
Map message = [:]
String taskId = ''
String nvr = ''

// Required host information
List arches = params.ARCHES.tokenize(',')
String os = ''
String distro = ''
String variant = ''

// Lookup the build information
MAQEAPI.v1.testWrapper(this, config) {
  node ("provisioner-${config.version}"){
    // Message
    message = getCIMessage(params.CI_MESSAGE)

    // Task ID
    taskId = message && message.build && message.build.task_id ?: params.TASK_ID
    if (!taskId) {
      error("Invalid brew task ID for CI_MESSAGE: ${params.CI_MESSAGE} and TASK_ID: ${params.TASK_ID}.")
    }

    // NVR
    nvr = sh(script:"brew taskinfo ${taskId} | grep 'Build:' | cut -d' ' -f2", returnStdout:true)
    if (!nvr) {
      error("Invalid nvr: ${nvr}.")
    }

    // OS
    os = sh(
      script: """
        brew buildinfo \
            \$(brew taskinfo ${taskId} | grep 'Build:' | cut -d '(' -f 2 | cut -d ')' -f 1) | \
            grep 'Volume:' | cut -d ' ' -f 2
      """,
      returnStdout: true
    ).trim()
    if (!os || !(['rhel-7', 'rhel-8'].contains(os))) {
      error("Invalid OS version: ${os}.")
    }

    // Distro
    distro = (os == 'rhel-8') ? params.RHEL8_DISTRO : params.RHEL7_DISTRO
    if (!distro) {
      error("Invalid distro: ${distro}.")
    }

    // Variant
    variant = (os == 'rhel-8') ? 'BaseOS' : 'Server'
    if (!variant) {
      error("Invalid variant: ${variant}.")
    }
  }
}

def targetHosts = []
for (String arch in arches) {
  def targetHost = MAQEAPI.v1.newTargetHost()
  targetHost.arch = arch
  targetHost.distro = distro
  targetHost.variant = variant
  if (os == 'rhel-8') {
      targetHost.inventoryVars = [ ansible_python_interpreter:'/usr/libexec/platform-python' ]
  }
  targetHosts.push(targetHost)
}

MAQEAPI.v1.runTest(
  this,
  targetHosts,
  config,
  { host ->
    /*********************************************************/
    /* TEST BODY                                             */
    /* @param host               Provisioned host details.   */
    /*********************************************************/
    installBrewPkgs(params, config.runOnSlave)

    stage ('Download Test Files') {
      downloadTests()
    }

    stage ('Run Test') {
      runTests(config, host)
    }

    stage ('Archive Test Output') {
      archiveOutput()
    }

    /*****************************************************************/
    /* END TEST BODY                                                 */
    /* Do not edit beyond this point                                 */
    /*****************************************************************/
  },
  { Exception exception, def host ->
    stage ('Archive Failed Test Output') {
      archiveOutput()
    }

    def error = "Exception ${exception} occured on ${host.arch}\n"
    errorMessages += error
    if (host.arch.equals("x86_64") || host.arch.equals("ppc64le")) {
      currentBuild.result = 'FAILURE'
    }
  },
  {
    try {
      sh "mkdir -p artifacts"
      unarchive(mapping: ['**/*.*' : 'artifacts/.'])
    } catch (e) {
      errorMessages += "Exception ${e} occured while unarchiving artifacts\n"
    }

    def emailBody = "Results for ${env.JOB_NAME} - Build #${currentBuild.number}\n\nResult: ${currentBuild.currentResult}\nNVR: ${nvr}\nURL: $BUILD_URL"
    if (errorMessages) emailBody += "\nErrors: " + errorMessages

    emailext(
      subject: "${env.JOB_NAME} (#${currentBuild.number}) - ${nvr ? nvr + ' - ': ''}${currentBuild.currentResult}",
      body: emailBody,
      from: 'multiarch-qe-jenkins',
      replyTo: 'multiarch-qe',
      to: "${params.EMAIL_SUBSCRIBERS}",
      attachmentsPattern: 'artifacts/tests/scripts/rhel-system-roles/artifacts/**/*.*'
    )
  }
)
