## ADDED Requirements

### Requirement: Storyboard task error log inspection and clipboard copy
The storyboard board and task queue drawer SHALL provide a detailed log inspection dialog for failed tasks, displaying full unabridged error text and execution metadata, and allowing users to copy the entire error log to the clipboard with visual confirmation.

#### Scenario: Inspecting failed shot generation error
- **WHEN** user clicks on the error indicator on a shot card or a failed task in the queue drawer
- **THEN** system opens a modal dialog displaying the full error message in selectable text with a dedicated copy button
- **WHEN** user clicks the copy button
- **THEN** system writes the complete error text to system clipboard and displays a confirmation notification

### Requirement: Full-lifecycle AI logging for video generation
All video generation adapters SHALL log request dispatch, upstream response, and error details through `AiLogger`, ensuring video generation operations are transparently recorded alongside image generation in application logs.

#### Scenario: Video generation request logging
- **WHEN** a video generation task is initiated
- **THEN** adapter logs the target provider, model, endpoint, and prompt summary to `AiLogger`
- **WHEN** an error occurs during video generation
- **THEN** adapter logs the full error status code and response payload to `AiLogger`

### Requirement: Robust first frame payload handling for Agnes video
The `AgnesVideoAdapter` SHALL format the initial frame image data to be compatible with upstream Agnes video gateways, ensuring the keyframe mode payload includes valid first-frame attributes accepted by the endpoint without triggering `first_frame` missing rejections.

#### Scenario: Dispatching Agnes video with keyframe image
- **WHEN** user generates a video clip for a shot with a valid keyframe image
- **THEN** adapter formats the payload to satisfy the gateway's first-frame parameter requirements and begins polling
