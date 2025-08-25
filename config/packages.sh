#!/usr/bin/env bash
TARGET_PACKAGES=(
  "com.zhiliaoapp.musically"    # TikTok
  "com.facebook.katana"         # Facebook
  "com.facebook.orca"           # Messenger
  "com.snapchat.android"        # Snapchat
  "com.twitter.android"         # Twitter/X
  "com.instagram.android"       # Instagram
  "com.whatsapp"                # WhatsApp
)

: "${CUSTOM_PACKAGES_FILE:="$REPO_ROOT/custom_packages.txt"}"
if [[ -f "$CUSTOM_PACKAGES_FILE" ]]; then
  while IFS= read -r pkg; do
    [[ -n "$pkg" && ! "$pkg" =~ ^[[:space:]]*# ]] && TARGET_PACKAGES+=("$pkg")
  done < "$CUSTOM_PACKAGES_FILE"
fi

