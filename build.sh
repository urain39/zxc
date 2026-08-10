#!/bin/sh

# Build script configuration
TEMPLATE="zxc.sh"
OUTPUT="${HOME}/.local/bin/zxc"
SOFA_SOURCE="ClubFritz4.sofa"

# Check if required files exist
if [ ! -f "${TEMPLATE}" ]; then
  echo "Error: Template file '${TEMPLATE}' not found."
  exit 1
fi

if [ ! -f "${SOFA_SOURCE}" ]; then
  echo "Error: Source SOFA file '${SOFA_SOURCE}' not found."
  exit 1
fi

echo "Building ${OUTPUT} from ${TEMPLATE} with ${SOFA_SOURCE}..."

mkdir -p "${OUTPUT%/*}"
{
  # Extract the script part before the placeholder
  sed '/^#@DEFAULT_SOFA@$/,$d' "${TEMPLATE}"

  # Encode and append the SOFA file in base64
  base64 "${SOFA_SOURCE}"
} > "${OUTPUT}"

# Make the output file executable
chmod +x "${OUTPUT}"

echo "Build successful: ${OUTPUT}"
