from types import SimpleNamespace

import pytest

from tools import meshy_stage as stage


def test_download_limits_preserve_live_operator_fix():
    assert stage._GLB_MAX_BYTES == 128 * 1024 * 1024
    assert stage._THUMBNAIL_MAX_BYTES == 16 * 1024 * 1024
    assert stage._DOWNLOAD_TOTAL_MAX_BYTES == 256 * 1024 * 1024


@pytest.mark.parametrize("size", [0, 7, 8])
def test_download_accepts_bytes_up_to_bound_without_extra_request(size):
    calls = []
    payload = b"x" * size

    def download(url, maximum, remaining, clock):
        calls.append((url, maximum, remaining))
        return payload

    client = SimpleNamespace(download_bytes=download)
    preflight = SimpleNamespace(clock=lambda: 0.0, operation_deadline=10.0)
    assert stage._download_with_limit(client, "https://example.invalid/a", 8, preflight) == payload
    assert calls == [("https://example.invalid/a", 8, 10.0)]


def test_download_rejects_one_byte_over_bound_without_retry():
    calls = []

    def download(*args):
        calls.append(args)
        return b"x" * 9

    client = SimpleNamespace(download_bytes=download)
    preflight = SimpleNamespace(clock=lambda: 0.0, operation_deadline=10.0)
    with pytest.raises(RuntimeError, match="exceeds maximum size"):
        stage._download_with_limit(client, "https://example.invalid/a", 8, preflight)
    assert len(calls) == 1


def test_expired_download_does_not_call_client():
    def unexpected(*args):
        pytest.fail("expired operation reached download client")

    client = SimpleNamespace(download_bytes=unexpected)
    preflight = SimpleNamespace(clock=lambda: 10.0, operation_deadline=10.0)
    with pytest.raises(RuntimeError, match="deadline exceeded"):
        stage._download_with_limit(client, "https://example.invalid/a", 8, preflight)
