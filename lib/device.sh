#!/bin/bash
pick_device() {
    if [[ -n "$DEVICE" ]]; then
        # Device already set (via argument or earlier selection)
        return
    fi

    # Get list of connected devices (skip header line)
    mapfile -t devices < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')

    if [[ ${#devices[@]} -eq 0 ]]; then
        log "ERROR: No devices detected."
        exit 1

    elif [[ ${#devices[@]} -eq 1 ]]; then
        DEVICE="${devices[0]}"
        log "INFO: Automatically selected device: $DEVICE"

    else
        echo ""
        echo "Connected devices:"
        for i in "${!devices[@]}"; do
            printf "  %2d) %s\n" $((i+1)) "${devices[$i]}"
        done

        read -rp "Select device [1-${#devices[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#devices[@]} )); then
            DEVICE="${devices[$((choice-1))]}"
            log "INFO: Selected device: $DEVICE"
        else
            log "ERROR: Invalid selection."
            exit 1
        fi
    fi
}
