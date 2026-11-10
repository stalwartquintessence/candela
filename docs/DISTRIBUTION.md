# Distributing Candela for free

Everything below costs nothing. The only paid option (Apple's Developer Program) is listed at
the end so you know what it would add, but you do not need it.

## 1. Publish the code on GitHub

Create an empty **public** repository on github.com (no README, license or .gitignore, since
the project has them), then from the project folder:

```sh
git init -b main            # skip if the folder is already a git repository
git add .
git commit -m "Candela 0.1.0"
git remote add origin https://github.com/<your-username>/candela.git
git push -u origin main
```

If you publish your own fork, change `BUNDLE_ID` in `scripts/config.sh` to an identifier you own,
for example `io.github.<your-username>.Candela`, and update the log command in the README.
macOS stores preferences and permissions under the bundle ID, so changing it later resets them.

Public repositories get unlimited free GitHub Actions minutes, so the included workflows run at
no cost:

- `.github/workflows/ci.yml` runs the tests and builds the app on every push and pull request,
  and attaches the build to the run.
- `.github/workflows/release.yml` publishes a release when you push a version tag.

(Private repositories also work, but macOS runners use up the monthly free minutes quickly.)

## 2. Publish a release

Once, before the first release, give the release workflow your signing identity so every
release carries the same signature (see [Sign releases on GitHub Actions](#sign-releases-on-github-actions)):

```sh
./scripts/create-signing-identity.sh   # if you have not already
./scripts/export-signing-identity.sh
```

Then, for each release:

1. Update `AppVersion.string` in `Sources/MonitorCore/Version.swift`.
2. In `CHANGELOG.md`, move the entries under **Unreleased** into a new section for that
   version with the release date, for example `## [0.1.0] - 2026-12-01`.
3. Commit, then tag and push:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The release workflow checks that the tag matches the version, runs the tests, builds and signs
(it stops if the signing secrets are missing), and creates a GitHub Release with `Candela-0.1.0.dmg`, `Candela-0.1.0.zip` and `SHA256SUMS.txt`.
GitHub hosts the downloads for free.

You can also build release files locally with `./scripts/package.sh` and upload them by hand
on the repository's Releases page.

## 3. What users see on first launch

Apps that are not notarized by Apple are blocked the first time they are opened, and again the
first time each downloaded update is opened. Users either:

- open **System Settings > Privacy & Security** and click **Open Anyway**, or
- run `xattr -dr com.apple.quarantine /Applications/Candela.app`.

This is normal for free open source Mac apps and is explained in the README's Install section.
Because releases are signed with the same certificate, the Accessibility permission carries
over to each update.

## 4. Optional: a Homebrew tap

Since 2026-09-01 the official Homebrew cask repository (`homebrew/cask`) only accepts apps
that pass Gatekeeper, which needs Apple's paid notarization, and Homebrew removed the
`--no-quarantine` option. Your own tap still works.

A tap is just another free GitHub repository. Create `github.com/<your-username>/homebrew-tap`
with `Casks/candela.rb`:

```ruby
cask "candela" do
  version "0.1.0"
  sha256 "<the .dmg line from SHA256SUMS.txt>"

  url "https://github.com/<your-username>/candela/releases/download/v#{version}/Candela-#{version}.dmg"
  name "Candela"
  desc "Brightness, contrast and picture mode control for external displays"
  homepage "https://github.com/<your-username>/candela"

  depends_on arch: :arm64
  depends_on macos: ">= :ventura"

  app "Candela.app"
  binary "#{appdir}/Candela.app/Contents/MacOS/candelactl"

  zap trash: "~/Library/Preferences/<your bundle id>.plist"
end
```

Users then install with `brew install --cask <your-username>/tap/candela` and update with
`brew upgrade`. macOS still blocks the first launch after each install or upgrade, exactly as
for a download (see section 3).

## 5. Optional: a website

Turn on **GitHub Pages** in the repository settings (Settings > Pages > Deploy from branch,
`main`, `/docs` or root). It is free and serves the README or a page you add.

## Keep permissions across builds

macOS ties the Accessibility permission (used for the brightness keys) to the app's code
signature. Without a certificate the build is signed ad-hoc, which changes on every build, so
macOS silently stops honoring the permission after each rebuild.

A free self-signed certificate fixes this for builds on your own Mac. One command sets it up:

```sh
./scripts/create-signing-identity.sh
./scripts/build-app.sh   # now signs with "Candela Local Signing"
```

The identity lives in its own keychain in `~/Library/Application Support/Candela Signing`.
Nothing is added to your login keychain, no trust settings change and there is no password
prompt. The build script prints the signature's designated requirement, which should read
`identifier "..." and certificate leaf = H"..."`; that is what macOS matches the permission
against, and it stays the same for every build. To remove the identity:
`rm -rf "$HOME/Library/Application Support/Candela Signing"`.

Then, once: in **System Settings > Privacy & Security > Accessibility**, remove any old Candela
entry, click **Allow in System Settings** in Candela's window and switch Candela on.
From now on rebuilds keep the permission.

(Alternatively, any code signing certificate works: set `CODESIGN_IDENTITY` to its name.)

Never commit certificates or private keys; `.gitignore` already excludes common formats.

### Sign releases on GitHub Actions

GitHub's build machines do not have your identity, so without help they sign ad-hoc and every
update would ask users for the Accessibility permission again. Give them a copy, once:

```sh
./scripts/export-signing-identity.sh
```

It exports the identity to a temporary file, stores it as two encrypted repository secrets
(`SIGNING_IDENTITY_P12` and `SIGNING_IDENTITY_PASSWORD`) with the GitHub CLI, and deletes the
file. macOS may ask for the signing keychain's password before the key leaves it; the script
puts that password on your clipboard. Both workflows then run
`scripts/import-signing-identity.sh`, which loads the identity into a temporary keychain on the
build machine. The release workflow stops if the secrets are missing, so a release is never
signed ad-hoc by mistake. CI builds of pull requests from forks get no secrets and are signed
ad-hoc.

Releases then have the same designated requirement as your own builds, so the permission you
granted locally applies to them too.

Anyone who has these secrets can sign apps that macOS accepts as Candela for this permission,
so keep them only in the repository's secrets. To replace the identity, delete the signing
folder, run both scripts again, and note in the release that users must allow Candela once more.

## What the paid Apple Developer Program would add (not required)

For 99 USD per year, Apple issues a Developer ID certificate and notarizes apps, which removes
the first-launch warning and allows a listing in the official Homebrew cask repository. Candela works
fine without it. It can never be on the Mac App Store, because the App Store does not allow the
private I2C APIs that DDC/CI control needs. If your university has an Apple Developer
organization account, its IT department may be able to sign releases for you.
