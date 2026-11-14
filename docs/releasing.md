# Releasing

Versions, release notes and the DMG come from the commits on `main`. The reasons are in
[decision 0017](decisions/0017-releases-from-conventional-commits.md).

## How a version comes out

1. Each push to `main` runs `.github/workflows/release.yml`. The release-please action opens a pull
   request named `chore(main): release x.y.z`, or updates it. It holds the next version in
   `project.yml` and the new part of `CHANGELOG.md`.
2. The version follows the commits since the last release. Before 1.0, a `feat` raises the minor
   number (0.1.0 to 0.2.0) and a `fix` the patch number (0.1.0 to 0.1.1).
3. Merging that pull request tags the version, publishes its notes as a GitHub release and builds
   `Flux.dmg`, which the workflow attaches to the release a few minutes later, with its update
   signature in `Flux.dmg.sparkle`.
4. The workflow then rebuilds flux-browser.com, which makes a page of each release, points its
   download buttons to the latest `Flux.dmg` and adds the version to `appcast.xml`. Flux finds it
   there at its next daily check (see [decision 0018](decisions/0018-updates-with-sparkle.md)).

A paragraph added by hand at the top of a GitHub release becomes its headline on the website, at
the next rebuild.

The notes take the subjects of the commits as they are: `feat` under New, `perf` under Faster,
`fix` under Fixed, `style` and `refactor` under Smaller. To fix a subject before a release, put
the corrected messages in the body of the release pull request, between `BEGIN_COMMIT_OVERRIDE`
and `END_COMMIT_OVERRIDE`.

To force a version, add a commit with a `Release-As: 1.0.0` footer.

## Signing

Released versions are signed with a self-signed certificate named Flux Release, so that macOS sees
the same app from one version to the next. Flux has no Apple Developer ID, so Gatekeeper blocks the
first launch. The README explains how to open it anyway.

The certificate and its private key are in two secrets of the repository:

- `FLUX_SIGNING_CERTIFICATE`: the `.p12` file, in base64.
- `FLUX_SIGNING_PASSWORD`: the password of the `.p12`.

Updates are signed with an EdDSA key, whose public half is `SUPublicEDKey` in `project.yml`:

- `FLUX_SPARKLE_KEY`: the private key, in base64, as Sparkle's `generate_keys -x` exports it.

The maintainer keeps a copy of it outside GitHub too. Without it, the versions out there can't
update anymore.

The secret `WEBSITE_DEPLOY_HOOK` holds the deploy webhook of the website on Dokploy. Without it
the website waits for its next deployment.

The maintainer keeps a copy of the `.p12` and its password outside GitHub. A new certificate would
give Flux a new identity, and every user would get a keychain prompt after the next update.

To make one, if it is ever lost:

    cat > cert.cnf <<EOF
    [req]
    distinguished_name = dn
    x509_extensions = ext
    prompt = no
    [dn]
    CN = Flux Release
    [ext]
    basicConstraints = critical,CA:false
    keyUsage = critical,digitalSignature
    extendedKeyUsage = critical,codeSigning
    EOF
    openssl req -x509 -newkey rsa:3072 -nodes -days 7300 -config cert.cnf \
        -keyout key.pem -out cert.pem
    openssl pkcs12 -export -inkey key.pem -in cert.pem -out flux-release.p12
    base64 -i flux-release.p12 | gh secret set FLUX_SIGNING_CERTIFICATE
    gh secret set FLUX_SIGNING_PASSWORD

## Building the DMG locally

    scripts/package.sh

builds Flux in release and writes `build/Flux.dmg`. Set `FLUX_SIGNING_IDENTITY` to the hash or
the name of a certificate to sign with it, and `FLUX_KEYCHAIN` when it isn't in the login keychain.
Set `FLUX_SPARKLE_KEY` to write the update signature to `build/Flux.dmg.sparkle` as well.

## Repository settings

release-please opens its pull request with the workflow's token. Settings > Actions > General >
Workflow permissions must allow GitHub Actions to create pull requests.
