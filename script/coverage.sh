#!/usr/bin/env bash

set -euo pipefail

MINIMUM_COV=94
COV_PERCENTAGE=$(forge coverage | grep src/Ploan.sol | tr "|" "\n" | grep "%" | head -n 1 | awk -F '%' '{print $1}')
if [ $(bc <<< "$COV_PERCENTAGE < $MINIMUM_COV") -eq 1 ]; then
    echo "$COV_PERCENTAGE is below minimum coverage threshold ($MINIMUM_COV)";
    exit 1
fi