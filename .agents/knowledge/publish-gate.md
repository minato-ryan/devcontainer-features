# Clean-context Publish Gate

Read and follow this gate before every delegated `git push` and every delegated
public GitHub write (creating or editing an Issue, Pull Request, comment, or
review reply). Published content on a public repository is indexed and mirrored
within minutes and cannot be reliably deleted.

Local `git commit` continues to follow `.agents/knowledge/git-workflow.md`
self-inspection and the pre-commit `gitleaks` hook.

## 1. Assemble the exact payload outside the repository

1. Run `git fetch origin` so `origin/main` is current.
2. Create a temporary directory outside the repository (`mktemp -d`) so review
   files can never be staged or committed.
3. Write the exact files to publish:
   - `git push` or pull request: `commits.txt` from
     `git log origin/main..HEAD --format=full`, `diff.patch` from
     `git diff origin/main...HEAD`; for a pull request, also include `title.txt`
     and `body.md`.
   - Issue: `title.txt` and `body.md`.
   - Comment or review reply: `body.md` and any quoted lines.
   - Include any pasted command or build output inside `body.md` so it is
     reviewed as well.

## 2. Dispatch a clean-context read-only subagent

Invoke a read-only subagent with no prior conversation context and pass only
this prompt (replacing `<DIR>` with the scratch directory path):

```text
Review the files in <DIR> before they are published to a public GitHub repository, where they are indexed,
mirrored, and cannot be reliably deleted. Judge only what the files contain.
1. List the files. If the directory is empty, a pull request lacks commits.txt or diff.patch, or a file is
   unreadable, end with SAFE TO PUBLISH: NO.
2. Check every line for: secrets and credentials (tokens, keys, passwords, private keys, auth headers); personal
   data (real names, personal emails, phone numbers, addresses; placeholders like name@example.com are fine);
   internal-only context (private hostnames, internal URLs, private local paths or branch names); co-author
   trailers (`Co-authored-by:`) or AI/tool-generated markers ("Generated with ...", tool signatures, robot
   attribution); content unrelated to the stated change; @-mentions or cross-references that would notify
   uninvolved people; hostile or regret-worthy wording.
3. Report one line per finding: file, excerpt with secret values masked, category, required fix; or "No findings."
4. Your last line must be exactly SAFE TO PUBLISH: YES or SAFE TO PUBLISH: NO. Any secret, personal data,
   internal context, or attribution finding means NO.
```

If subagent support is unavailable, re-read every file from disk against the
same checklist and write `Review mode: file-only (not clean-context)` above your
verdict.

## 3. Gate decision, publish, verify, and clean up

- Anything other than a final line of exactly `SAFE TO PUBLISH: YES` is `NO`:
  fix every finding (amending commits or editing drafts as needed), rebuild the
  scratch directory, and re-run the review.
- Publish strictly what passed review; any subsequent edit requires a fresh
  review.
- After publishing, read back the published GitHub object (`gh pr view` or
  `gh issue view`) to confirm, and delete the temporary `<DIR>`.
- If a secret ever reached GitHub, treat it as compromised and notify the
  maintainer immediately so it can be rotated.
