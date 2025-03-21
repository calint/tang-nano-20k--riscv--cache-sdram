#!/bin/sh
set -e
cd $(dirname "$0")

# override configuration
. ./configuration.sh

cd ..

if [ "$BITSTREAM_FLASH_TO_EXTERNAL" -eq 1 ]; then
    OPTS="--external-flash"
fi

echo
echo "flashing '$BITSTREAM_FILE' to board '$BOARD_NAME'"
echo

openFPGALoader --board $BOARD_NAME --write-flash $OPTS "$BITSTREAM_FILE"
