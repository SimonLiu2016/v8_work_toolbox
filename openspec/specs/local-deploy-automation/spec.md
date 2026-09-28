# local-deploy-automation Specification

## Purpose

Provides the repeatable, single-command path from a source change to a running locally installed application, so that building, signing, and replacing the installed bundle cannot silently skip a step whose omission corrupts credentials or leaves orphaned child processes.

## Requirements

### Requirement: One-command local macOS deployment
The project SHALL provide a single command that rebuilds and replaces the locally installed application without manual intermediate steps. The command SHALL perform every mandatory step in a fixed order, SHALL abort the entire run when any step fails (leaving no half-deployed state), and SHALL report a final artifact identity that lets the operator confirm the deployed build matches the code just built.

#### Scenario: Successful end-to-end deploy
- **WHEN** operator runs the local deploy command with no arguments
- **THEN** the command cleans prior build artifacts, performs a release build, injects the bundled proxy binary that the build system intentionally does not ship, re-signs the bundle so the modified resource set carries a valid seal, terminates any running previous instance, replaces the installed application, and launches it
- **AND** the command exits successfully only after the post-deploy signature verification passes and the launched application process is confirmed alive
- **AND** the command reports the identity of the deployed application code snapshot so the operator can confirm it differs from the previously installed one

#### Scenario: Build failure aborts before touching the installed app
- **WHEN** the release build fails during the deploy run
- **THEN** the command aborts at that step, the previously installed application remains untouched and still launchable
- **AND** the command reports the failing step and exits non-zero

#### Scenario: Post-deploy verification failure aborts before launch
- **WHEN** the deployed bundle fails strict code signature verification
- **THEN** the command does not launch the application, reports the verification failure, and exits non-zero

#### Scenario: Bundled proxy binary is preserved across clean builds
- **WHEN** the deploy command runs its clean step, which removes build artifacts including a bundled proxy binary that source control intentionally excludes
- **THEN** the command restores that binary into the newly built bundle before signing
- **AND** the resulting bundle contains the binary and reports a valid strict signature

### Requirement: Graceful cleanup of child processes on termination
The application SHALL terminate its own spawned child processes when it receives a process-level termination signal, and SHALL NOT leave orphaned child processes that continue holding shared resources (such as the local proxy listening port) after the application process has exited.

#### Scenario: Termination signal stops the proxy child process
- **WHEN** the application process receives a termination signal while its managed proxy child process is running
- **THEN** the application stops that child process before exiting
- **AND** no orphaned child process remains, and the local proxy port is released

#### Scenario: Window close still stops the proxy child process
- **WHEN** the operator closes the main application window
- **THEN** the proxy child process is stopped as before, preserving the existing close-time cleanup behavior

#### Scenario: Cleanup failure does not prevent exit
- **WHEN** stopping a child process fails or times out during termination
- **THEN** the application still completes its exit, and does not hang indefinitely waiting on the child process

### Requirement: Targeted fallback cleanup during deploy
The deploy command SHALL provide a fallback cleanup for child processes that outlived a previous application instance, but SHALL scope that cleanup to processes belonging to this application's own installation and SHALL NOT terminate unrelated processes that happen to be similarly named.

#### Scenario: Orphaned child process from a previous run is cleaned
- **WHEN** the deploy command finds a still-running proxy child process spawned from a previous application instance whose own instance is no longer alive
- **THEN** the command terminates that orphaned process before replacing the application

#### Scenario: Third-party process with a similar name is left alone
- **WHEN** the deploy command performs its fallback cleanup
- **THEN** it terminates only processes whose executable path belongs to this application's installation
- **AND** processes belonging to other applications (including other proxy implementations with similar names) are not signaled
