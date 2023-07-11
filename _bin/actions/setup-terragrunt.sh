#!/bin/bash

dir="$HOME/.local/bin"
file="$dir/terragrunt"

curl -sSLO "https://github.com/gruntwork-io/terragrunt/releases/download/v0.48.1/terragrunt_linux_amd64"

mkdir -p "$dir"
mv terragrunt_linux_amd64 "$file"

chmod +x "$file"
