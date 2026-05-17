# OpenCode Model Discovery

Automatically discovers models from OpenAI-compatible `/v1/models` endpoints
at wrapper launch time, so newly-available models appear in the OpenCode model
picker without rebuilding the Nix config.

## Problem

Enterprise AI proxies (CCv2, Bedrock) add and retire models frequently — 7 new
models appeared in 6 weeks during initial development. Each change required
updating the Nix config, rebuilding, and switching. Discovery makes model lists
self-updating while keeping Nix as the source of truth for known-good models.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     opencode${account} wrapper                  │
│                                                                 │
│  1. Export env vars (DISABLE_TELEMETRY, CONFIG_DIR, tokens)     │
│  2. Fetch Bitwarden credentials (rbw get)                       │
│  3. ┌──────────────────────────────────┐                        │
│     │  Model Discovery (parallel)      │                        │
│     │  ┌────────────┐ ┌────────────┐   │                        │
│     │  │ ai-proxy   │ │ bedrock    │   │  ← backgrounded,      │
│     │  │ /v1/models │ │ /v1/models │   │    timeout-bounded     │
│     │  └─────┬──────┘ └─────┬──────┘   │                        │
│     │        ▼              ▼          │                        │
│     │   ~/.cache/opencode-discovery/   │                        │
│     │     ├── ai-proxy.json            │                        │
│     │     └── bedrock.json             │                        │
│     └──────────────┬───────────────────┘                        │
│                    ▼                                            │
│  4. jq merge cache → OPENCODE_CONFIG_CONTENT                   │
│  5. exec opencode "$@"                                          │
└─────────────────────────────────────────────────────────────────┘
```

**Precedence** (highest → lowest):
1. `OPENCODE_CONFIG_CONTENT` env var — discovered models injected here
2. `opencode.json` in config dir — Nix-managed static models
3. OpenCode built-in defaults

Discovery only adds models not already in the static config.  It never
removes or overrides Nix-managed models.

## How It Works

### 1. Provider auto-detection (Nix eval time)

The wrapper generator scans `programs.opencode.provider.*` for providers that
have **both**:
- `options.baseURL` set (an API endpoint to query)
- `options.apiKey` matching `{env:VARNAME}` (a resolvable credential)

Matching providers get a discovery command in the wrapper — no explicit
provider list needed.

### 2. Discovery script (`opencode-discover-models`)

Each provider runs a backgrounded instance of `opencode-discover-models`:

```bash
opencode-discover-models \
  --provider-id bedrock \
  --base-url "https://proxy.example.com/api/v1" \
  --api-key-env BEDROCK_API_TOKEN \
  --cache-dir ~/.cache/opencode-discovery/work \
  --cache-ttl 30 \
  --static-models "model-a,model-b"
```

The script:
1. Checks cache freshness (skips API call if within TTL)
2. Queries `$BASE_URL/models` with Bearer auth, 5s timeout
3. Parses `.data[].id` (OpenAI-compatible response format)
4. Filters out models already in `--static-models` (Nix-managed)
5. Writes only NEW models to `$CACHE_DIR/$PROVIDER_ID.json`
6. Logs retired models (in static config but absent from API) to stderr

### 3. Merge and inject (wrapper runtime)

After all discovery processes complete (or timeout), the wrapper:
1. Glob-matches `~/.cache/opencode-discovery/${account}/*.json`
2. Deep-merges all fragments with `jq -s 'reduce .[] as $item ({}; . * $item)'`
3. Exports the result as `OPENCODE_CONFIG_CONTENT` (only if non-empty)

### Cache fragment format

```json
{
  "provider": {
    "bedrock": {
      "models": {
        "new-model-id": { "name": "new-model-id" }
      }
    }
  }
}
```

## Configuration

### Enable discovery for an account

```nix
programs.opencode.accounts.work = {
  enable = true;
  discovery.enable = true;          # default: false
  # discovery.cacheTtlMinutes = 30; # default: 30
  # discovery.timeoutSeconds = 3;   # default: 3
};
```

No other configuration is needed. Providers are auto-detected from the
existing `programs.opencode.provider` definitions.

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `discovery.enable` | bool | `false` | Enable model discovery for this account |
| `discovery.cacheTtlMinutes` | int | `30` | Minutes before re-querying endpoints |
| `discovery.timeoutSeconds` | int | `3` | Max seconds to wait before launching opencode |

### Tuning

- **Slow network**: Increase `timeoutSeconds` (discovery runs in parallel, so
  this is wall-clock time for the slowest provider)
- **Frequent changes**: Decrease `cacheTtlMinutes` (each wrapper launch
  re-queries if cache is stale)
- **Offline use**: Discovery silently falls back to static models on any
  failure — no configuration needed

## Graceful Degradation

The feature is designed to never block or break the wrapper:

| Failure mode | Behavior |
|-------------|----------|
| `/models` returns 403/404 | Warning to stderr, static models used |
| Network timeout (>5s per provider) | Warning to stderr, static models used |
| API key env var not set | Warning to stderr, provider skipped |
| All providers fail | No `OPENCODE_CONFIG_CONTENT` set, static config only |
| Wrapper timeout (>3s total) | Discovery processes orphaned, static config used |
| Malformed API response | jq parse failure caught, static config used |
| Cache directory unwritable | Discovery skipped, static config used |

## Observing Discovery

```bash
# Run wrapper normally — discovery warnings appear on stderr
opencodework 2>&1 | head

# Inspect cached discovery results
cat ~/.cache/opencode-discovery/work/ai-proxy.json
cat ~/.cache/opencode-discovery/work/bedrock.json

# Force cache refresh (delete cache, re-run)
rm -rf ~/.cache/opencode-discovery/work
opencodework --version

# Run discovery script directly for debugging
opencode-discover-models \
  --provider-id ai-proxy \
  --base-url "https://your-proxy/v1" \
  --api-key-env YOUR_API_KEY_VAR \
  --cache-dir /tmp/test-discovery \
  --cache-ttl 0 \
  --static-models ""
```

## File Layout

```
modules/programs/opencode/
├── opencode.nix                  # discovery options (L473-487)
│                                 # wrapper snippet generation (L1150-1222)
└── _hm/
    └── model-discovery.nix       # opencode-discover-models script package

~/.cache/opencode-discovery/
└── ${account}/                   # per-account cache
    ├── ai-proxy.json             # cached fragment (or empty {} if no new models)
    └── bedrock.json
```

## Limitations

- Requires OpenAI-compatible `/v1/models` endpoint with Bearer auth.
  Enterprise proxies may not expose this endpoint (returns 403). In that
  case discovery is a no-op and static models are used.
- Discovered models get a minimal config (`{"name": "model-id"}`) — no
  custom display names, token limits, or capability flags. Add these via
  the Nix static config if needed.
- Discovery is additive only. To remove a model, remove it from the Nix
  static config; discovered models persist in cache until TTL expires.
