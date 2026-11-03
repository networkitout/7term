# Releasing 7 Term

`tools/release.sh 1.0.0` builds a Release copy, signs it with your Developer ID, has Apple notarize it, packs it in a signed and notarized DMG, writes Sparkle's update feed, and publishes a GitHub release with both files attached. Apps already installed find the update through **7 Term ▸ Check for Updates…** or Sparkle's own daily check.

Try `tools/release.sh 1.0.0 --no-publish` first: it does everything except tag and publish, and leaves the results in `build/release/1.0.0/`.

## One-time setup

Nothing secret goes in the repo. The certificate, the notarization password and Sparkle's private key all live in your login Keychain.

### 1. Developer ID certificate and team

- In Xcode: **Settings ▸ Accounts**, select your Apple ID, **Manage Certificates…**, **+**, **Developer ID Application**.
- Check it's there: `security find-identity -v -p codesigning` lists `Developer ID Application: Your Name (TEAMID)`.
- Put the 10-character team ID in `project.yml`: `DEVELOPMENT_TEAM: "TEAMID"`. It isn't secret; it's printed inside every app you sign.

### 2. Notarization login

Create an app-specific password at [account.apple.com](https://account.apple.com) (**Sign-In and Security ▸ App-Specific Passwords**), then save it in your Keychain under the name the script uses:

```
xcrun notarytool store-credentials 7term-notary --apple-id you@example.com --team-id TEAMID
```

It asks for the password itself, so it never appears in your shell history.

### 3. Sparkle's update key

Updates are signed with an EdDSA key so a tampered download is refused. Build once (`tools/install.sh`) so Sparkle's tools are downloaded, then:

```
"$(find build/DerivedData/SourcePackages/artifacts -path '*Sparkle*/bin/generate_keys' | head -1)"
```

It stores the private key in your Keychain and prints the public key. Put that in `project.yml`: `SPARKLE_PUBLIC_KEY: "…"`.

Back up the private key (`generate_keys -x sparkle-key.txt`, then keep that file somewhere safe and offline). If it's lost, installed copies can't verify future updates and people would have to download 7 Term again by hand.

### 4. GitHub CLI

`brew install gh` and `gh auth login`, so the script can tag and publish the release.

## Each release

1. Commit everything (the script refuses to build from uncommitted changes).
2. `tools/release.sh 1.2.0`

The build number is the commit count, so it always goes up, which Sparkle needs to see a newer version. Release DMGs are also kept in `build/release/updates/`; keep that folder between releases if you want Sparkle's smaller delta updates later.
