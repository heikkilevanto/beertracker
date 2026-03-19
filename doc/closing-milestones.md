# Closing GitHub Milestones

## Problem
The project is currently at version 3.2, but GitHub still shows milestone 2.0 as available/open. This guide explains how to close that milestone.

## Solution

### Option 1: Using GitHub Web Interface (Recommended)

1. Go to https://github.com/heikkilevanto/beertracker/milestones
2. Find the "2.0" milestone in the list
3. Click on the milestone name to view its details
4. Click the "Edit" button (top right of the milestone page)
5. Click the "Close milestone" button at the bottom of the edit page
6. Confirm the closure

### Option 2: Using GitHub CLI (`gh`)

If you have the GitHub CLI installed, you can close milestones from the command line:

```bash
# List all milestones to find the milestone number
gh api repos/heikkilevanto/beertracker/milestones

# Close milestone by number (replace <NUMBER> with the actual milestone number)
gh api -X PATCH repos/heikkilevanto/beertracker/milestones/<NUMBER> -f state=closed
```

### Option 3: Using curl with GitHub API

If you have a GitHub personal access token with repo permissions:

```bash
# Find the milestone number
curl -H "Authorization: token YOUR_TOKEN" \
  https://api.github.com/repos/heikkilevanto/beertracker/milestones

# Close the milestone (replace <NUMBER> with the milestone number)
curl -X PATCH \
  -H "Authorization: token YOUR_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/heikkilevanto/beertracker/milestones/<NUMBER> \
  -d '{"state":"closed"}'
```

## Notes

- Closing a milestone does not delete it; it just marks it as completed
- You can reopen a closed milestone if needed
- Issues associated with the milestone will remain unchanged
- Closed milestones can still be viewed by selecting "Closed" in the milestone filter

## Future Milestones

When releasing a new version and want to close the associated milestone:

1. Ensure all issues in the milestone are resolved or moved to a future milestone
2. Follow one of the methods above to close the milestone
3. Consider creating a new milestone for the next version if not already exists

## Version History Reference

According to `doc/design.md`, the version history is:
- v1.0 Feb'16: First release
- v1.1 Mar'17: Improved lists, graphs, menu
- v1.2 Aug'18: Small improvements
- v1.3 Sep'20: Restaurant entries, graph zoom, summaries
- v1.4 Apr'24: Scrape beer lists, fancy colors, blood alc, caching
- v2.0 Jun'24: Record types on text lines (incompatible)
- v2.1 Oct'24: Last version with text file
- v3.0 Jul'25: SQLite, redesigned UI, split into modules
- v3.1 Aug'25: Rating stats, photos, geo coordinates
- v3.2 Jan'26: Tracking beer taps, prices, AI-assisted refactoring

Current version: v3.2 (see `code/VERSION.pm`)
