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
