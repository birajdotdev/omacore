import copy
import runpy
import unittest
from unittest.mock import patch
from pathlib import Path

api = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'omacore-connection'))
main = api['main']
packet = api['packet']
Link = api['Link']
EARBUD = '34:09:C9:AD:F7:80'
A, B, C = ('00:00:00:00:00:01', '00:00:00:00:00:02', '00:00:00:00:00:03')


class FakeLink:
    rows = []
    sent = []
    closed = False

    def __init__(self, mac):
        self.sock = self

    def open(self):
        return self

    def close(self):
        type(self).closed = True

    def devices(self):
        return copy.deepcopy(self.rows)

    def sendall(self, data):
        self.sent.append(data)


class ConnectionsTest(unittest.TestCase):
    def setUp(self):
        FakeLink.rows = [{'mac': mac, 'connected': mac != C} for mac in (A, B, C)]
        FakeLink.sent = []
        FakeLink.closed = False

    def invoke(self, mac, enabled):
        with patch.dict(main.__globals__, Link=FakeLink):
            main([EARBUD, 'SoundcoreD1202C', mac, enabled])

    def test_disconnect_targets_only_selected_host(self):
        self.invoke(B, 'false')
        self.assertEqual(FakeLink.sent, [packet((0x0b, 0x81), bytes.fromhex(B.replace(':', '')))])
        self.assertTrue(FakeLink.closed)

    def test_connect_targets_only_selected_host(self):
        FakeLink.rows[1]['connected'] = False
        self.invoke(C, 'true')
        self.assertEqual(FakeLink.sent, [packet((0x0b, 0x82), bytes.fromhex(C.replace(':', '')))])

    def test_third_connection_is_rejected_without_disconnecting_others(self):
        with self.assertRaisesRegex(ValueError, 'maximum two'):
            self.invoke(C, 'true')
        self.assertEqual(FakeLink.sent, [])
        self.assertTrue(FakeLink.closed)

    def test_unknown_and_noop_do_not_send(self):
        self.invoke(A, 'true')
        with self.assertRaisesRegex(ValueError, 'no longer'):
            self.invoke('00:00:00:00:00:04', 'true')
        self.assertEqual(FakeLink.sent, [])

    def test_known_request_frame(self):
        self.assertEqual(packet((1, 1)), bytes.fromhex('08ee00000001010a0002'))

    def test_fragmented_and_coalesced_responses(self):
        frame = bytearray(packet((0x0b, 1), bytes([1, 1])))
        frame[:5] = bytes.fromhex('09ff000001')
        frame[-1] = sum(frame[:-1]) & 255
        chunks = iter([bytes(frame[:4]), bytes(frame[4:]) + bytes(frame)])
        link = Link.__new__(Link)
        link.buffer = b''
        class Socket:
            def settimeout(self, timeout): pass
            def recv(self, count): return next(chunks)
        link.sock = Socket()
        import time
        self.assertEqual(link.receive(time.monotonic() + 1), (bytes([0x0b, 1]), bytes([1, 1])))
        self.assertEqual(link.receive(time.monotonic() + 1), (bytes([0x0b, 1]), bytes([1, 1])))
        link.buffer = bytes(frame[:-1]) + bytes([frame[-1] ^ 1])
        with self.assertRaisesRegex(ValueError, 'checksum'):
            link.receive(time.monotonic() + 1)


if __name__ == '__main__':
    unittest.main()
