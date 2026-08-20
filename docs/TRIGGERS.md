# Reviewed run triggers

Neloa’s triggers prepare the existing run-review experience. They never plan, click, type, upload, send, or otherwise replay an automation in the background.

## Run reminders

An automation can show a local notification every day, on weekdays, or on one selected weekday. Notification content omits the automation name. Opening the notification routes the saved workflow ID into Neloa’s normal “What should change this time?” sheet.

Notification permission is requested only after the user saves an enabled reminder. Removing an automation also removes its pending reminders.

## Shortcut links

The automation menu can copy a link in this form:

```text
neloa://run/WORKFLOW-UUID
```

The URL handler accepts only the `neloa` scheme, the `run` host, and one valid UUID path component. Queries, fragments, extra path components, and other commands are rejected. A valid link opens the reviewed run sheet with no pre-authorized changes.

## Watched folders

A watched-folder trigger is available only when the taught workflow contains a grounded, flexible file input. The user chooses the demonstrated file field, one folder, and a file-type filter. While Neloa is open, it:

1. Takes an initial snapshot so existing files do not trigger a run.
2. Ignores hidden files and common partial-download suffixes.
3. Waits for a new or replaced matching file’s size and modification date to remain stable across scans.
4. Queues one run request containing the exact local path.
5. Accepts that path only from the selected folder and file type.
6. Replaces only the user-selected demonstrated file input in the preview.

The trigger does not add a file picker, upload action, click, or any other replay step. If the file disappears before review, the requested change is rejected. If the folder moves or becomes unreadable, Neloa stops watching it and shows a red status in the automation library.

Watched folders are deliberately active only while Neloa is running. Neloa is not installed as an invisible login item or background daemon.

## Queue behavior

Reminders, run links, and file arrivals share one FIFO run-request queue. A new trigger cannot replace a run that the user is already reviewing. The review sheet shows how many prepared runs remain, and closing or completing the current review advances to the next request. Removing an automation clears its queued requests.

## Verification

`make test` covers trigger parsing, filtering, persistence, legacy decoding, queue order, missing-file rejection, and preservation of captured action IDs. `make trigger-test` exercises a real filesystem watcher with a multi-chunk file write. Both run in GitHub Actions for every push to `main` and every pull request.
