import threading
import time
import unittest
import video_runner
from telemetry import Cancelled, SessionMonitor, TransferMeter


class TelemetryTests(unittest.TestCase):
    def test_direction_and_rolling_payload_rates(self):
        meter=TransferMeter(now=10)
        value=meter.record(3,1024,0.1,now=11)
        self.assertEqual(value['uploaded_bytes'],1024)
        self.assertEqual(value['readback_bytes'],0)
        self.assertEqual(value['current_bytes_per_second'],1024)
        value=meter.record(2,512,0.2,now=12)
        self.assertEqual(value['average_bytes_per_second'],768)
        self.assertEqual(value['readback_bytes_per_second'],2560)
        self.assertEqual(meter.snapshot(now=16)['current_bytes_per_second'],0)
        self.assertEqual(meter.snapshot(now=16)['transferred_bytes'],1536)

    def fake_monitor(self):
        mon=SessionMonitor.__new__(SessionMonitor)
        mon.observing=True
        mon.buffer=bytearray()
        mon.cancel_event=threading.Event()
        mon.wait_started=mon.last_wait_notice=time.monotonic()-600
        mon.wait_notice_sent=False
        mon._record=lambda *_:None
        mon.transport=type('Transport',(),{'read':lambda self,n:b'ABCD'})()
        return mon

    def test_live_observation_has_no_elapsed_deadline(self):
        mon=self.fake_monitor();events=[]
        mon.wait_callback=lambda kind,**values:events.append((kind,values))
        mon._fill(4,deadline=0)
        self.assertEqual(mon.buffer,b'ABCD')
        self.assertEqual(events[0][0],'link_wait')
        self.assertGreater(events[0][1]['waited_seconds'],599)

    def test_manual_stop_can_interrupt_pending_observation(self):
        mon=self.fake_monitor()
        mon.cancel_event.set()
        with self.assertRaises(Cancelled):mon._fill(4,deadline=0)


if __name__=='__main__':unittest.main()
