# Troubleshooting

## 1. Docker looks dead but Colima is actually running

### Symptom
- `colima status` says running
- `docker ps` fails or points at `/var/run/docker.sock`

### Fix

```bash
export DOCKER_HOST=unix:///Users/scott/.colima/default/docker.sock
```

Persist it in `~/.zshrc` if this Mac mini uses Colima for Docker.

---

## 2. Cognee health is OK but indexing fails with LLM connection timeout

### Symptom
- `/health` works
- index or cognify fails with connection test timeout

### Fix
Set:

```bash
COGNEE_SKIP_CONNECTION_TEST=true
```

Reason: Cognee's connection-test path is brittle and gave false negatives in the validated rollout.

---

## 3. Cognee update fails with 409

### Symptom
- `PATCH /api/v1/update` returns 409
- plugin logs `update failed ... falling back to add`

### Root cause
Cognee 0.5.5-local update path is not reliable for this workflow.

### Correct method
Patch `cognee-openclaw` so update becomes replace:
- add new blob
- delete old blob
- keep the operation counted as update

Use `scripts/patch_openclaw_cognee_plugin.py`.

---

## 4. Embedding calls fail because `dimensions` is passed to SiliconFlow

### Symptom
- log mentions `UnsupportedParamsError`
- log says `Setting dimensions is not supported`

### Root cause
Cognee/LiteLLM embedding path passes `dimensions` by default.

### Correct method
Patch LiteLLM embedding engine to suppress the `dimensions` parameter.

Use `scripts/apply_cognee_hotfix.sh`.

---

## 5. Vector validation says 3072 required but embedding is 1024

### Symptom
- log shows validation error requiring 3072 items
- actual vector length is 1024

### Root cause
Cognee default embedding schema is 3072-dim, but `bge-m3` on this setup is 1024-dim.

### Correct method
Patch Cognee default embedding dimension to 1024.

Use `scripts/apply_cognee_hotfix.sh`.

---

## 6. Dataset stays `DATASET_PROCESSING_ERRORED`

### Symptom
- status never recovers
- search or recall is unreliable

### Root cause
Usually a poisoned dataset from earlier bad update attempts or failed file pointers.

### Correct method
Create a fresh dataset name and re-index cleanly.

Recommended pattern:

```text
openclaw-main-<machine>-v<N>
```

---

## 7. Recall still does not work even though indexing succeeds

### Checklist
1. confirm `searchType` is `CHUNKS`
2. confirm dataset status is not errored
3. confirm plugin slot `memory` points to `cognee-openclaw`
4. confirm `autoRecall: true`
5. verify a real search or a live `<cognee_memories>` injection

Do not call rollout complete until recall is proven.

---

## 8. Search returns empty / "No data found" despite data existing (user identity mismatch)

### Symptom
- Cognee server is up, login succeeds
- `POST /api/v1/search` returns `404` with `"NoDataError: No data found in the system"`
- But lance files exist under `.cognee_system/databases/` and `cognify dispatched` logs appear
- Gateway logs show `cognee-openclaw: injecting N memories` (recall works via plugin)

### Root cause
**Multi-tenant user identity mismatch.** Cognee isolates data per user. Data was ingested under one user (e.g. `default_user@example.com`, ID `f5249267...`) but the config now authenticates as a different user (e.g. `admin2@cognee.ai`, ID `95cf83e5...`).

This typically happens when:
1. Cognee was initially set up with the **default user** (`default_user@example.com` / `default_password`) — this is the built-in user Cognee creates at server init
2. Config was later changed to use a custom user like `admin2@cognee.ai`
3. All historical data remains owned by the old user; the new user's data directory is empty

### Diagnosis

```bash
# Check who owns the data
docker exec cognee ls /app/cognee/.cognee_system/databases/
# → You'll see user UUID directories. The one with lance files is the data owner.

# Check who you're logging in as
curl -s -X POST http://HOST:8000/api/v1/auth/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'username=YOUR_USER&password=YOUR_PASS' | python3 -c "import sys,json; print(json.load(sys.stdin))"
# → Compare the JWT sub claim with the data directory name
```

### Fix
Change `openclaw.json` credentials back to the user that owns the data:

```json
{
  "cognee-sidecar-openclaw": {
    "config": {
      "username": "default_user@example.com",
      "password": "default_password"
    }
  }
}
```

Then restart gateway.

### Known Cognee default credentials

| User | Password | Notes |
|------|----------|-------|
| `default_user@example.com` | `default_password` | Auto-created at server init. All data ingested before custom user setup lives here. |
| `admin2@cognee.ai` | `<YOUR_PASSWORD>` | Manually registered. Empty unless data was explicitly added under this account. |

### Auth endpoint

Login endpoint is `POST /api/v1/auth/login` (NOT `/api/v1/users/signin`). Content-Type must be `application/x-www-form-urlencoded`, not JSON.

---

## 9. cognify dispatched but data never appears in search

### Symptom
- Gateway logs show `cognify dispatched` after file sync
- But `sync-index.json` still shows `"status": "pending"` for all files
- Search returns empty

### Root cause
cognify is async and may silently fail if:
- Embedding model is down or quota exhausted (SiliconFlow)
- LLM model for graph extraction is down
- Docker container ran out of memory

### Diagnosis
```bash
docker logs cognee --tail 200 2>&1 | grep -i "error\|fail\|exception"
```

### Fix
1. Check SiliconFlow API key and quota
2. Restart cognee container: `docker restart cognee`
3. If dataset is poisoned, create a fresh one (see #6)

---

## 10. Best-known good settings

- `LLM_PROVIDER=openai`
- `LLM_MODEL=openai/Qwen/Qwen2.5-72B-Instruct`
- `EMBEDDING_PROVIDER=custom`
- `EMBEDDING_MODEL=openai/BAAI/bge-m3`
- `HUGGINGFACE_TOKENIZER=BAAI/bge-m3`
- `searchType=CHUNKS`
- fresh dataset if previous datasets errored
