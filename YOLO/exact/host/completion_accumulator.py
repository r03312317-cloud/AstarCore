"""Bounded-memory cumulative FPS; every raw sample is saved by the caller."""
from completion_fps import calculate


class CompletionAccumulator:
    def __init__(self):
        self.first = self.last = None
        self.count = 0

    def add(self, sample):
        if self.last is not None:
            calculate([self.last, sample])
        else:
            self.first = sample
        self.last = sample
        self.count += 1
        if self.count == 1:
            return calculate([sample])
        result = calculate([self.first, sample])
        result['samples'] = self.count
        result['unsampled_completions'] = result['complete_frame_intervals'] - self.count + 1
        return result
