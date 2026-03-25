#!/bin/bash -ex

# AI Generated, but seems to work fine

# === Configuration ===
# !!! IMPORTANT: Replace these placeholders with your actual details !!!
REMOTE_USER="hobe"                 # Your username on the remote server
REMOTE_HOST="REPLACE.ME."    # Hostname or IP address of the remote SSH server
LOCAL_SOCKS_PORT="1080"                     # Local port for the SOCKS proxy (1080 is common)
REMOTE_SSH_PORT="22"                        # SSH port on the remote server (usually 22)
# Optional: Specify path to your private key if needed
# SSH_KEY_PATH="/path/to/your/private_key"
# === End Configuration ===

# --- Build SSH command arguments ---
SSH_OPTIONS=""
# Uncomment the following line if using a specific private key
# SSH_OPTIONS+="-i ${SSH_KEY_PATH} "

# The core SSH command for dynamic port forwarding (SOCKS proxy)
# -N: Do not execute a remote command. This is useful for just forwarding ports.
# -D: Specifies a local "dynamic" application-level port forwarding.
#     (We removed the '-f' flag to keep it in the foreground)
SSH_CMD="ssh ${SSH_OPTIONS} -N -D ${LOCAL_SOCKS_PORT} -p ${REMOTE_SSH_PORT} ${REMOTE_USER}@${REMOTE_HOST}"

# --- Print Information and Instructions FIRST ---
# Since SSH runs in the foreground, print usage info before starting it.
echo "--------------------------------------------------"
echo " Preparing to Start SOCKS Proxy"
echo "--------------------------------------------------"
echo " Remote User:      ${REMOTE_USER}"
echo " Remote Host:      ${REMOTE_HOST}"
echo " Remote SSH Port:  ${REMOTE_SSH_PORT}"
echo " Local SOCKS Port: ${LOCAL_SOCKS_PORT}"
echo "--------------------------------------------------"
echo ""
echo "--- Proxy Usage Instructions ---"
echo ""
echo " Once the SSH connection is established below,"
echo " configure your applications to use the proxy:"
echo ""
echo "  Proxy Type: SOCKS5"
echo "  Proxy Host: localhost (or 127.0.0.1)"
echo "  Proxy Port: ${LOCAL_SOCKS_PORT}"
echo ""
echo " Example (run in a *different* terminal):"
echo "   curl --socks5-hostname localhost:${LOCAL_SOCKS_PORT} https://ifconfig.me/ip"
echo "   (This should show the IP address of your remote server: ${REMOTE_HOST})"
echo ""
echo " Browser:"
echo "   Configure your browser's network/proxy settings for SOCKS5"
echo "   using localhost and port ${LOCAL_SOCKS_PORT}."
echo ""
echo "--- How to Stop the Proxy ---"
echo ""
echo "  >>>>> Press CTRL+C in THIS terminal window. <<<<<"
echo ""
echo "--------------------------------------------------"
echo ""
echo "Attempting to establish SSH connection and start proxy..."
echo "Executing command: ${SSH_CMD}"
echo "(Leave this terminal running. Press CTRL+C here to stop the proxy.)"
echo ""

# --- Execute the SSH Command in the Foreground ---
# The script will block here until the SSH connection is terminated (e.g., by Ctrl+C)
${SSH_CMD}

# --- Post-Execution Message (After Ctrl+C or disconnect) ---
# This part will only execute after the ssh command terminates.
SSH_EXIT_STATUS=$? # Capture the exit status of the ssh command

echo ""
echo "--------------------------------------------------"
echo " SSH connection terminated (Exit Status: ${SSH_EXIT_STATUS})."
echo " SOCKS proxy stopped."
echo "--------------------------------------------------"

# Optionally, check the exit status if needed
if [ ${SSH_EXIT_STATUS} -ne 0 ] && [ ${SSH_EXIT_STATUS} -ne 130 ]; then # 130 is often the status for Ctrl+C
  echo "Note: SSH exited with a non-zero status (${SSH_EXIT_STATUS})."
  echo "      This might indicate an issue during connection or termination,"
  echo "      or it could be normal if the connection dropped unexpectedly."
fi

exit ${SSH_EXIT_STATUS}
