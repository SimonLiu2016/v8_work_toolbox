## ADDED Requirements

### Requirement: StepFun Provider Dual-Route Presets and Step Plan Adaptation
The AI provider configuration interface SHALL offer dual quick-fill options for StepFun: one for standard Open Platform (`https://api.stepfun.com/v1`) and one for Step Plan subscribers (`https://api.stepfun.com/step_plan/v1`). If an ASR or TTS request returns HTTP 402 with quota exceeded on a standard endpoint, the system SHALL inform the user to switch the base URL to the Step Plan dedicated path.

#### Scenario: User selects Step Plan preset
- **WHEN** user clicks the "StepFun (Step Plan)" quick-fill preset in provider configuration
- **THEN** the Base URL is populated with `https://api.stepfun.com/step_plan/v1`, and the protocol is set to `stepfun`.

#### Scenario: Step Plan 402 remediation guidance
- **WHEN** a StepFun ASR or TTS request fails with HTTP 402 and the provider's base URL does not contain `step_plan`
- **THEN** the error notification specifically suggests updating the base URL to `https://api.stepfun.com/step_plan/v1` for Step Plan subscriptions.
