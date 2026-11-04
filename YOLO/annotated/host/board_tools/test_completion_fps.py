# 架构导读：test_completion_fps。
# 离线检查入口，用可重复输入验证本文件列出的行为条件。
import unittest
from completion_fps import calculate


# 对象 TestCompletionFPS 封装下列状态和操作，实例字段在各方法之间保持本地上下文。
class TestCompletionFPS(unittest.TestCase):
    # 接口 sample，显式输入字段：n, t, g。
    # 本函数调用入口包括 dict。
    def sample(self,n,t,g=None):
        return dict(completed=n,TR=t,cpu_hz=70000000,generation=n if g is None else g)

    # 接口 test_average_interval_not_average_instantaneous_rates，显式输入字段：无位置参数。
    # 本函数调用入口包括 calculate, self.assertAlmostEqual, self.assertEqual, self.sample。
    def test_average_interval_not_average_instantaneous_rates(self):
        result=calculate([self.sample(1,7000000000),self.sample(2,7014000000),self.sample(3,7035000000)])
        self.assertAlmostEqual(result['fps'],4)
        self.assertEqual(result['average_interval_ms'],250)
        self.assertEqual(result['complete_frame_intervals'],2)

    # 接口 test_missing_host_samples_use_actual_completed_count，显式输入字段：无位置参数。
    # 本函数调用入口包括 calculate, self.assertEqual, self.sample。
    def test_missing_host_samples_use_actual_completed_count(self):
        result=calculate([self.sample(5,70000000),self.sample(8,122500000)])
        self.assertEqual(result['fps'],4)
        self.assertEqual(result['unsampled_completions'],2)

    def test_invalid_source_and_clock(self):
        with self.assertRaises(ValueError):calculate([self.sample(1,1),self.sample(2,2,1)])
        with self.assertRaises(ValueError):calculate([self.sample(1,2),self.sample(2,1)])

    def test_no_early_rate(self):
        self.assertFalse(calculate([])['valid'])
        self.assertFalse(calculate([self.sample(1,1)])['valid'])


if __name__=='__main__':unittest.main()
