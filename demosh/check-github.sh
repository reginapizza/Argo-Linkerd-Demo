set -e

# This demo _requires_ a few things:
#
# 1. You need to set GITHUB_USER to your GitHub username.
#
# 2. You need to fork https://github.com/reginapizza/Argo-Linkerd-Demo under
#    the $GITHUB_USER account.
#
# 3. You need to clone your fork, and have that clone be in its "main" branch.
#
# 4. You need to be running this script from your "Argo-Linkerd-Demo" clone.
#
# This script verifies that all these things are done.
#
# NOTE WELL: We use Makefile-style escaping in several places, because demosh
# needs it.

# First up, is GITHUB_USER set?
if [ -z "$GITHUB_USER" ]; then \
    echo "GITHUB_USER is not set" >&2 ;\
    exit 1 ;\
fi

# OK. Next up: we should be in the Argo-Linkerd-Demo repo, and our "origin"
# remote should point to a fork of the repo under the $GITHUB_USER account.

origin=$(git remote get-url --all origin)

if [ $(echo "$origin" | grep -c "$GITHUB_USER/Argo-Linkerd-Demo\.git$") -ne 1 ]; then \
    echo "Not in the $GITHUB_USER fork of Argo-Linkerd-Demo" >&2 ;\
    exit 1 ;\
fi

# Next up: we should be in the "main" branch.
if [ $(git branch --show-current) != "main" ]; then \
    echo "Not in the main branch of Argo-Linkerd-Demo" >&2 ;\
    exit 1 ;\
fi

set +e
