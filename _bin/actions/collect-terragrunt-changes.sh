#!/bin/bash

get_path_level() {
    echo "$2" | cut -d '/' -f$1
}

ignored_files=(
    "README.md"
    "CODEOWNERS"
)

cd "$GITHUB_WORKSPACE/terragrunt-gitops"

# Get all accounts: list all directories that don't start with _ or .
accounts=$(for d in *; do if [[ -d "$d" ]]; then [[ $d == _* ]] || echo $d; fi; done)

# For every new/modified/deleted file
for file in $CHANGED_AND_MODIFIED_FILES; do
    # Skip if file is ignored
    [[ " ${ignored_files[@]} " =~ " ${file##*/} " ]] && continue

    dir="$(dirname $file)"              # Directory where the file is
    d="$(get_path_level 1 "$file")"     # First level directory (AWS account)
    piece="$(get_path_level 2 "$file")" # Second level directory
    unset dirlist

    if [[ -d "$dir" ]]; then
        # If first level directory is _common, add all accounts that use that solution
        if [[ "$d" == "_common" ]]; then
            for account in $accounts; do
                if [[ -d "$account/$piece" ]]; then
                    dirlist="$dirlist $account/$piece"
                fi
            done
        else
            dirlist="$dir"
        fi

        for direc in $dirlist; do
            # Check if there is a hcl file in the directory or subdirectories. 
            # If not, we are in a configuration folder and we don't want to run terragrunt in it.
            # direc is the first parent directory with an *.hcl file.
            while [[ -z $(find "$direc" -type f -name "*.hcl") ]]; do 
                direc="$(dirname "$direc")"
            done

            # We ignore the directories that start with . or _ because we don't want to run terragrunt in them.
            # If the directory starts with ., it means that it is a hidden directory or root directory.
            # If the directory starts with _, it means that it is _common or _template folder and we don't want to run terragrunt in it.
            if [[ "$direc" != .* && "$direc" != _* ]]; then
                # TERRAGRUNT_WORKDIRS will contain all the directories where terragrunt is going to be run.
                for f in $(find "$direc" -type f -name "terragrunt.hcl"); do
                    TERRAGRUNT_WORKDIRS="$TERRAGRUNT_WORKDIRS $(dirname $f)"
                done
            fi
        done
    else
        # If first level directory is _common, check that every usage has been deleted, otherwise fail
        if [[ "$d" == "_common" ]]; then
            used=0
            for account in $accounts; do
                if [[ -d "$account/$piece" ]]; then
                    used=1
                fi
            done

            if [[ $used -eq 1 ]]; then
                echo "ERROR: attempting to remove a directory in _common that is being used." >&2
                echo "Please remove all usages first." >&2
                exit 1
            fi
        # Add dir if it doesn't start with . or _ and file is a hcl or a tfvars
        else
            current_branch="$(git branch --show-current)"

            git checkout main

            # If there is a hcl file in dir and dir doesn't start with . or _, add all child directories with terragrunt.hcl files
            if [[ -n $(find "$dir" -maxdepth 1 -type f -name "*.hcl") && "$dir" != .* && "$dir" != _* ]]; then
                for f in $(find "$dir" -type f -name "terragrunt.hcl"); do
                    TERRAGRUNT_DELETED_DIRS="$TERRAGRUNT_DELETED_DIRS $(dirname $f)"
                done
            fi

            git checkout "$current_branch"
        fi
    fi
done

for file_pair in $OLD_NEW_RENAMED_FILES; do
    old_file=$(echo $file_pair | cut -d ',' -f1)
    new_file=$(echo $file_pair | cut -d ',' -f2)

    # If old file is a terragrunt.hcl file, add tfstate file pair to TERRAGRUNT_TFSTATE_RENAMED_FILES
    if [[ "$(basename $old_file)" == terragrunt.hcl ]]; then
        old_tfstate_file="$(dirname $old_file)/terraform.tfstate"
        new_tfstate_file="$(dirname $new_file)/terraform.tfstate"
        tfstate_file_pair="$old_tfstate_file,$new_tfstate_file"

        TERRAGRUNT_TFSTATE_RENAMED_FILES="$TERRAGRUNT_TFSTATE_RENAMED_FILES $tfstate_file_pair"
    fi
done

# Remove duplicates
TERRAGRUNT_WORKDIRS=$(echo $TERRAGRUNT_WORKDIRS | xargs -n1 | sort | uniq | xargs)
TERRAGRUNT_DELETED_DIRS=$(echo $TERRAGRUNT_DELETED_DIRS | xargs -n1 | sort | uniq | xargs)

echo "Directories where Terragrunt Sync is going to be run: $TERRAGRUNT_WORKDIRS"
echo "Directories where Terragrunt Destroy is going to be run: $TERRAGRUNT_DELETED_DIRS"

TERRAGRUNT_WORKDIRS_NOFMT=$TERRAGRUNT_WORKDIRS
TERRAGRUNT_WORKDIRS=$(for dir in $TERRAGRUNT_WORKDIRS; do echo $dir; done | jq -R -s -c 'split("\n")[:-1]')
TERRAGRUNT_DELETED_DIRS=$(for dir in $TERRAGRUNT_DELETED_DIRS; do echo $dir; done | jq -R -s -c 'split("\n")[:-1]')

# Set GH Actions outputs
echo "terragrunt_workdirs_nofmt=$TERRAGRUNT_WORKDIRS_NOFMT" >> $GITHUB_OUTPUT
echo "terragrunt_workdirs=$TERRAGRUNT_WORKDIRS" >> $GITHUB_OUTPUT
echo "terragrunt_deleted_dirs=$TERRAGRUNT_DELETED_DIRS" >> $GITHUB_OUTPUT
echo "terragrunt_tfstate_renamed_files=$TERRAGRUNT_TFSTATE_RENAMED_FILES" >> $GITHUB_OUTPUT

cd "$GITHUB_WORKSPACE"
