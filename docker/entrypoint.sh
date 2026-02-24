#!/usr/bin/env bash
set -euo pipefail

# Check for commandline arguments
if [[ $# -gt 0 ]]; then
    case "${1}" in
        # If we get a valid mode, set SLURM_WEB_MODE and shift the arguments.
        agent|gateway|ldap-check|gen-jwt-key|show-conf|connect-check|--version|-v|--help|-h)
            SLURM_WEB_MODE="$1"
            echo "Using command-line argument for SLURM_WEB_MODE: ${SLURM_WEB_MODE}"
            shift
            ;;
        # if the first argument is not a valid mode/subcommand, assume it's a command and execute it directly.
        *)
            exec "$@"
    esac
else
    echo "Using environment variable for SLURM_WEB_MODE: ${SLURM_WEB_MODE}"
fi


# Determine the mode and execute the appropriate command, passing any additional arguments
case "${SLURM_WEB_MODE:-}" in
    gateway)
        exec slurm-web gateway --conf "${SLURM_WEB_CONF:-/etc/slurm-web/gateway.ini}" "$@"
        ;;
    agent)
        exec slurm-web agent --conf "${SLURM_WEB_CONF:-/etc/slurm-web/agent.ini}" "$@"
        ;;
    ldap-check|gen-jwt-key|show-conf|connect-check|--version|-v|--help|-h)
        exec slurm-web "${SLURM_WEB_MODE}" "$@"
        ;;
    *)
        # If SLURM_WEB_MODE is not set to a valid mode, print an error and exit.
        echo "Error: Invalid SLURM_WEB_MODE: '${SLURM_WEB_MODE:-}' (must be a valid slurm-web subcommand like 'gateway', 'agent', 'gen-jwt-key', etc.)"
        exit 1
        ;;
esac
