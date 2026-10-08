# private-browser/video-library Specification

## Purpose
Persistent private collection of favorited web videos, organized with a multi-level category tree, multi-tag system, star ratings, user notes, and AI-generated summaries.

## Data Model

- **VideoBookmark**: id, title, url, platform, thumbnail_path (local cache), duration (if available), added_at, category_id, tags[], rating (0–5), notes, ai_summary, ai_tags[]
- **Category**: id, name, parent_id, icon, display_order — supports unlimited nesting
- **Tag**: id, name, color, usage_count

## ADDED Requirements

### Requirement: Category tree management
The system SHALL allow users to create, rename, delete, and reorder categories in an unlimited multi-level hierarchy. Each VideoBookmark SHALL belong to exactly one category or be marked as uncategorized.

#### Scenario: Create a root category
- **WHEN** the user clicks "New Category" at the root level of the category tree and enters a name
- **THEN** a new Category record is created with `parent_id = nil` and appears as a top-level node in the tree

#### Scenario: Create a nested subcategory
- **WHEN** the user right-clicks an existing category and selects "New Subcategory", then enters a name
- **THEN** a new Category is created with `parent_id` set to the selected category's `id` and appears as a child node in the tree

#### Scenario: Rename a category
- **WHEN** the user double-clicks a category node and edits the name, then confirms
- **THEN** the Category record's `name` field is updated and the tree reflects the new name immediately

#### Scenario: Delete a category with bookmarks
- **WHEN** the user deletes a category that contains bookmarks or subcategories
- **THEN** the system prompts the user to choose between: (a) move contained bookmarks to "Uncategorized" and delete subcategories recursively, or (b) cancel; the deletion proceeds only on explicit confirmation

#### Scenario: Reorder categories
- **WHEN** the user drags a category node to a new position within the same level
- **THEN** the `display_order` fields of affected categories are updated and the tree reorders accordingly

### Requirement: Tag management
The system SHALL allow users to create, delete, and rename tags, assign multiple tags to a bookmark, and view a tag cloud displaying each tag's `usage_count`.

#### Scenario: Create a new tag
- **WHEN** the user types a new tag name in the tag input field and confirms
- **THEN** a Tag record is created with the given name and a default color, appearing in the tag list with `usage_count = 0`

#### Scenario: Assign tags to a bookmark
- **WHEN** the user opens a bookmark's detail view and selects one or more tags from the tag picker
- **THEN** the selected tag IDs are added to the bookmark's `tags[]` array and `usage_count` is incremented for each assigned tag

#### Scenario: Remove a tag from a bookmark
- **WHEN** the user removes a tag chip from a bookmark's detail view
- **THEN** the tag ID is removed from the bookmark's `tags[]` array and the tag's `usage_count` is decremented

#### Scenario: Tag cloud reflects usage
- **WHEN** the user opens the tag cloud view
- **THEN** tags are displayed with visual weight proportional to their `usage_count`, allowing the user to identify frequently used tags at a glance

#### Scenario: Delete a tag
- **WHEN** the user deletes a tag from the tag management list
- **THEN** the Tag record is removed and the tag ID is removed from all bookmarks that referenced it; `usage_count` becomes irrelevant and the tag no longer appears anywhere

### Requirement: Bookmark CRUD
The system SHALL support creating bookmarks (from the video-enhancer Favorite action), viewing bookmark details, editing fields (title, notes, rating, category, tags), and deleting bookmarks.

#### Scenario: Bookmark created from Favorite action
- **WHEN** the video-enhancer Favorite action is triggered for a page
- **THEN** a VideoBookmark is created with the page's title, URL, platform, thumbnail_path, and added_at timestamp; rating defaults to 0 and notes defaults to empty

#### Scenario: View bookmark detail
- **WHEN** the user clicks a bookmark entry in the library list
- **THEN** a detail view opens showing all fields: thumbnail, title, URL, platform, duration (if available), added_at, category, tags, rating, notes, ai_summary, and ai_tags

#### Scenario: Edit bookmark fields
- **WHEN** the user edits the title, notes, rating, category, or tags in the detail view and saves
- **THEN** the VideoBookmark record is updated in private storage and the list view reflects the changes immediately

#### Scenario: Delete a bookmark
- **WHEN** the user selects "Delete" from the bookmark's context menu or detail view and confirms
- **THEN** the VideoBookmark record is permanently removed from private storage and the local thumbnail file is deleted

### Requirement: Thumbnail caching
The system SHALL download the og:image or favicon for each bookmark at creation time, store it as a local file, and display it as a 64×44 pt rounded thumbnail in all list views. If the remote image cannot be fetched, a platform-specific placeholder is displayed.

#### Scenario: Thumbnail fetched on bookmark creation
- **WHEN** a VideoBookmark is created
- **THEN** the system immediately issues an HTTP GET for the og:image URL (or favicon URL if og:image is absent), saves the file to the private media directory under a content-addressed filename, and sets `thumbnail_path` to the local path

#### Scenario: Thumbnail displayed in list
- **WHEN** the library list renders a bookmark row
- **THEN** the local file at `thumbnail_path` is displayed as a 64×44 pt image with rounded corners

#### Scenario: Thumbnail fetch failure
- **WHEN** the og:image and favicon URLs both fail to download
- **THEN** a platform-specific placeholder icon (e.g. YouTube logo for platform=YouTube, generic video icon for unknown) is shown in the thumbnail slot

### Requirement: List and filtering
The library SHALL display all bookmarks filterable by category, tag(s), platform, star rating range, and date range. The list SHALL be sortable by `added_at`, `rating`, and `title`.

#### Scenario: Filter by category
- **WHEN** the user selects a category node in the category tree sidebar
- **THEN** the main bookmark list shows only bookmarks with `category_id` matching the selected category (and optionally its descendants if "Include subcategories" is enabled)

#### Scenario: Filter by multiple tags
- **WHEN** the user selects two or more tags in the tag filter panel
- **THEN** the list shows only bookmarks whose `tags[]` array contains ALL selected tag IDs (AND logic)

#### Scenario: Filter by rating range
- **WHEN** the user sets a minimum star rating (e.g. ≥ 3 stars)
- **THEN** the list shows only bookmarks with `rating >= 3`

#### Scenario: Sort by rating descending
- **WHEN** the user selects "Rating" as the sort field with descending order
- **THEN** the list reorders so that bookmarks with higher ratings appear first; ties are broken by `added_at` descending

### Requirement: Search
The library SHALL support full-text search on the `title` and `notes` fields of all bookmarks, returning matching results regardless of the active category or tag filters.

#### Scenario: Search by title keyword
- **WHEN** the user types a keyword in the search bar
- **THEN** the library list updates in real time to show only bookmarks whose `title` contains the keyword (case-insensitive substring match)

#### Scenario: Search by notes content
- **WHEN** the user types a phrase that appears only in a bookmark's `notes` field
- **THEN** that bookmark appears in the search results, with the matching text highlighted

#### Scenario: Search with no results
- **WHEN** the user types a query that matches no bookmark's title or notes
- **THEN** the list displays an empty-state message indicating no results were found for the query

#### Scenario: Clear search restores filtered view
- **WHEN** the user clears the search bar after having performed a search
- **THEN** the list reverts to the previously active category/tag/platform filter view
