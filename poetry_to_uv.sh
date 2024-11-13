#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [input_file]"
    echo "If input_file is not provided, the script will look for pyproject.toml in the current directory."
    exit 1
}

# Set input file
if [ "$#" -eq 0 ]; then
    input_file="pyproject.toml"
elif [ "$#" -eq 1 ]; then
    input_file="$1"
else
    usage
fi

# Check if input file exists
if [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' not found."
    exit 1
fi

# Check if the file contains [tool.poetry.dependencies]
if ! grep -q '\[tool\.poetry\.dependencies\]' "$input_file"; then
    echo "Exiting: The input file is not created using Poetry. [tool.poetry.dependencies] section not found."
    exit 1
fi

# Set output file name
full_path=$(realpath "$input_file")
dir_path=$(dirname "$full_path")
output_file="${dir_path}/pyproject.toml"
backup_file="${dir_path}/pyproject.toml.old"

# Create a backup of the input file
rsync -av "$input_file" "$backup_file"
echo "Backup created: $backup_file"

# Read the content of pyproject.toml
content=$(cat "$input_file")

# Extract the name, version, description, and author information
name=$(echo "$content" | grep 'name =' | cut -d '"' -f 2)
version=$(echo "$content" | grep '^version =' | cut -d '"' -f 2)
description=$(echo "$content" | grep 'description =' | cut -d '"' -f 2)
author_name=$(echo "$content" | grep 'authors =' | sed 's/.*\["\(.*\) <.*/\1/')
author_email=$(echo "$content" | grep 'authors =' | sed 's/.*<\(.*\)>.*/\1/')

# Extract Python version
# python_version=$(echo "$content" | grep '^python =' | cut -d '"' -f 2 | sed 's/\^/>=/')
python_version=$(echo "$content" | grep '^python =' | awk '{
  output = $3  
  gsub(/^"/, "", output)
  gsub(/"$/, "", output)
  if (match(output, /^[[:alnum:]]/)) {
    output = "==" output 
  } else {
    # Extract alphanumeric characters and add >=
    gsub(/^[^[:alnum:]]+/, "", output)
    output = ">=" output
  }
  print output
}')

# Remove the python version line
content=$(echo "$content" | sed -e '/^python\s=/d')
# Extract dependencies
dependencies=$(
    echo "$content" |
        sed -n '/\[tool.poetry.dependencies\]/,/\[tool\.poetry\.group\.dev\.dependencies\]/p' |
        sed -e '1d; $d' | \
        grep -v '^$' | \
        sort 
)

# Extract dev dependencies
dev_dependencies=$(
    echo "$content" |
        sed -n '/\[tool.poetry.group.dev.dependencies\]/,/\[build-system\]/p' |
        sed -e '1d; $d' | \
        grep -v '^$' | \
        sort
)

# Function to clean up dependency lines
clean_dependency() {
    if echo "$1" | grep -q 'path\s*=\s*'; then
        echo "$1" | sed -e 's/^.*\s=\s{/# {/g'
    elif echo "$1" | grep -q 'extras'; then
        echo "$1" | sed -e 's/\s=\s//g' \
            -e 's/{.*extras.*\(\[.*\]\).*version"^\(.*\)}/\1>=\2/' \
            -e 's/\"//g' \
            -e 's/^/"/;s/$/"/' # Add double quotes at start and end
    else
        echo "$1" | sed -e 's/\s=\s\"^/>=/g' \
            -e 's/\"//' \
            -e 's/^/"/;s/$/"/' # Add double quotes at start and end
    fi
}

# Create the new pyproject.toml content
cat <<EOF >"$output_file"
[project]
name = "$name"
version = "$version"
requires-python = "$python_version"
description = "$description"
readme = "README.md"
authors = [{name = "$author_name", email = "$author_email"}]
dependencies = [
$(echo "$dependencies" | while read -r line; do
    cleaned=$(clean_dependency "$line")
    [ ! -z "$cleaned" ] && echo "    $cleaned,"
done)
]
[tool.uv]
dev-dependencies = [
$(echo "$dev_dependencies" | while read -r line; do
    cleaned=$(clean_dependency "$line")
    [ ! -z "$cleaned" ] && echo "    $cleaned,"
done)
]
EOF

echo "Converted file created: $output_file"
