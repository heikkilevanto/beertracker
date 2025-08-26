#!/bin/sh

# Print a warning when git pull finds a modified db.schema
# Should be invoked from .git/hooks/post-merge

# File to watch
WATCHED_FILE="db.schema"

# Check if the file changed between ORIG_HEAD and HEAD
if git diff --name-only ORIG_HEAD HEAD | grep -q "^$WATCHED_FILE$"; then
  echo
  echo "WARNING: The database script '$WATCHED_FILE' has changed. "
  echo "Please run scripts/dbchange.sh"
fi
