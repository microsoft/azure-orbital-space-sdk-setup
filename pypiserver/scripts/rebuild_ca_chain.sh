#!/bin/bash

# Directory containing additional certificates
EXTRA_CERTS_DIR="/usr/local/share/ca-certificates"
# Destination certificate bundle
DEST_BUNDLE="/etc/ssl/certs/ca-certificates.crt"

# Check if EXTRA_CERTS_DIR exists
if [ ! -d "$EXTRA_CERTS_DIR" ]; then
  echo "Directory $EXTRA_CERTS_DIR does not exist. Creating it now."
  mkdir -p "$EXTRA_CERTS_DIR"
fi

# Create a temporary directory for processing
TEMP_DIR=$(mktemp -d)

# Extract and format existing certificates if required
if [ -f "$DEST_BUNDLE" ]; then
  c=0
  sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' "$DEST_BUNDLE" | while IFS= read -r line; do
    echo "$line" >> "$TEMP_DIR/cert$c.crt"
    [[ "$line" =~ "-----END CERTIFICATE-----" ]] && c=$((c + 1))
  done
fi

# Copy new certificates to the temporary directory
cp "$EXTRA_CERTS_DIR"/*.crt "$TEMP_DIR/"

# Concatenate all certificates into the destination bundle
cat "$TEMP_DIR"/*.crt | tee "$DEST_BUNDLE" > /dev/null

# Clean up temporary directory
rm -r "$TEMP_DIR"

# Verify the new bundle
echo "Verification: Checking for newly added certificates in $DEST_BUNDLE"
for CERT in "$EXTRA_CERTS_DIR"/*.crt; do
  CERT_NAME=$(basename "$CERT")
  grep -q "$(openssl x509 -in "$CERT" -noout -subject)" "$DEST_BUNDLE" && echo "$CERT_NAME has been added successfully" || echo "Warning: $CERT_NAME was not added"
done

echo "CA certificates bundle has been rebuilt successfully."