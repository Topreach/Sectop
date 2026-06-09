# Fix BackendApi Tests - Use Mock HTTP Client

## Reason
The `BackendApi` class uses a singleton pattern with `http.get()`/`http.post()` directly (top-level functions), making it impossible for tests to inject a mock HTTP client. The existing `backend_api_test.dart` creates a `MockClient` but never uses it — all test calls hit the real backend (nginx), returning 404 errors. After 5 failures, the circuit breaker opens and all subsequent tests fail with 503.

## Changes

### 1. `frontend/lib/shared/services/backend_api.dart`
- Add a `http.Client` field that defaults to `http.Client()` but can be injected
- Change all `http.get(...)` calls to `_client.get(...)`, `http.post(...)` to `_client.post(...)`, etc.
- This enables dependency injection for testing without breaking the singleton pattern

### 2. `frontend/test/backend_api_test.dart`
- Inject `MockClient` into `BackendApi` via the new `_client` field
- The `MockClient` already exists in the test file but was never wired up
- Reset circuit breaker state between tests to prevent cascade failures

## Impact
- All 20 backend_api tests will pass using mocked HTTP instead of hitting the real backend
- No change to production behavior (default `http.Client()` is used)
- Singleton pattern preserved
