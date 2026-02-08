#!/usr/bin/env bash
# Script Help Format Template for Automatic Shell Completion
# 
# This template demonstrates the recommended help output format for scripts
# to ensure optimal automatic parsing by the shell completion generators.
#
# Key principles:
# 1. Use consistent section headers in UPPERCASE followed by a colon
# 2. Indent command/option descriptions consistently (4 spaces recommended)
# 3. For options with constrained values, use one of these formats:
#    - "Mode: value1, value2, value3" (comma-separated after colon)
#    - "(value1|value2|value3)" (pipe-separated in parentheses)
#    - "{value1,value2,value3}" (comma-separated in braces)
# 4. Use UPPERCASE for parameter placeholders (FILE, MODE, USER, etc.)

show_usage() {
    cat << 'EOF'
SCRIPTNAME - Brief one-line description of what the script does

USAGE:
    scriptname COMMAND [OPTIONS] [ARGS]
    scriptname [GLOBAL-OPTIONS] COMMAND [COMMAND-OPTIONS]

DESCRIPTION:
    More detailed description of the script's purpose and functionality.
    Can span multiple lines if needed.

COMMANDS:
    setup       Configure the system for operation
    deploy      Deploy resources to target
    run         Execute the main operation
    check       Verify system status
    help        Show this help message

GLOBAL OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -q, --quiet             Suppress non-error output
    -c, --config FILE       Configuration file path
    -u, --user USER         Username for authentication
    -H, --host HOST         Target hostname or IP address
    -p, --port PORT         Port number (default: 22)

EXAMPLES:
    # Basic usage
    scriptname setup -m auto
    
    # With custom configuration
    scriptname -c /path/to/config deploy
    
    # Verbose mode with specific target
    scriptname -v -H 192.168.1.1 run --mode scan

Run 'scriptname COMMAND --help' for command-specific help.
EOF
}

show_setup_usage() {
    cat << 'EOF'
Configure the system for operation

USAGE:
    scriptname setup [OPTIONS]

OPTIONS:
    -m MODE         Operation mode (default: auto)
    -e ENVIRONMENT  Target environment
    -t TYPE         Setup type
    -b              Backup existing configuration
    -f              Force setup without confirmation
    -w SECONDS      Wait time before proceeding (default: 30)
    --dry-run       Show what would be done without doing it
    -h, --help      Show this help

MODE VALUES:
    auto        Automatic detection and configuration
    manual      Step-by-step interactive setup
    expert      Advanced configuration with all options

ENVIRONMENT VALUES:
    dev         Development environment
    staging     Staging/testing environment  
    prod        Production environment

TYPE VALUES:
    full        Complete setup with all features
    minimal     Basic setup with core features only
    custom      User-defined configuration

EXAMPLES:
    scriptname setup -m auto -e dev
    scriptname setup -t minimal --dry-run
    scriptname setup -m expert -b -f
EOF
}

show_run_usage() {
    cat << 'EOF'
Execute the main operation

USAGE:
    scriptname run [OPTIONS] [TARGET]

OPTIONS:
    -m MODE         Execution mode: scan, monitor, analyze, process
    -i INPUT        Input file or directory
    -o OUTPUT       Output file or directory
    -f FORMAT       Output format: json, xml, csv, text (default: text)
    -F FILTER       Apply filter expression
    -l LEVEL        Log level: debug, info, warn, error (default: info)
    -t TIMEOUT      Operation timeout in seconds
    -r RETRIES      Number of retry attempts (default: 3)
    --parallel N    Number of parallel workers
    -h, --help      Show this help

MODE VALUES:
    scan        Quick scan for issues
    monitor     Continuous monitoring
    analyze     Deep analysis with reporting
    process     Process and transform data

FORMAT VALUES:
    json        JSON structured output
    xml         XML formatted output
    csv         Comma-separated values
    text        Human-readable text

LOG LEVELS:
    debug       All messages including debug
    info        Informational messages and above
    warn        Warnings and errors only
    error       Errors only

EXAMPLES:
    scriptname run -m scan -o results.json
    scriptname run -m monitor -l debug --parallel 4
    scriptname run target.txt -f csv -F "status=active"
EOF
}

# Main script logic
case "${1:-}" in
    setup)
        shift
        if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
            show_setup_usage
            exit 0
        fi
        # setup implementation
        ;;
    run)
        shift
        if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
            show_run_usage
            exit 0
        fi
        # run implementation
        ;;
    help|--help|-h)
        show_usage
        exit 0
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
