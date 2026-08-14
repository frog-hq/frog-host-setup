# frog-host-setup

`frog-host-setup` is the small, auditable host-preparation tool used by Frog. It
installs and verifies standard OpenSSH, Mosh, and tmux prerequisites without
changing SSH policy, shell startup files, or tmux configuration.

The terminal remains a normal SSH/Mosh terminal. Frog does not add a private
shell protocol or reduce the privileges of the operating-system account chosen
by the user.

## Safety contract

- Detect → plan → explicit consent → apply → verify.
- Only `openssh`, `mosh`, and `tmux` are accepted component names.
- `--dry-run` prints the exact package-manager plan without mutation.
- `sudo` is never used before the plan is displayed and consent is provided.
- Re-running the tool is safe: ready components are not installed again.
- The tool never edits `sshd_config`, `authorized_keys`, `.tmux.conf`, or shell
  profiles.
- Release assets are accompanied by SHA-256 checksums, an SPDX SBOM, and a
  GitHub build-provenance attestation. Frog consumes a pinned release, never a
  floating `curl | sh` command.

## Usage

```sh
./bin/frog-host-setup --dry-run
./bin/frog-host-setup --component tmux --dry-run
./bin/frog-host-setup --component tmux --yes
./bin/frog-host-setup --verify-only --json
```

Supported package managers are Homebrew, APT, DNF, and pacman. Package-manager
availability does not imply that the tool enables or reconfigures `sshd`; that
remains an explicit operating-system administration decision.

## Development

```sh
bash -n bin/frog-host-setup tests/run.sh
./tests/run.sh
```

This project is dual-licensed under Apache-2.0 or MIT, at your option.
