#!/bin/bash

while IFS= read -r line; do
    if [[ $line == variable* ]]; then
        var_name=$(echo $line | cut -d'"' -f2 | tr '[:lower:]' '[:upper:]')
        echo -n "export $var_name="
    elif [[ $line == *default* ]]; then
        var_value=$(echo $line | cut -d'"' -f2)
        echo "\"$var_value\""
    fi
done < variable.pkr.hcl