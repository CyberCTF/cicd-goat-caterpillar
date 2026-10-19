// Loads the per-player flag into the `flag2` credential, scoped to the `caterpillar-release` folder.
//
// This runs at the end of Jenkins startup — after Configuration-as-Code has created the folders — and
// reads the flag from the root-only file the entrypoint staged out of the per-player input Isoloom
// mounts at run time. The flag therefore never appears in an image layer, a spec value or a process
// environment variable: a pipeline must bind the `flag2` credential to read it, and only pipelines in
// the `caterpillar-release` folder can (the test pipeline that builds untrusted fork PRs cannot). An
// offline start leaves the mounted file empty, so the inert development placeholder is loaded instead.
import com.cloudbees.hudson.plugins.folder.Folder
import com.cloudbees.plugins.credentials.CredentialsProvider
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.domains.Domain
import hudson.util.Secret
import jenkins.model.Jenkins
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl

def LOG = java.util.logging.Logger.getLogger('wonderland.caterpillar')

def secretsDir = System.getenv('SECRETS') ?: '/run/lab/casc_secrets'
def flagFile = new File(secretsDir, 'flag2')
def dev = 'cat-dev-flag-not-a-real-secret-0000'
def value = (flagFile.exists() && flagFile.length() > 0) ? flagFile.text.trim() : dev
if (!value) { value = dev }

def jenkins = Jenkins.get()

// The PROD folder is created by Configuration-as-Code's Job DSL seed; create it here too if this hook
// happens to run first, so the credential always has a home.
def folderName = 'caterpillar-release'
def folder = jenkins.getItem(folderName)
if (folder == null) {
    folder = jenkins.createProject(Folder.class, folderName)
    LOG.info("caterpillar: created folder ${folderName}")
}

// Locate the folder's own credentials store and (re)place the flag2 string credential in it.
def store = CredentialsProvider.lookupStores(folder).find { it.getContext() == folder }
if (store == null) {
    LOG.severe("caterpillar: could not find a folder-scoped credentials store on ${folderName}")
    return
}

def cred = new StringCredentialsImpl(
    CredentialsScope.GLOBAL, 'flag2',
    'Wonderland release token (flag2) — keep secret', Secret.fromString(value))

def domain = Domain.global()
def existing = store.getCredentials(domain).find { it.hasProperty('id') && it.id == 'flag2' }
if (existing != null) {
    store.removeCredentials(domain, existing)
}
store.addCredentials(domain, cred)
jenkins.save()
LOG.info("caterpillar: loaded flag2 (${value.length()} chars) into folder ${folderName}")
