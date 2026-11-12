import jenkins.model.Jenkins
import jenkins.model.JenkinsLocationConfiguration
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey
import hudson.plugins.emailext.ExtendedEmailPublisherDescriptor
import jenkins.plugins.git.GitSCMSource
import jenkins.plugins.git.traits.BranchDiscoveryTrait
import jenkins.branch.BranchSource
import org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject
import org.jenkinsci.plugins.workflow.multibranch.WorkflowBranchProjectFactory

// Este bootstrap é exclusivo do laboratório local criado pelo Compose.
if (System.getenv('CA5_LOCAL_LAB') != 'true') {
    return
}

def instance = Jenkins.get()
def realm = new HudsonPrivateSecurityRealm(false)
realm.createAccount('luiz', new File('/run/secrets/admin_password').text.trim())
instance.setSecurityRealm(realm)
def authorization = new FullControlOnceLoggedInAuthorizationStrategy()
authorization.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(authorization)
instance.setNumExecutors(1)
instance.setLabelString('ca5-linux')

def location = JenkinsLocationConfiguration.get()
location.setUrl('http://localhost:18080/')
location.setAdminAddress('Jenkins CA5 <jenkins@ca5.local>')
location.save()

def credentialStore = SystemCredentialsProvider.getInstance().getStore()
def registryCredential = new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL, 'dockerhub-ca5', 'Registo local de teste; não é um token Docker Hub',
    'ca5-local', new File('/run/secrets/registry_password').text.trim()
)
def sshCredential = new BasicSSHUserPrivateKey(
    CredentialsScope.GLOBAL, 'ca5-production-ssh', 'vagrant',
    new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(new File('/run/secrets/production_key').text),
    null, 'Chave da VM de produção do laboratório CA5'
)
for (credential in [registryCredential, sshCredential]) {
    def existing = credentialStore.getCredentials(Domain.global()).find { it.id == credential.id }
    if (existing) {
        credentialStore.updateCredentials(Domain.global(), existing, credential)
    } else {
        credentialStore.addCredentials(Domain.global(), credential)
    }
}

def email = instance.getDescriptorByType(ExtendedEmailPublisherDescriptor.class)
email.getMailAccount().setSmtpHost('mailpit')
email.getMailAccount().setSmtpPort('1025')
email.getMailAccount().setUseSsl(false)
email.getMailAccount().setUseTls(false)
email.setDefaultRecipients('luiz@ca5.local')
email.setCharset('UTF-8')
email.save()

def project = instance.getItem('ca5-local')
if (!project) {
    project = instance.createProject(WorkflowMultiBranchProject.class, 'ca5-local')
    def source = new GitSCMSource('/srv/scm.git')
    source.setId('ca5-local-scm')
    source.setTraits([new BranchDiscoveryTrait()])
    project.getSourcesList().add(new BranchSource(source))
    def factory = new WorkflowBranchProjectFactory()
    factory.setScriptPath('CA5/Part2/Jenkinsfile')
    project.setProjectFactory(factory)
    project.save()
}
instance.save()
project.scheduleBuild2(0)
println('CA5: laboratório local configurado; nenhuma publicação no GitHub foi realizada.')
