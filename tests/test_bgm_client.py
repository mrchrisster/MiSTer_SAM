"""Optional policy negotiation and idempotent RAM state fixtures."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch
from paths import PACKAGE

spec = importlib.util.spec_from_file_location("sam_bgm_client", PACKAGE / ".MiSTer_SAM/sam_bgm_client.py")
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)


class PolicyClient(unittest.TestCase):
    def test_fragmented_framed_reply(self):
        conn = MagicMock()
        conn.__enter__.return_value = conn
        conn.recv.side_effect = [b'{"v":', b'2}\n']
        with patch.object(client.socket, "AF_UNIX", 1, create=True), patch.object(client.socket, "socket", return_value=conn):
            self.assertEqual(client.exchange("socket", b"request\n"), {"v": 2})
        conn.sendall.assert_called_once_with(b"request\n")

    def test_empty_unterminated_and_oversized_wire_replies_fail(self):
        for chunks in ([b""], [b'{"v":2}', b""], [b"x" * 65537]):
            conn = MagicMock()
            conn.__enter__.return_value = conn
            conn.recv.side_effect = chunks
            with patch.object(client.socket, "AF_UNIX", 1, create=True), patch.object(client.socket, "socket", return_value=conn):
                with self.assertRaises(client.ProtocolError):
                    client.exchange("socket", b"request\n")

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.state = str(Path(self.directory.name) / "bgm-owner.policy")
        self.requests = []

    def invoke(self, mode="active", identity="12:34:socket", owner="56:78"):
        return client.policy("socket", self.state, identity, owner, mode)

    def exchange(self, path, payload, framed=True):
        self.requests.append(payload)
        if not framed:
            return '{"v":2,"policy":true,"framing":"json-line"}'
        request = json.loads(payload)
        return {"v": 2, "id": request["id"], "ok": True, "applied": True}

    def test_capability_probe_cached_and_one_atomic_request_per_stage(self):
        with patch.object(client, "exchange", self.exchange):
            self.assertEqual(self.invoke(), 0)
            self.assertEqual(self.invoke(), 0)
            self.assertEqual(self.invoke("menu"), 0)
            self.assertEqual(self.invoke("game"), 0)
        self.assertEqual(self.requests[0], b"capabilities")
        policies = [json.loads(item) for item in self.requests[1:]]
        self.assertEqual([item["revision"] for item in policies], [1, 2, 3])
        self.assertEqual([item["mode"] for item in policies], ["active", "menu", "game"])

    def test_legacy_empty_unknown_and_disabled_never_receive_json(self):
        for response in ("", "unknown command", '{"v":2,"policy":false,"framing":"json-line"}'):
            Path(self.state).unlink(missing_ok=True)
            with patch.object(client, "exchange", return_value=response) as call:
                self.assertEqual(self.invoke(), 3)
                self.assertEqual(self.invoke(), 3)
                call.assert_called_once_with("socket", b"capabilities", framed=False)

    def test_replaced_service_reprobes(self):
        with patch.object(client, "exchange", self.exchange):
            self.invoke()
            self.invoke(identity="12:35:new-socket")
        self.assertEqual(self.requests.count(b"capabilities"), 2)

    def test_failed_probe_blocks_without_caching_legacy(self):
        with patch.object(client, "exchange", side_effect=TimeoutError("busy service")):
            with self.assertRaises(TimeoutError):
                self.invoke()
        self.assertFalse(Path(self.state).exists())
        with patch.object(client, "exchange", self.exchange):
            self.assertEqual(self.invoke(), 0)
        self.assertEqual(self.requests[0], b"capabilities")

    def test_lost_active_reply_then_release_has_new_revision_and_stable_retry(self):
        def lose_active(path, payload, framed=True):
            if not framed:
                return self.exchange(path, payload, framed)
            self.requests.append(payload)
            raise client.ProtocolError("reply lost after apply")
        with patch.object(client, "exchange", lose_active):
            with self.assertRaises(client.ProtocolError):
                self.invoke()
        with patch.object(client, "exchange", self.exchange):
            self.assertEqual(self.invoke("menu"), 0)
            self.assertEqual(self.invoke("menu"), 0)
        self.assertEqual([json.loads(item)["revision"] for item in self.requests[1:]], [1, 2])
        self.assertNotEqual(json.loads(self.requests[1])["id"], json.loads(self.requests[2])["id"])

    def test_release_without_owner_never_sends_policy(self):
        for owner in ("", "0:0", "bad", "56:wrong"):
            Path(self.state).unlink(missing_ok=True)
            with patch.object(client, "exchange", self.exchange):
                with self.assertRaises(client.ProtocolError):
                    self.invoke("menu", owner=owner)
        self.assertEqual(self.requests, [b"capabilities"] * 4)

    def test_new_daemon_does_not_reuse_old_ack_or_revision(self):
        with patch.object(client, "exchange", self.exchange):
            self.invoke()
            self.invoke("menu")
            self.invoke(identity="12:99:new-socket", owner="88:100")
        final = json.loads(self.requests[-1])
        self.assertEqual(final["revision"], 1)
        self.assertEqual(final["owner"], "88:100")
        self.assertEqual(self.requests.count(b"capabilities"), 2)

    def test_lost_reply_reuses_request_id_revision_and_owner(self):
        with patch.object(client, "exchange", self.exchange):
            self.invoke()
        def lost(path, payload, framed=True):
            self.requests.append(payload)
            raise client.ProtocolError("lost reply")
        with patch.object(client, "exchange", lost):
            with self.assertRaises(client.ProtocolError):
                self.invoke("menu", owner="99:100")
        with patch.object(client, "exchange", self.exchange):
            self.invoke("menu", owner="99:100")
        self.assertEqual(self.requests[-2], self.requests[-1])
        self.assertEqual(json.loads(self.requests[-1])["owner"], "99:100")

    def test_unapplied_and_wrong_id_cannot_acknowledge(self):
        for reply in ({"v": 2, "id": "wrong", "ok": True, "applied": True},
                      {"v": 2, "ok": True, "applied": False}):
            Path(self.state).unlink(missing_ok=True)
            def answer(path, payload, framed=True):
                if not framed:
                    return self.exchange(path, payload, framed)
                result = dict(reply)
                result.setdefault("id", json.loads(payload)["id"])
                return result
            with patch.object(client, "exchange", answer):
                with self.assertRaises(client.ProtocolError):
                    self.invoke()
            self.assertFalse(json.loads(Path(self.state).read_text())["acknowledged"])


if __name__ == "__main__":
    unittest.main()
