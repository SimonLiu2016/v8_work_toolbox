# local-dictionary-bridge Delta

## MODIFIED Requirements

### Requirement: Loopback dictionary endpoint
The desktop application SHALL expose a single HTTP endpoint on the IPv4 loopback interface that resolves a word or short phrase into phonetic transcription, definitions, and an audio URL, reusing the desktop application's own dictionary resolution. The response SHALL carry both a flat definition list and the grouped meanings (part-of-speech, definitions, examples) it was derived from, so a client can render the same structure the desktop lookup panel renders without re-deriving it. Adding fields SHALL NOT remove or change the existing flat `definitions` field, so a client that only reads the flat list keeps working unchanged.

#### Scenario: Extension queries a word through the bridge
- **WHEN** a local client requests the endpoint with a word and the desktop application is running
- **THEN** the endpoint returns structured dictionary data (word, phonetic, definitions, audio URL) equivalent to what the desktop application's own lookup panel would render for the same word.

#### Scenario: Grouped meanings accompany the flat definitions
- **WHEN** the endpoint resolves a term that has part-of-speech groupings
- **THEN** the response includes a `meanings` array whose entries carry `partOfSpeech`, that group's `definitions`, and that group's `examples`, alongside the unchanged flat `definitions` array
- **AND** every entry in the flat list still appears in the grouped structure, so a client rendering either shape shows the same definitions.

#### Scenario: Examples are not dropped by the bridge
- **WHEN** the resolved result contains examples
- **THEN** the bridge returns them with their part-of-speech group rather than discarding them, so a client can display them without a second lookup.

#### Scenario: Term with no part-of-speech prefix still resolves
- **WHEN** the endpoint resolves a short phrase whose dictionary entry does not begin with a part-of-speech prefix
- **THEN** the response still contains a grouped entry (with an empty `partOfSpeech`) carrying the phrase's definitions, and the flat `definitions` array is populated as before
- **AND** the prefix-less entry is not treated as a lookup failure, because a phrase having no `adj.`-style prefix is a property of the source data, not an error.

#### Scenario: Endpoint binds loopback only
- **WHEN** the desktop application starts the bridge
- **THEN** the endpoint listens on the IPv4 loopback address only and is not reachable from other network interfaces.

#### Scenario: Word absent from dictionary
- **WHEN** a local client requests a term that dictionary resolution cannot match
- **THEN** the endpoint responds with a distinguishable "no match" result containing the requested term and an empty definition set, rather than a transport error.
