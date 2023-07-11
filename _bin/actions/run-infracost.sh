#!/bin/bash

cd "$GITHUB_WORKSPACE/terragrunt-gitops"

# Run Infracost in every dir
for workdir in $TERRAGRUNT_WORKDIRS; do
    (
        # Remove / and - from dir name to get a valid filename
        workdir_h=$(echo $workdir | tr / -)
        repodir="$GITHUB_WORKSPACE/terragrunt-gitops-$workdir_h"

        cp -a "$GITHUB_WORKSPACE/terragrunt-gitops" "$repodir"
        cd "$repodir"

        # Switch to main branch
        git checkout main
        
        if [[ "$(ls $workdir)" != "" ]]; then
            # If dir exists in base branch, get costs
            infracost breakdown --path=$workdir \
                                --format=json \
                                --out-file="/tmp/base-infracost-$workdir_h.json"

            # Switch to head branch
            git checkout $HEAD_REF

            # Compare costs in head branch to the ones in base branch
            infracost diff --path=$workdir \
                        --format=json \
                        --compare-to="/tmp/base-infracost-$workdir_h.json" \
                        --out-file="/tmp/infracost-$workdir_h.json"
        else
            # Switch to head branch
            git checkout $HEAD_REF

            # If dir doesn't exist in base branch, get costs directly from head branch
            infracost breakdown --path=$workdir \
                                --format=json \
                                --out-file="/tmp/infracost-$workdir_h.json"
        fi
    ) &
done

wait

# Post comment to PR
infracost comment github --path="/tmp/infracost-*.json" \
                         --repo=$REPO \
                         --github-token=$GITHUB_TOKEN \
                         --pull-request=$PULL_REQUEST_NUMBER \
                         --behavior=update

cd "$GITHUB_WORKSPACE"
