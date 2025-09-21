# Local AI Hybrid Architecture & Operations

## Architecture overview
- **Clients** issue inference or automation requests via the Ralf tooling.
- **Orchestration layer** routes requests to the appropriate execution environment (local for low-latency/private workloads, cloud for scale or specialised hardware).
- **Model backends**
  - *Local*: Ollama hosts pulled models (for example `llama3:8b`) on the operator workstation or edge node, exposing an HTTP API.
  - *Cloud*: Managed AI services (e.g. OpenAI, Azure, or self-managed GPU clusters) with authenticated endpoints.
- **State & configuration** is stored in repository configuration files and environment variables so that switching between environments is deterministic and auditable.

### Data flow
1. A request is created by the CLI or automation.
2. Routing logic resolves the preferred backend (local first, with cloud fallback if required capabilities or capacity are unavailable).
3. The chosen backend processes the prompt, returning responses to the caller.
4. Observability hooks persist logs/metrics for debugging and compliance.

## Setup guide
1. **Prerequisites**
   - Docker (or Podman) installed if running Ollama inside a container.
   - Access credentials for the cloud provider (API keys, tokens).
   - Python 3.10+ and `pipx` for tooling helpers.
2. **Install Ollama (local inference)**
   - Follow [Ollama installation docs](https://ollama.com/download).
   - Pull the baseline model:
     ```bash
     ollama pull llama3:8b
     ```
   - Verify that `ollama list` shows the model and that `ollama serve` is running (either as a service or foreground process).
3. **Configure environment**
   - Copy `.env.example` (if present) to `.env` and populate tokens, endpoints, and default backend preferences.
   - Export the environment variables in your shell or use a process manager that loads them automatically.
4. **Install Python dependencies**
   - Use the project virtual environment (e.g. `python -m venv .venv && source .venv/bin/activate`).
   - Run `pip install -r requirements.txt` if available, otherwise follow component-specific docs.
5. **Validate integration**
   - Execute the local smoke test script `make local-ai-check` (or run the equivalent CLI command) to ensure connectivity to both local and cloud providers.

## Usage patterns
### Running locally
- Start the Ollama service (`ollama serve`) and confirm the API port (default `11434`).
- Set `AI_BACKEND=local` (or configure the CLI flag `--backend local`).
- Run inference commands; responses should return immediately without internet dependency.

### Using cloud providers
- Ensure environment variables (e.g. `OPENAI_API_KEY`, `AZURE_OPENAI_ENDPOINT`) are set.
- Switch the backend selection (`AI_BACKEND=cloud` or CLI flag `--backend cloud`).
- For hybrid mode, configure routing rules so that requests fallback to the cloud only when local inference is unavailable or lacks capability.

## Troubleshooting
- **Model not found**: Re-run `ollama pull llama3:8b`; confirm disk space and network access.
- **Connection refused**: Ensure `ollama serve` is active and listening on the expected port. Use `curl http://localhost:11434/api/tags` to verify.
- **Authentication errors**: Refresh cloud API tokens; validate environment variable names and scopes.
- **Performance degradation**: Monitor local GPU/CPU utilisation; consider reducing concurrent requests or pinning to cloud resources for bursty workloads.
- **Configuration drift**: Commit shared configuration templates and document overrides; rerun smoke tests after changes.

## PR review checklist
Before approving changes to the local AI hybrid stack:
- [ ] Architecture documentation updated if components/data flows changed.
- [ ] Setup scripts (Makefile targets, Dockerfiles) tested locally.
- [ ] Hybrid routing logic covered by automated or manual tests.
- [ ] Security review completed for secrets handling and network exposure.
- [ ] Observability/logging validated for new code paths.
- [ ] Rollback plan documented for production deployments.

### Merge hint
After successful testing, **merge the feature branch `feature/local-ai-hybrid` into `main`** and tag the release if required by the deployment checklist.
