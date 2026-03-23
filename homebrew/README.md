# Homebrew tap (KMAC-CLI / kmac)

This directory holds the `kmac` formula. The repository root also contains `Formula/kmac.rb` (symlink) pointing here so Homebrew can discover the formula when you tap this repo.

**Commit `Formula/` and `homebrew/`** before pushing; `brew tap … https://github.com/…` clones the default branch from GitHub, so uncommitted files will not appear in the tap.

## Tap

```bash
brew tap ksarrafi/tap https://github.com/ksarrafi/KMAC-CLI
```

## Install

```bash
brew install ksarrafi/tap/kmac
```

To install the latest commit from `main` instead of the stable tarball:

```bash
brew reinstall --HEAD ksarrafi/tap/kmac
```

## Update

```bash
brew update
brew upgrade kmac
```

## After install: shell aliases

Add toolkit aliases and helpers to your shell (Zsh example):

```bash
echo 'source "$(brew --prefix kmac)/libexec/aliases.sh"' >> ~/.zshrc
source ~/.zshrc
```

Adjust the path if you prefer the explicit Cellar location; `brew --prefix kmac` resolves to the install prefix for the `kmac` formula.

## Releases

Use `./scripts/release <version>` at the repo root to bump `VERSION`, refresh the formula URL, and create a tag. After pushing the tag, compute the tarball `sha256` and update `homebrew/Formula/kmac.rb` as printed by the script.
