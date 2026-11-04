// [ARCH] 把去抖后的 LEVEL 电平转换为 AM 按下/松开事件。
// [ARCH] 实体 USER_BUTTON1/2/3/4/0 对应位 0/1/2/3/4。
// [ARCH] reported 与 desired 的异或给出尚未上报变化。
// [ARCH] 每次只返回一个事件，其余变化留给后续轮询。
// [ARCH] 左右同时按下映射为下方向，否则分别给出左/右。
// [ARCH] KEY1 开始，KEY0 跳跃，KEY2 加速/火焰。
// [ARCH] 硬件已完成去抖，此层不重复实现计时去抖。
#include "mario_port.h"
/* SoC LEVEL bits: USER_BUTTON1,2,3,4,0 = bits 0,1,2,3,4. */
AM_INPUT_KEYBRD_T mario_input_event(uint8_t raw) {
    static unsigned reported;
    unsigned desired=((raw&16)?1u<<AM_KEY_J:0)|((raw&1)?1u<<AM_KEY_I:0)|((raw&2)?1u<<AM_KEY_K:0);
    if((raw&12)==12)desired|=1u<<AM_KEY_S;
    else desired|=((raw&4)?1u<<AM_KEY_A:0)|((raw&8)?1u<<AM_KEY_D:0);
    unsigned changed=desired^reported;
    for(unsigned key=1;key<=AM_KEY_D;key++)if(changed&(1u<<key)) {
        reported^=1u<<key;return (AM_INPUT_KEYBRD_T){!!(desired&(1u<<key)),(int)key};
    }
    return (AM_INPUT_KEYBRD_T){false,AM_KEY_NONE};
}
