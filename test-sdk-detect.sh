#!/bin/bash
set -euo pipefail

OPENWRT_VERSION="24.10.0"
TARGET="mediatek"
SUBTARGET="filogic"

# We cannot test this directly here due to network blocks, but we can write the code.
echo "URL will be dynamically found"
