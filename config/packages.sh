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

# Friendly name mappings for quick pull results
declare -A FRIENDLY_DIR_MAP=(
  [com.facebook.katana]=facebook_app
  [com.facebook.orca]=messenger
  [com.whatsapp]=whatsapp
  [com.twitter.android]=twitter
  [com.instagram.android]=instagram
  [com.snapchat.android]=snapchat
  [com.zhiliaoapp.musically]=tiktok
)
declare -A FRIENDLY_FILE_MAP=(
  [com.facebook.katana]=facebook_app
  [com.facebook.orca]=messenger_app
  [com.whatsapp]=whatsapp_app
  [com.twitter.android]=twitter_app
  [com.instagram.android]=instagram_app
  [com.snapchat.android]=snapchat_app
  [com.zhiliaoapp.musically]=tiktok_app
)

