#!/bin/bash

TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
COUNT=$(git rev-list "$TAG"..HEAD --count 2>/dev/null || echo "0")
DATE=$(date +"%Y-%m-%d %H:%M:%S ")
COMMIT=$(git rev-parse --short HEAD)
BRANCH=$(git rev-parse --abbrev-ref HEAD)

cat > VERSION.pm <<EOF
package Version;
# Auto-generated file. Do not edit !!

use strict;
use warnings;

sub version_info {
    return {
        tag     => '$TAG',
        commits => $COUNT,
        date    => '$DATE',
        commit  => '$COMMIT',
        branch  => '$BRANCH',
    };
}

1;
EOF

git add VERSION.pm

