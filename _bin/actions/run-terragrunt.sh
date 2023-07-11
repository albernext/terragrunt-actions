#!/bin/bash

# Change to the directory of the repo
cd "$GITHUB_WORKSPACE/terragrunt-gitops"

# --terragrunt-non-interactive option: assume yes for all prompts; necessary since the script is not run interactively
# All operations are run like (cmd1 && cmd2 && ...) || exit 1 so if any of them fails, the script run fails

case "$1" in
    validate)
        (
            terragrunt init \
                -upgrade \
                --terragrunt-working-dir "$TERRAGRUNT_WORKDIR" \
                --terragrunt-non-interactive \
            && \
            terragrunt validate \
                --terragrunt-working-dir "$TERRAGRUNT_WORKDIR" \
                --terragrunt-non-interactive \
            && \
            terragrunt validate-inputs \
                --terragrunt-working-dir "$TERRAGRUNT_WORKDIR" \
                --terragrunt-non-interactive
        ) || exit 1
    ;;
    plan)
        (
            terragrunt plan \
                --terragrunt-working-dir "$TERRAGRUNT_WORKDIR" \
                -out=plan
        ) || exit 1

        # Save plan in JSON format so it can be easily parsed using jq
        terragrunt show --terragrunt-working-dir "$TERRAGRUNT_WORKDIR" -json plan > plan.json

        # Get how many resources are going to be created, updated and deleted and save the count in their respective outputs
        for op in create update delete; do
            count=$(jq -Mr "[.resource_changes[].change.actions | select(. == [\"$op\"])] | length" plan.json)
            echo "terragrunt_plan_$op=$count" >> $GITHUB_OUTPUT
        done

        # If a resource shows create and delete actions, that means it is going to be replaced; get the count and save it in the output
        count=$(jq -Mr "[.resource_changes[].change.actions | select (. == [\"create\", \"delete\"] or . == [\"delete\", \"create\"])] | length" plan.json)
        echo "terragrunt_plan_replace=$count" >> $GITHUB_OUTPUT
    ;;
    apply)
        (
            terragrunt init \
                -upgrade \
                --terragrunt-working-dir "$TERRAGRUNT_WORKDIR" \
                --terragrunt-non-interactive \
            && \
            terragrunt apply \
                --terragrunt-working-dir "$TERRAGRUNT_WORKDIR" \
                --terragrunt-non-interactive \
                -auto-approve
        ) || exit 1
    ;;
    plan-destroy)
        (
            terragrunt init \
                -upgrade \
                --terragrunt-working-dir "$TERRAGRUNT_WORKDIR" \
                --terragrunt-non-interactive \
            && \
            terragrunt plan \
                -destroy \
                --terragrunt-working-dir "$TERRAGRUNT_WORKDIR" \
                -out=plan
        ) || exit 1

        # Save plan in JSON format so it can be easily parsed using jq
        terragrunt show --terragrunt-working-dir "$TERRAGRUNT_WORKDIR" -json plan > plan.json

        # Get how many resources are going to be deleted and save the count in the output
        # No other actions (e.g. create) should appear since the operation is purely destructive
        count=$(jq -Mr "[.resource_changes[].change.actions | select(. == [\"delete\"])] | length" plan.json)
        echo "terragrunt_plan_delete=$count" >> $GITHUB_OUTPUT
    ;;
    apply-destroy)
        (
            terragrunt init \
                -upgrade \
                --terragrunt-working-dir "$TERRAGRUNT_WORKDIR" \
                --terragrunt-non-interactive \
            && \
            terragrunt apply \
                -destroy \
                --terragrunt-working-dir "$TERRAGRUNT_WORKDIR" \
                --terragrunt-non-interactive \
                -auto-approve
        ) || exit 1
    ;;
    plan-summary)
        dir="$HOME/.local/bin"

        cd "/tmp"

        # Download tf-summarize tool and unzip the package
        curl -sSLO "https://github.com/dineshba/terraform-plan-summary/releases/download/v0.3.2/tf-summarize_linux_amd64.zip"
        unzip -q tf-summarize_linux_amd64.zip

        chmod +x tf-summarize

        mkdir -p "$dir"
        mv tf-summarize "$dir"

        cd "$GITHUB_WORKSPACE/terragrunt-gitops"

        # Pipe the plan in JSON format to tf-summarize
        terragrunt show --terragrunt-working-dir "$TERRAGRUNT_WORKDIR" -json plan | tf-summarize
    ;;
    *)
        echo "ERROR: unknown option."
        echo "Try validate/plan/apply/plan-destroy/apply-destroy/rollback/cloud-conformity-scan"
        exit 1
    ;;
esac

# Go back to the original working directory
cd "$GITHUB_WORKSPACE"
