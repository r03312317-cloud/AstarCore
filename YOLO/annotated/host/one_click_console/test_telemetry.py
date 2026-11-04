# 架构导读：test_telemetry。
# 离线检查入口，用可重复输入验证本文件列出的行为条件。
import threading
import time
import unittest
import video_runner
from telemetry import Cancelled, SessionMonitor, TransferMeter


# 对象 TelemetryTests 封装下列状态和操作，实例字段在各方法之间保持本地上下文。
class TelemetryTests(unittest.TestCase):
    # 接口 test_direction_and_rolling_payload_rates，显式输入字段：无位置参数。
    # 本函数调用入口包括 TransferMeter, meter.record, self.assertEqual, meter.snapshot。
    def test_direction_and_rolling_payload_rates(self):
        # 维护本地状态/计算值：meter=TransferMeter(now=10)。
        meter=TransferMeter(now=10)
        # 维护本地状态/计算值：value=meter.record(3,1024,0.1,now=11)。
        value=meter.record(3,1024,0.1,now=11)
        self.assertEqual(value['uploaded_bytes'],1024)
        self.assertEqual(value['readback_bytes'],0)
        self.assertEqual(value['current_bytes_per_second'],1024)
        value=meter.record(2,512,0.2,now=12)
        self.assertEqual(value['average_bytes_per_second'],768)
        self.assertEqual(value['readback_bytes_per_second'],2560)
        self.assertEqual(meter.snapshot(now=16)['current_bytes_per_second'],0)
        self.assertEqual(meter.snapshot(now=16)['transferred_bytes'],1536)

    # 接口 fake_monitor，显式输入字段：无位置参数。
    # 本函数调用入口包括 SessionMonitor.__new__, bytearray, threading.Event, type('Transport', (), {'read': lambda self, n: b'ABCD'}), time.monotonic。
    def fake_monitor(self):
        mon=SessionMonitor.__new__(SessionMonitor)
        mon.observing=True
        mon.buffer=bytearray()
        mon.cancel_event=threading.Event()
        mon.wait_started=mon.last_wait_notice=time.monotonic()-600
        mon.wait_notice_sent=False
        mon._record=lambda *_:None
        mon.transport=type('Transport',(),{'read':lambda self,n:b'ABCD'})()
        # 向调用方返回本步骤结果：mon。
        return mon

    # 接口 test_live_observation_has_no_elapsed_deadline，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.fake_monitor, mon._fill, self.assertEqual, self.assertGreater, events.append。
    def test_live_observation_has_no_elapsed_deadline(self):
        mon=self.fake_monitor();events=[]
        mon.wait_callback=lambda kind,**values:events.append((kind,values))
        mon._fill(4,deadline=0)
        self.assertEqual(mon.buffer,b'ABCD')
        self.assertEqual(events[0][0],'link_wait')
        self.assertGreater(events[0][1]['waited_seconds'],599)

    # 接口 test_manual_stop_can_interrupt_pending_observation，显式输入字段：无位置参数。
    # 本函数调用入口包括 self.fake_monitor, mon.cancel_event.set, self.assertRaises, mon._fill。
    def test_manual_stop_can_interrupt_pending_observation(self):
        mon=self.fake_monitor()
        mon.cancel_event.set()
        # 资源上下文：with self.assertRaises(Cancelled):mon._fill(4,deadline=0)；离开上下文时执行对应清理约定。
        with self.assertRaises(Cancelled):mon._fill(4,deadline=0)


# 按条件 __name__ == '__main__' 选择后续流程，保留原有异常和退出分支。
if __name__=='__main__':unittest.main()
