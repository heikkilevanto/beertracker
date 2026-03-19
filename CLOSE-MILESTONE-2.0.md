# Quick Guide: Closing Milestone 2.0

Since the project is now at version 3.2 (and milestone 2.0 was completed in June 2024), you need to close the milestone on GitHub.

## Easiest Method: GitHub Web Interface

1. Visit: https://github.com/heikkilevanto/beertracker/milestones
2. Find "2.0" in the milestone list
3. Click on it to open the milestone page
4. Click "Edit" (top right)
5. Click "Close milestone" at the bottom
6. Done!

## Alternative: Using the Command Line

If you have GitHub CLI (`gh`) installed:

```bash
cd /home/runner/work/beertracker/beertracker
./tools/close-milestone.sh "2.0"
```

The script will:
- Find the milestone
- Show any open issues (if any)
- Ask for confirmation
- Close the milestone

## What This Does

- Marks milestone 2.0 as "closed" on GitHub
- Does NOT delete it (you can still view closed milestones)
- Does NOT affect any issues associated with it
- Simply indicates the milestone is complete

## For Future Versions

See `doc/closing-milestones.md` for complete documentation on managing milestones, including how to close future milestones when releasing new versions.
