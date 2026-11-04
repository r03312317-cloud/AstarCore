"""Actual acknowledged payload throughput and cancellable live UART observation."""
from collections import deque
import time
import board_common as b


class Cancelled(RuntimeError):
    pass


class TransferMeter:
    def __init__(self, now=None):
        self.started = time.monotonic() if now is None else now
        self.uploaded = self.readback = 0
        self.samples = deque()
        self.upload_seconds = self.readback_seconds = 0.0

    def record(self, opcode, count, duration, now=None):
        now = time.monotonic() if now is None else now
        if opcode not in (2, 3) or count < 0 or duration < 0:
            raise ValueError('Invalid transfer sample')
        if opcode == 3:
            self.uploaded += count
            self.upload_seconds += duration
        else:
            self.readback += count
            self.readback_seconds += duration
        self.samples.append((now, count))
        return self.snapshot(now)

    def snapshot(self, now=None):
        now = time.monotonic() if now is None else now
        while self.samples and self.samples[0][0] <= now-3:
            self.samples.popleft()
        elapsed = max(0.000001, now-self.started)
        return dict(uploaded_bytes=self.uploaded, readback_bytes=self.readback,
                    transferred_bytes=self.uploaded+self.readback,
                    current_bytes_per_second=sum(x[1] for x in self.samples)/min(3, elapsed),
                    average_bytes_per_second=(self.uploaded+self.readback)/elapsed,
                    upload_bytes_per_second=self.uploaded/self.upload_seconds if self.upload_seconds else 0,
                    readback_bytes_per_second=self.readback/self.readback_seconds if self.readback_seconds else 0,
                    elapsed_seconds=elapsed,
                    basis='Successful model payload bytes acknowledged/read back; excludes protocol framing; 3-second rolling rate')


class SessionMonitor(b.Monitor):
    checkpoint = None
    transfer_progress = None
    observation_enabled = False
    cancel_event = None
    wait_callback = None
    observing = False

    def request(self, opcode, argument=0, payload=b'', *, allow_status=()):
        if self.checkpoint:
            self.checkpoint()
        self.observing = self.observation_enabled and (opcode, argument) == (26, 0xffffffff)
        self.wait_started = self.last_wait_notice = time.monotonic()
        self.wait_notice_sent = False
        began = time.monotonic()
        try:
            status, response = super().request(opcode, argument, payload, allow_status=allow_status)
            elapsed = time.monotonic()-began
            if self.wait_notice_sent and self.wait_callback:
                self.wait_callback('link_resumed', waited_seconds=elapsed)
            if self.transfer_progress and status == 0 and opcode in (2,3):
                self.transfer_progress(opcode, len(payload) if opcode == 3 else len(response), elapsed)
            return status, response
        except Cancelled:
            self.failed = True
            raise
        finally:
            self.observing = False

    def _fill(self, count, deadline):
        if not self.observing:
            return super()._fill(count, deadline)
        # A pending read-only observation can wait indefinitely. No repeated
        # command, STOP, reconfiguration or elapsed-time abort is introduced.
        while len(self.buffer) < count:
            now = time.monotonic()
            if self.cancel_event is not None and self.cancel_event.is_set():
                raise Cancelled('已停止等待串口回应；板端停止尚未确认。可重新上板初始化。')
            if now-self.wait_started >= 3 and now-self.last_wait_notice >= 1:
                self.last_wait_notice = now
                self.wait_notice_sent = True
                if self.wait_callback:
                    self.wait_callback('link_wait', waited_seconds=now-self.wait_started)
            chunk = self.transport.read(max(1, min(4096, count-len(self.buffer))))
            self._record('rx', chunk)
            self.buffer.extend(chunk)
