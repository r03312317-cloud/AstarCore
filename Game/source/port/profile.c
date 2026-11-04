// [ARCH] 定义阶段周期统计的唯一全局实例。
// [ARCH] 主循环按采样窗口读取并清零。
// [ARCH] 这组状态不属于模拟 6502 的架构寄存器或 RAM。
#include "mario_profile.h"
struct mario_costs mario_costs;
