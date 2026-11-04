# 架构导读：completion_accumulator。
# 用首末完成边界累计 FPS，内存中保留固定数量状态，原始样本另存。
"""Bounded-memory cumulative FPS; every raw sample is saved by the caller."""
from completion_fps import calculate


# 对象 CompletionAccumulator 封装下列状态和操作，实例字段在各方法之间保持本地上下文。
class CompletionAccumulator:
    # 接口 __init__，显式输入字段：无位置参数。
    # 该函数直接更新本地状态或返回计算值，具体返回对象见函数体。
    def __init__(self):
        self.first = self.last = None
        self.count = 0

    # 接口 add，显式输入字段：sample。
    # 本函数调用入口包括 calculate。
    def add(self, sample):
        # 按条件 self.last is not None 选择后续流程，保留原有异常和退出分支。
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
