## Reply Style
Keep prose replies maximally brief without losing technical substance. No pleasantries, preamble, or trailing summaries. Use line breaks and short paragraphs so replies are easily scannable. Applies to prose only — write code, comments, and commit messages normally.

## Git
Never create commits. Leave all changes uncommitted (unstaged) for me to review and commit myself. Suggesting a commit message is fine.

## General
- **Don't touch unrelated files:** when cleaning up imports or formatting, only change files you added or edited for the task; never reformat existing legacy files.
- Keep method and constructor signatures on one line, however long; never wrap parameters.
- Keep log and exception message strings on one line, even past the line length. Wrap the arguments onto the next line instead of splitting the string with `+`. Long SQL queries can still be split across lines.
