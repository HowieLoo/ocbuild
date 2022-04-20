#!/bin/bash

#
#  covstrap-linux.sh
#  ocbuild
#
#  Copyright © 2018-2022 vit9696, PMheart. All rights reserved.
#

#
#  This script is supposed to quickly bootstrap Coverity Scan environment for GitHub Actions
#  to be later used with OpenCore.
#
#  Latest version available at:
#  https://raw.githubusercontent.com/acidanthera/ocbuild/master/coverity/covstrap-linux.sh
#
#  Example usage:
#  src=$(/usr/bin/curl -Lfs https://raw.githubusercontent.com/acidanthera/ocbuild/master/coverity/covstrap-linux.sh) && eval "$src" || exit 1
#


PROJECT_PATH="$(pwd)"
# shellcheck disable=SC2181
if [ $? -ne 0 ] || [ ! -d "${PROJECT_PATH}" ]; then
  echo "ERROR: Failed to determine working directory!"
  exit 1
fi

if [ "${COVERITY_SCAN_TOKEN}" = "" ]; then
  echo "ERROR: No COVERITY_SCAN_TOKEN provided!"
  exit 1
fi

if [ "${COVERITY_SCAN_EMAIL}" = "" ]; then
  echo "ERROR: No COVERITY_SCAN_EMAIL provided!"
  exit 1
fi

if [ "${GITHUB_REPOSITORY}" = "" ]; then
  echo "ERROR: No GITHUB_REPOSITORY provided!"
  exit 1
fi

# Avoid conflicts with PATH overrides.
CHMOD="/bin/chmod"
CURL="/usr/bin/curl"
MKDIR="/bin/mkdir"
MV="/bin/mv"
RM="/bin/rm"
TAR="/usr/bin/tar"

TOOLS=(
  "${CHMOD}"
  "${CURL}"
  "${MKDIR}"
  "${MV}"
  "${RM}"
  "${TAR}"
)

for tool in "${TOOLS[@]}"; do
  if [ ! -x "${tool}" ]; then
    echo "ERROR: Missing ${tool}!"
    exit 1
  fi
done

if [ "$(which gpg)" = "" ]; then
  echo "ERROR: Missing GPG installation!"
fi

# Download Coverity
COVERITY_ANALYSIS_DIR="${PROJECT_PATH}/cov-analysis"
COVERITY_SCAN_ARCHIVE=cov-analysis.tar.gz
COVERITY_SCAN_LINK="https://scan.coverity.com/download/cxx/linux64"

ret=0
echo "Downloading Coverity analysis tool..."
"${CURL}" -LfsS "${COVERITY_SCAN_LINK}" -d "token=${COVERITY_SCAN_TOKEN}&project=${GITHUB_REPOSITORY}" -o "${COVERITY_SCAN_ARCHIVE}" || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to download Coverity analysis tool with code ${ret}!"
  exit 1
fi

"${TAR}" -xzf cov-analysis.tar.gz
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to decompress Coverity analysis tool with code ${ret}!"
  exit 1
fi

"${MV}" cov-analysis-linux64-* "${COVERITY_ANALYSIS_DIR}"
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to rename cov-analysis-linux64 directory to cov-analysis!"
  exit 1
fi

# Export override variables
export COVERITY_RESULTS_DIR="${PROJECT_PATH}/cov-int"

# Refresh PATH to apply overrides
export PATH="${COVERITY_ANALYSIS_DIR}/bin:${PATH}"

# Run Coverity
# shellcheck disable=SC2086
cov-build --dir "${COVERITY_RESULTS_DIR}" ${COVERITY_BUILD_COMMAND} || ret=$?

if [ $ret -ne 0 ]; then
  echo "ERROR: Coverity build tool failed with code ${ret}!"
  exit 1
fi

# Upload results
COVERITY_RESULTS_FILE=results.tgz
${TAR} czf "${COVERITY_RESULTS_FILE}" -C "${COVERITY_RESULTS_DIR}/.." "$(basename "${COVERITY_RESULTS_DIR}")" || ret=$?

if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to compress Coverity results dir ${COVERITY_RESULTS_DIR} with code ${ret}!"
  exit 1
fi

upload () {
  ${CURL} \
    --form project="${GITHUB_REPOSITORY}" \
    --form token="${COVERITY_SCAN_TOKEN}" \
    --form email="${COVERITY_SCAN_EMAIL}" \
    --form file="@${COVERITY_RESULTS_FILE}" \
    --form version="${GITHUB_SHA}" \
    --form description="GitHub Actions build" \
    "https://scan.coverity.com/builds?project=${GITHUB_REPOSITORY}"
  return $?
}

for i in {1..3}
do
  echo "Uploading results... (Trial $i/3)"
  upload && exit 0 || ret=$?
done

echo "ERROR: Failed to upload Coverity results ${COVERITY_RESULTS_FILE} with code ${ret}!"
exit 1
