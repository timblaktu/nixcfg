# modules/programs/opencode/_hm/model-discovery.nix
# Provides `opencode-discover-models` — a shell script that queries OpenAI-compatible
# /v1/models endpoints and emits JSON fragments suitable for merging into opencode
# config via OPENCODE_CONFIG_CONTENT.
#
# Usage:
#   opencode-discover-models \
#     --provider-id bedrock \
#     --base-url "https://proxy.example.com/api/v1" \
#     --api-key-env BEDROCK_API_TOKEN \
#     --cache-dir ~/.cache/opencode-discovery/work \
#     --cache-ttl 30 \
#     --static-models "model-a,model-b,model-c"

{ pkgs }:

pkgs.writeShellApplication {
  name = "opencode-discover-models";

  runtimeInputs = with pkgs; [ curl jq coreutils ];

  text = ''
    set -o pipefail

    # --- Argument parsing ---
    PROVIDER_ID=""
    BASE_URL=""
    API_KEY_ENV=""
    CACHE_DIR=""
    CACHE_TTL=30
    STATIC_MODELS=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --provider-id) PROVIDER_ID="$2"; shift 2 ;;
        --base-url) BASE_URL="$2"; shift 2 ;;
        --api-key-env) API_KEY_ENV="$2"; shift 2 ;;
        --cache-dir) CACHE_DIR="$2"; shift 2 ;;
        --cache-ttl) CACHE_TTL="$2"; shift 2 ;;
        --static-models) STATIC_MODELS="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    # Validate required args
    if [[ -z "$PROVIDER_ID" || -z "$BASE_URL" || -z "$API_KEY_ENV" || -z "$CACHE_DIR" ]]; then
      echo "ERROR: --provider-id, --base-url, --api-key-env, and --cache-dir are required" >&2
      exit 1
    fi

    CACHE_FILE="$CACHE_DIR/$PROVIDER_ID.json"

    # --- Cache check ---
    if [[ -f "$CACHE_FILE" ]]; then
      file_age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
      ttl_seconds=$(( CACHE_TTL * 60 ))
      if [[ "$file_age" -lt "$ttl_seconds" ]]; then
        exit 0  # Cache is fresh
      fi
    fi

    # --- Read API key from environment ---
    api_key="''${!API_KEY_ENV:-}"
    if [[ -z "$api_key" ]]; then
      echo "WARNING: $API_KEY_ENV is not set, skipping discovery for $PROVIDER_ID" >&2
      exit 0
    fi

    # --- Query /v1/models ---
    models_url="''${BASE_URL%/}/models"
    response=""
    if ! response=$(curl -sf --max-time 5 \
      -H "Authorization: Bearer $api_key" \
      "$models_url" 2>/dev/null); then
      echo "WARNING: Failed to query $models_url for provider $PROVIDER_ID" >&2
      exit 0  # Leave existing cache untouched
    fi

    # --- Parse model IDs ---
    discovered_ids=""
    if ! discovered_ids=$(echo "$response" | jq -r '.data[].id' 2>/dev/null); then
      echo "WARNING: Failed to parse /v1/models response for $PROVIDER_ID" >&2
      exit 0
    fi

    if [[ -z "$discovered_ids" ]]; then
      echo "WARNING: No models found in /v1/models response for $PROVIDER_ID" >&2
      exit 0
    fi

    # --- Build static model set for filtering ---
    declare -A static_set
    if [[ -n "$STATIC_MODELS" ]]; then
      IFS=',' read -ra static_arr <<< "$STATIC_MODELS"
      for m in "''${static_arr[@]}"; do
        static_set["$m"]=1
      done
    fi

    # --- Log retired models (in static but missing from API) ---
    if [[ -n "$STATIC_MODELS" ]]; then
      declare -A api_set
      while IFS= read -r id; do
        api_set["$id"]=1
      done <<< "$discovered_ids"

      for m in "''${!static_set[@]}"; do
        if [[ -z "''${api_set[$m]:-}" ]]; then
          echo "INFO: Model '$m' is in static config but not in $PROVIDER_ID API (may be retired)" >&2
        fi
      done
    fi

    # --- Filter to only NEW models ---
    new_models=""
    while IFS= read -r id; do
      if [[ -z "''${static_set[$id]:-}" ]]; then
        new_models+="$id"$'\n'
      fi
    done <<< "$discovered_ids"

    new_models=$(echo -n "$new_models" | sed '/^$/d')

    if [[ -z "$new_models" ]]; then
      # No new models — write empty provider fragment so cache timestamp updates
      mkdir -p "$CACHE_DIR"
      tmp_file="$CACHE_DIR/.$PROVIDER_ID.json.tmp"
      echo '{}' > "$tmp_file"
      mv -f "$tmp_file" "$CACHE_FILE"
      exit 0
    fi

    # --- Build JSON fragment ---
    # Format: { "provider": { "<provider-id>": { "models": { "<id>": { "name": "<id>" } } } } }
    models_json=$(echo "$new_models" | jq -R -s '
      split("\n") | map(select(length > 0)) |
      map({(.): {"name": .}}) |
      add // {}
    ')

    fragment=$(jq -n \
      --arg pid "$PROVIDER_ID" \
      --argjson models "$models_json" \
      '{"provider": {($pid): {"models": $models}}}')

    # --- Atomic write ---
    mkdir -p "$CACHE_DIR"
    tmp_file="$CACHE_DIR/.$PROVIDER_ID.json.tmp"
    echo "$fragment" > "$tmp_file"
    mv -f "$tmp_file" "$CACHE_FILE"

    new_count=$(echo "$new_models" | wc -l)
    echo "INFO: Discovered $new_count new model(s) for $PROVIDER_ID" >&2
  '';
}
