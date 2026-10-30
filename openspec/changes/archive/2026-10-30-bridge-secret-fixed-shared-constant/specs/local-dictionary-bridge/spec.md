## MODIFIED Requirements

### Requirement: Bridge access authentication
The bridge SHALL require a shared secret on every request and SHALL reject requests that do not carry it. The secret SHALL be a fixed constant shared verbatim between the desktop application and the browser companion extension, so that pairing can never drift out of sync.

#### Scenario: Request without secret
- **WHEN** a request arrives without the shared secret
- **THEN** the endpoint responds with an authorization failure and performs no dictionary lookup.

#### Scenario: Request with wrong secret
- **WHEN** a request arrives with a secret that does not match the one the desktop application issued
- **THEN** the endpoint responds with an authorization failure and performs no dictionary lookup.

#### Scenario: Secret matches the extension's hard-coded value
- **WHEN** the desktop application starts and serves the bridge
- **THEN** the secret it accepts equals the constant hard-coded in the browser companion extension, so a request carrying that extension value is authorized
- **AND** no random generation or persistence of the secret occurs.

#### Scenario: Secret persists across desktop application restarts
- **WHEN** the desktop application restarts after a client has received the secret once
- **THEN** the same secret remains valid, so the client does not need to be reconfigured
- **AND** the accepted secret is a fixed constant, so it is also unchanged across reinstalls.
