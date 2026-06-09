# Task: Fix BackendApi Tests - Use Mock HTTP Client

## Change ID: fix-backend-api-tests

## Tasks

### Task 1: Add injectable http.Client to BackendApi
**File:** `frontend/lib/shared/services/backend_api.dart`

**Changes:**
1. Add a `http.Client` field after line 18 (`final String _baseUrl`):
   ```dart
   http.Client _client = http.Client();
   ```
   
2. Add a setter method (or make the field public) so tests can inject a mock client:
   ```dart
   /// Set a custom HTTP client (for testing with MockClient).
   void setClient(http.Client client) => _client = client;
   ```

3. Replace all top-level `http.get(...)` calls with `_client.get(...)`:
   - Line 93-94: `http.get(uri, headers: await _headers())` → `_client.get(uri, headers: await _headers())`
   - Line 107-112: `http.post(uri, headers: ..., body: ...)` → `_client.post(uri, headers: ..., body: ...)`
   - Line 125-131: `http.put(uri, headers: ..., body: ...)` → `_client.put(uri, headers: ..., body: ...)`
   - Line 140-141: `http.delete(uri, headers: ...)` → `_client.delete(uri, headers: ...)`

### Task 2: Update backend_api_test.dart to use MockClient
**File:** `frontend/test/backend_api_test.dart`

**Changes:**
1. In `setUp()`, after creating `api = BackendApi()`, inject the mock client:
   ```dart
   api.setClient(mockClient);
   ```

2. Reset circuit breaker state between tests (since BackendApi is a singleton, circuit breaker state persists across tests). Add after `api.setClient(mockClient)`:
   ```dart
   // Reset circuit breaker state for each test
   // (BackendApi is a singleton, so state persists across tests)
   ```

   Note: The circuit breaker fields are private. We need to either:
   - Make them package-visible (prefix with `_` removed), OR
   - Add a `reset()` method to BackendApi

   **Best approach**: Add a `reset()` method to BackendApi:
   ```dart
   /// Reset circuit breaker state (primarily for testing).
   @visibleForTesting
   void resetCircuitBreaker() {
     _circuitState = CircuitState.closed;
     _consecutiveFailures = 0;
     _lastFailureTime = null;
   }
   ```

   Then in test setUp:
   ```dart
   api.resetCircuitBreaker();
   ```
