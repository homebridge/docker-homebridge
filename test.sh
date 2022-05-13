#!/bin/sh

RELEASE_NAME="some-other"

TARGET_IMAGE_TAG=$(if [ "${{ steps.get_branch.outputs.NAME }}" = "master" ]; then echo "latest"; else echo "${{ steps.get_branch.outputs.NAME }}"; fi;)

echo $TARGET_IMAGE_TAG