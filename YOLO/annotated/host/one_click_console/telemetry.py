# 架构导读：telemetry。
# 统计成功完成的模型有效载荷字节，并在实时只读状态等待时支持人工取消。
"""Actual acknowledged payload throughput and cancellable live UART observation."""
from collections import deque
import time
import board_common as b


# 对象 Cancelled 封装下列状态和操作，实例字段在各方法之间保持本地上下文。
class Cancelled(RuntimeError):
    pass


# 对象 TransferMeter 封装下列状态和操作，实例字段在各方法之间保持本地上下文。
class TransferMeter:
    # 接口 __init__，显式输入字段：now。
    # 本函数调用入口包括 deque, time.monotonic。
    def __init__(self, now=None):
        self.started = time.monotonic() if now is None else now
        self.uploaded = self.readback = 0
        self.samples = deque()
        self.upload_seconds = self.readback_seconds = 0.0

    # 接口 record，显式输入字段：opcode, count, duration, now。
    # 本函数调用入口包括 self.samples.append, self.snapshot, time.monotonic, ValueError。
    def record(self, opcode, count, duration, now=None):
        now = time.monotonic() if now is None else now
        # 按条件 opcode not in (2, 3) or count < 0 or duration < 0 选择后续流程，保留原有异常和退出分支。
        if opcode not in (2, 3) or count < 0 or duration < 0:
            # 停止当前调用并上报异常：raise ValueError('Invalid transfer sample')。
            raise ValueError('Invalid transfer sample')
        # 按条件 opcode == 3 选择后续流程，保留原有异常和退出分支。
        if opcode == 3:
            self.uploaded += count
            self.upload_seconds += duration
        else:
            self.readback += count
            self.readback_seconds += duration
        self.samples.append((now, count))
        # 向调用方返回本步骤结果：self.snapshot(now)。
        return self.snapshot(now)

    # 接口 snapshot，显式输入字段：now。
    # 本函数调用入口包括 max, dict, time.monotonic, self.samples.popleft, sum。
    def snapshot(self, now=None):
        now = time.monotonic() if now is None else now
        # 迭代/等待条件：self.samples and self.samples[0][0] <= now - 3；退出由原循环条件及显式 break/异常决定。
        while self.samples and self.samples[0][0] <= now-3:
            self.samples.popleft()
        elapsed = max(0.000001, now-self.started)
        # 向调用方返回本步骤结果：dict(uploaded_bytes=self.uploaded, readback_bytes=self.readback,。
        return dict(uploaded_bytes=self.uploaded, readback_bytes=self.readback,
                    transferred_bytes=self.uploaded+self.readback,
                    current_bytes_per_second=sum(x[1] for x in self.samples)/min(3, elapsed),
                    average_bytes_per_second=(self.uploaded+self.readback)/elapsed,
                    upload_bytes_per_second=self.uploaded/self.upload_seconds if self.upload_seconds else 0,
                    readback_bytes_per_second=self.readback/self.readback_seconds if self.readback_seconds else 0,
                    elapsed_seconds=elapsed,
                    basis='Successful model payload bytes acknowledged/read back; excludes protocol framing; 3-second rolling rate')


# 对象 SessionMonitor 封装下列状态和操作，实例字段在各方法之间保持本地上下文。
class SessionMonitor(b.Monitor):
    checkpoint = None
    transfer_progress = None
    observation_enabled = False
    cancel_event = None
    wait_callback = None
    observing = False

    # 接口 request，显式输入字段：opcode, argument, payload。
    # 本函数调用入口包括 time.monotonic, self.checkpoint, super().request, self.wait_callback, self.transfer_progress。
    def request(self, opcode, argument=0, payload=b'', *, allow_status=()):
        # 按条件 self.checkpoint 选择后续流程，保留原有异常和退出分支。
        if self.checkpoint:
            self.checkpoint()
        self.observing = self.observation_enabled and (opcode, argument) == (26, 0xffffffff)
        self.wait_started = self.last_wait_notice = time.monotonic()
        self.wait_notice_sent = False
        began = time.monotonic()
        # 异常边界：保存当前步骤的错误信息，并沿原 except/finally 路径处理清理。
        try:
            status, response = super().request(opcode, argument, payload, allow_status=allow_status)
            elapsed = time.monotonic()-began
            # 按条件 self.wait_notice_sent and self.wait_callback 选择后续流程，保留原有异常和退出分支。
            if self.wait_notice_sent and self.wait_callback:
                self.wait_callback('link_resumed', waited_seconds=elapsed)
            # 按条件 self.transfer_progress and status == 0 and (opcode in (2, 3)) 选择后续流程，保留原有异常和退出分支。
            if self.transfer_progress and status == 0 and opcode in (2,3):
                self.transfer_progress(opcode, len(payload) if opcode == 3 else len(response), elapsed)
            return status, response
        except Cancelled:
            self.failed = True
            # 停止当前调用并上报异常：raise。
            raise
        finally:
            self.observing = False

    # 接口 _fill，显式输入字段：count, deadline。
    # 本函数调用入口包括 super()._fill, len, time.monotonic, self.transport.read, self._record。
    def _fill(self, count, deadline):
        # 按条件 not self.observing 选择后续流程，保留原有异常和退出分支。
        if not self.observing:
            return super()._fill(count, deadline)
        # A pending read-only observation can wait indefinitely. No repeated
        # command, STOP, reconfiguration or elapsed-time abort is introduced.
        while len(self.buffer) < count:
            now = time.monotonic()
            # 按条件 self.cancel_event is not None and self.cancel_event.is_set() 选择后续流程，保留原有异常和退出分支。
            if self.cancel_event is not None and self.cancel_event.is_set():
                # 停止当前调用并上报异常：raise Cancelled('已停止等待串口回应；板端停止尚未确认。可重新上板初始化。')。
                raise Cancelled('已停止等待串口回应；板端停止尚未确认。可重新上板初始化。')
            # 按条件 now - self.wait_started >= 3 and now - self.last_wait_notice >= 1 选择后续流程，保留原有异常和退出分支。
            if now-self.wait_started >= 3 and now-self.last_wait_notice >= 1:
                self.last_wait_notice = now
                self.wait_notice_sent = True
                # 按条件 self.wait_callback 选择后续流程，保留原有异常和退出分支。
                if self.wait_callback:
                    self.wait_callback('link_wait', waited_seconds=now-self.wait_started)
            chunk = self.transport.read(max(1, min(4096, count-len(self.buffer))))
            self._record('rx', chunk)
            self.buffer.extend(chunk)
