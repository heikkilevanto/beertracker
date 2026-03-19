#!/bin/bash
#
# Helper script to close GitHub milestones
#
# Usage: ./tools/close-milestone.sh [milestone-title]
# Example: ./tools/close-milestone.sh "2.0"
#
# Requires: gh (GitHub CLI) - https://cli.github.com/
#

set -e

REPO="heikkilevanto/beertracker"

if [ -z "$1" ]; then
    echo "Usage: $0 <milestone-title>"
    echo "Example: $0 '2.0'"
    echo ""
    echo "Available milestones:"
    gh api "repos/$REPO/milestones?state=open" --jq '.[] | "\(.number): \(.title) (\(.open_issues) open issues)"'
    exit 1
fi

MILESTONE_TITLE="$1"

echo "Searching for milestone: $MILESTONE_TITLE"

# Find the milestone by title
MILESTONE_DATA=$(gh api "repos/$REPO/milestones?state=open" --jq ".[] | select(.title == \"$MILESTONE_TITLE\")")

if [ -z "$MILESTONE_DATA" ]; then
    echo "Error: Milestone '$MILESTONE_TITLE' not found in open milestones."
    echo ""
    echo "Open milestones:"
    gh api "repos/$REPO/milestones?state=open" --jq '.[] | "  \(.title)"'
    exit 1
fi

MILESTONE_NUMBER=$(echo "$MILESTONE_DATA" | jq -r '.number')
OPEN_ISSUES=$(echo "$MILESTONE_DATA" | jq -r '.open_issues')

echo "Found milestone #$MILESTONE_NUMBER: $MILESTONE_TITLE"
echo "Open issues: $OPEN_ISSUES"

if [ "$OPEN_ISSUES" -gt 0 ]; then
    echo ""
    echo "Warning: This milestone has $OPEN_ISSUES open issue(s)."
    echo "Issues in this milestone:"
    gh api "repos/$REPO/issues?milestone=$MILESTONE_NUMBER&state=open" --jq '.[] | "  #\(.number): \(.title)"'
    echo ""
    read -p "Do you want to close the milestone anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

echo ""
echo "Closing milestone #$MILESTONE_NUMBER: $MILESTONE_TITLE"

# Close the milestone
gh api -X PATCH "repos/$REPO/milestones/$MILESTONE_NUMBER" -f state=closed

echo "✓ Milestone '$MILESTONE_TITLE' has been closed successfully!"
echo ""
echo "View closed milestones at: https://github.com/$REPO/milestones?state=closed"
