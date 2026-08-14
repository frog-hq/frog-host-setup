# Contributing

Changes must preserve the fixed component and package allowlists, explicit
consent, idempotency, and post-install verification. New operating systems or
package managers require tests that use fake executables and perform no real
installation.

Run `bash -n bin/frog-host-setup tests/run.sh` and `./tests/run.sh` before
opening a pull request. Do not add remote-script execution, shell-profile
edits, SSH policy changes, telemetry, or credential access.
