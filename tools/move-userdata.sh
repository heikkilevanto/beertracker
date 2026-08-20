#! /usr/bin/bash

# Move each user's graph files, plot/cmd files, and photo directory into a
# `beerdata/<username>/` subdirectory (issue 748). Idempotent, safe to re-run.
# Run from the repo root, after `git pull` of the new code (production step).

cd beerdata || exit 1

users=""

# Find users via .photo dirs
for d in *.photo; do
  [ -d "$d" ] || continue
  base="${d%.photo}"
  [[ "$base" =~ ^[a-zA-Z0-9]+$ ]] || continue
  users="${users}${base} "
done
# Find users via .plot files (exclude -pr/-price variants: user names are alnum)
for f in *.plot; do
  [ -f "$f" ] || continue
  base="${f%.plot}"
  [[ "$base" =~ ^[a-zA-Z0-9]+$ ]] || continue
  users="${users}${base} "
done

# Deduplicate, keep order
users=$(printf "%s\n" $users | awk '!seen[$0]++' | tr '\n' ' ')

for u in $users; do
  echo "== User: $u"
  mkdir -p "$u" || exit 1
  if [ -d "$u.photo" ]; then
    if [ -e "$u/$u.photo" ]; then
      echo "  skip: $u.photo already in subdir"
    else
      mv "$u.photo" "$u/$u.photo"
      echo "  moved: $u.photo -> $u/$u.photo"
    fi
  fi
  for f in "$u"*; do
    [ -e "$f" ] || continue
    if [ -d "$f" ]; then
      continue  # other user's dir or the subdir itself
    fi
    base="${f##*/}"
    case "$f" in
      *.data)
        rm -f "$f"
        echo "  deleted legacy archive: $f"
        ;;
      *)
        if [ -e "$u/$base" ]; then
          echo "  skip: $base already in subdir"
        else
          mv "$f" "$u/$base"
          echo "  moved: $base -> $u/$base"
        fi
        ;;
    esac
  done
done