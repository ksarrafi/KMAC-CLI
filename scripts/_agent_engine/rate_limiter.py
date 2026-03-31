"""Token-bucket rate limiter for API calls — prevents accidental bill spikes."""

import threading
import time


class RateLimiter:
    """Sliding-window rate limiter tracking both requests and tokens per minute."""

    def __init__(self, max_rpm=50, max_tpm=100_000):
        self.max_rpm = max_rpm
        self.max_tpm = max_tpm
        self._lock = threading.Lock()
        self._requests: list[float] = []
        self._tokens: list[tuple[float, int]] = []

    def _prune(self, now: float):
        cutoff = now - 60
        self._requests = [t for t in self._requests if t > cutoff]
        self._tokens = [(t, n) for t, n in self._tokens if t > cutoff]

    def check(self, estimated_tokens: int = 0) -> tuple[bool, str]:
        """Return (allowed, reason). Non-blocking check."""
        now = time.time()
        with self._lock:
            self._prune(now)
            if len(self._requests) >= self.max_rpm:
                wait = 60 - (now - self._requests[0])
                return False, f"Rate limited: {self.max_rpm} requests/min exceeded (wait {wait:.0f}s)"
            token_sum = sum(n for _, n in self._tokens) + estimated_tokens
            if token_sum > self.max_tpm:
                return False, f"Rate limited: {self.max_tpm:,} tokens/min exceeded"
        return True, ""

    def record(self, tokens_used: int = 0):
        """Record a completed request."""
        now = time.time()
        with self._lock:
            self._requests.append(now)
            if tokens_used:
                self._tokens.append((now, tokens_used))

    def wait_if_needed(self, estimated_tokens: int = 0) -> str | None:
        """Block until rate limit clears. Returns warning message or None."""
        for _ in range(120):
            ok, reason = self.check(estimated_tokens)
            if ok:
                return None
            time.sleep(0.5)
        return reason

    def stats(self) -> dict:
        now = time.time()
        with self._lock:
            self._prune(now)
            return {
                "rpm_current": len(self._requests),
                "rpm_limit": self.max_rpm,
                "tpm_current": sum(n for _, n in self._tokens),
                "tpm_limit": self.max_tpm,
            }
