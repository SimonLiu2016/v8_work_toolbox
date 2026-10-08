# vocab-book-live-update Specification

## Purpose
Enables reactive data synchronization and live UI refresh for the vocabulary book whenever vocabulary entries are added, deleted, or modified.
## Requirements
### Requirement: Reactive vocabulary change broadcast
The vocabulary storage layer SHALL broadcast change notifications whenever entries are created, updated, or removed, allowing active UI views to synchronize their state immediately.

#### Scenario: Entry added to vocabulary store
- **WHEN** an entry is inserted into the vocabulary store from any source within the application
- **THEN** a change notification is broadcast to all active subscribers.

#### Scenario: Entry removed or modified in vocabulary store
- **WHEN** an entry is updated or removed from the vocabulary store
- **THEN** a change notification is broadcast to all active subscribers.

### Requirement: Real-time vocabulary book page refresh
The vocabulary book view SHALL listen for storage change notifications and perform a silent reload of the entries list without requiring the user to switch window focus away and back.

#### Scenario: Vocabulary page open when new word is added
- **WHEN** the user is viewing the vocabulary book page and a new word is added via the background bridge
- **THEN** the vocabulary book page receives the change notification and reloads the entry list silently, displaying the newly added word without disturbing active scroll or selection.

