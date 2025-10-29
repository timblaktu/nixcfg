#!/bin/bash
# Example script demonstrating unified files module capabilities
# This script will be auto-detected as bash by autoWriter

set -euo pipefail

# Source libraries (will be injected by mkValidatedFile)
source terminalUtils
source colorUtils

main() {
    header "Unified Files Module Demo"
    
    info "This script demonstrates:"
    echo "  • Auto file type detection via autoWriter"
    echo "  • Library injection (terminalUtils, colorUtils)"  
    echo "  • Enhanced testing beyond syntax validation"
    echo "  • Preserved functionality from validated-scripts"
    
    section "Terminal Capabilities"
    echo "Terminal width: $(get_terminal_width)"
    echo "Terminal height: $(get_terminal_height)"
    
    if has_color; then
        success "Color support detected"
        show_colors
    else
        info "Running in no-color mode"
    fi
    
    section "Progress Demo"
    for i in {1..10}; do
        show_progress $i 10 "Processing items"
        sleep 0.1
    done
    
    complete "Demo completed successfully!"
}

# Help function
show_help() {
    cat << 'EOF'
Example Unified Script - Demonstrates hybrid autoWriter + enhanced libraries

USAGE:
    example-unified-script [OPTIONS]

OPTIONS:
    -h, --help     Show this help message
    --demo         Run the demo (default)
    --colors       Show color palette
    --terminal     Show terminal info only

EXAMPLES:
    example-unified-script
    example-unified-script --colors
    example-unified-script --terminal

This script showcases the unified files module that combines:
- nixpkgs autoWriter for file type detection
- Enhanced testing framework
- Script library system for code reuse
- Domain-specific generators for specialized functionality
EOF
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    --colors)
        source colorUtils
        show_colors
        exit 0
        ;;
    --terminal)
        echo "Terminal width: $(get_terminal_width)"
        echo "Terminal height: $(get_terminal_height)"
        echo "Color support: $(has_color && echo "yes" || echo "no")"
        exit 0
        ;;
    --demo|"")
        main
        ;;
    *)
        error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac