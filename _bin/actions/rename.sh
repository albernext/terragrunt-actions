#!/bin/bash

case "$1" in
    plan-rename)
        if [[ $TF_STATE_RENAMED_FILES == "" ]]; then
            echo "No files are going to be renamed."
            exit 0
        fi

        # For every file that is going to be renamed, in the state bucket...
        for file in $TF_STATE_RENAMED_FILES; do
            new_file=$(echo $file | cut -d ',' -f2)

            # Check if the file exists in the new path
            if aws s3 ls s3://$TF_STATE_BUCKET/$new_file > /dev/null; then
                echo "The file $new_file already exists in the state bucket."
                exit 1
            fi
        done

        echo "In the bucket $TF_STATE_BUCKET, the following files are going to be renamed:"

        # For every file that is going to be renamed, in the state bucket...
        for file in $TF_STATE_RENAMED_FILES; do
            old_file=$(echo $file | cut -d ',' -f1)
            new_file=$(echo $file | cut -d ',' -f2)

            echo "$old_file -> $new_file"

            # Copy file to the new path
            aws s3 cp s3://$TF_STATE_BUCKET/$old_file s3://$TF_STATE_BUCKET/$new_file > /dev/null
        done

        echo

        echo "In the table $TF_LOCKS_TABLE, the following items are going to be renamed:"

        # For every file that is going to be renamed, in the locks table...
        for file in $TF_STATE_RENAMED_FILES; do
            old_file=$(echo $file | cut -d ',' -f1)
            new_file=$(echo $file | cut -d ',' -f2)
            digest="$(aws dynamodb get-item --table-name $TF_LOCKS_TABLE --key "{\"LockID\": {\"S\": \"$TF_STATE_BUCKET/$old_file-md5\"}}" | jq -Mr '.Item.Digest.S')"

            echo "LockID = $TF_STATE_BUCKET/$old_file-md5 -> LockID = $TF_STATE_BUCKET/$new_file-md5"

            # Create new item with the new path and the same digest
            aws dynamodb update-item \
                --table-name $TF_LOCKS_TABLE \
                --key "{\"LockID\": {\"S\": \"$TF_STATE_BUCKET/$new_file-md5\"}}" \
                --update-expression "SET Digest = :d" \
                --expression-attribute-values "{\":d\": {\"S\": \"$digest\"}}"
        done
    ;;
    post-plan-rename)
        # For every file that is going to be renamed...
        for file in $TF_STATE_RENAMED_FILES; do
            old_file=$(echo $file | cut -d ',' -f1)
            new_file=$(echo $file | cut -d ',' -f2)

            # Delete the copy of the file in the new path in the state bucket
            aws s3 rm s3://$TF_STATE_BUCKET/$new_file

            # Delete item with the new path in the locks table
            aws dynamodb delete-item \
                --table-name $TF_LOCKS_TABLE \
                --key "{\"LockID\": {\"S\": \"$TF_STATE_BUCKET/$new_file-md5\"}}"
        done
    ;;
    rename)
        # For every file that is going to be renamed...
        for file in $TF_STATE_RENAMED_FILES; do
            old_file=$(echo $file | cut -d ',' -f1)
            new_file=$(echo $file | cut -d ',' -f2)
            digest="$(aws dynamodb get-item --table-name $TF_LOCKS_TABLE --key "{\"LockID\": {\"S\": \"$TF_STATE_BUCKET/$old_file-md5\"}}" | jq -Mr '.Item.Digest.S')"

            # Move file to the new path in the state bucket
            aws s3 mv s3://$TF_STATE_BUCKET/$old_file s3://$TF_STATE_BUCKET/$new_file

            # Delete item with the old path in the locks table
            aws dynamodb delete-item \
                --table-name $TF_LOCKS_TABLE \
                --key "{\"LockID\": {\"S\": \"$TF_STATE_BUCKET/$old_file-md5\"}}"
            # Create new item with the new path and the same digest
            aws dynamodb update-item \
                --table-name $TF_LOCKS_TABLE \
                --key "{\"LockID\": {\"S\": \"$TF_STATE_BUCKET/$new_file-md5\"}}" \
                --update-expression "SET Digest = :d" \
                --expression-attribute-values "{\":d\": {\"S\": \"$digest\"}}"
        done
    ;;
esac
