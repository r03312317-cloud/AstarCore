import unittest
from completion_fps import calculate


class TestCompletionFPS(unittest.TestCase):
    def sample(self,n,t,g=None):
        return dict(completed=n,TR=t,cpu_hz=70000000,generation=n if g is None else g)

    def test_average_interval_not_average_instantaneous_rates(self):
        result=calculate([self.sample(1,7000000000),self.sample(2,7014000000),self.sample(3,7035000000)])
        self.assertAlmostEqual(result['fps'],4)
        self.assertEqual(result['average_interval_ms'],250)
        self.assertEqual(result['complete_frame_intervals'],2)

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
