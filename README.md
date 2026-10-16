# Find/replace practice with checked backup and undo

PowerShell 7.4+ on Windows or Ubuntu; Ubuntu requires /usr/bin/test (coreutils).
Use only fictional practice in a new empty lesson folder first. Open pwsh,
not Windows PowerShell5.1 or Command Prompt. Do not bypass an execution-policy
or security restriction: use your normal approved script workflow.

    ./make_sample.ps1
    ./fr.ps1 count 'Project Bluebird'
    ./fr.ps1 preview 'Project Bluebird' 'Project Heron'
    ./check39.ps1 snapshot
    ./fr.ps1 backup
    ./fr.ps1 apply 'Project Bluebird' 'Project Heron'
    ./fr.ps1 diff
    ./fr.ps1 undo
    ./check39.ps1 verify
    ./test_fr.ps1

Setup refuses an existing notes path. Backups are kept beside root as
notes.fr-backup. Existing backups are refused and never deleted by the tool.
Use a different new empty lesson folder for another practice round.

## Narrow contract

Only case-sensitive literal single-line replacement, not regex. A BOM is content
for matching purposes: do not target the BOM marker itself. Only UTF8
.txt contents, including UTF8 BOM and existing newline bytes. Invalid UTF8,
NUL content, case-colliding selected names and unsupported filesystem entries
are refused.1-1000 selected files,1MiB each,10MiB total,2000 tree entries.
Parent-traversal root spellings are refused before normalization.
Source/backup paths are literal and checked for links/reparse points and
hardlinks. Ubuntu uses /usr/bin/test to reject special entries because a
PowerShell metadata probe misidentified a FIFO as regular. No hostile race
or concurrent tree-change protection is promised. Stop editors and sync.

Apply binds backup to canonical root, selected inventory and original digests.
It validates every backup/source before writes and saves its plan in a journal.
Undo verifies the backup and every current selected file against original or
planned bytes before restoring anything. Other edits refuse the preflight.
A partial apply can leave a mix of original/planned bytes; undo supports this
state. Injected second-write failure/recovery is tested on fictional files.
A storage failure during writes or restore can still leave a partial state.
Keep the backup and journal, inspect before taking any recovery action.

Multi-file writes are NOT transactional. Renaming a staged file avoids
truncating another hardlink inode, but file metadata (permissions, timestamps,
ownership, streams etc.) is NOT restored. This is not a backup product,
security boundary or real-data validator. Paths, matched lines and journal
replacement text can be private. No upload/network code is used; cloud sync
and other software are outside this tool's control.

check39.ps1 only compares the three known fictional file names and original
SHA256 digests. It does not validate real folders or adversarial trees.
Tests/recorder create and remove only their own unique temporary folders.
Two Windows replays pass50checks (one Unix-only group skipped); two Ubuntu
replays pass52checks, including pipe and case-collision cases. Per-platform
pairs differ only in their unique temporary folder path in the expected
missing-backup refusal. The visible lesson uses first Windows output.
23phone stages and four exact clipboard values pass at320/390/1280 without
page overflow or JavaScript errors; actual pixels inspected. These are fixture
checks, not Windows desktop or real-data validation. Lesson/source uses MIT;
PowerShell/.NET are separately installed with their own licenses, not bundled.

Sources:
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-childitem?view=powershell-7.6
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_filesystem_provider?view=powershell-7.6
- https://learn.microsoft.com/en-us/dotnet/api/system.text.utf8encoding.-ctor?view=net-10.0
- https://learn.microsoft.com/en-us/dotnet/api/system.io.filemode?view=net-10.0
- https://learn.microsoft.com/en-us/dotnet/api/system.io.file.move?view=net-10.0
