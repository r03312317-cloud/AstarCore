#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "soc_port.h"
#include "game_regs.h"
#define CHECK(x) do { if(!(x)) {fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x);exit(1);} } while(0)

static uint32_t tick,committed_at,published,published_before,active,target,error,fault;
static unsigned commits,queued,error_on_commit,fault_on_commit;
static int publication_delay,active_delay;

static void advance(void) {
    ++tick;
    uint32_t elapsed=tick-committed_at;
    if(queued && publication_delay>=0 && elapsed>=(unsigned)publication_delay)
        published=published_before+1;
    if(queued && active_delay>=0 && elapsed>=(unsigned)active_delay)active=target;
}
uint32_t test_io_read(uint32_t address) {
    advance();
    switch(address) {
    case MMIO_GAME_VIDEO+GVID_PUBLISHED:return published;
    case MMIO_GAME_VIDEO+GVID_ACTIVE_FB:return active;
    case MMIO_GAME_VIDEO+GVID_ERROR:return error;
    case MMIO_GAME_VIDEO+GVID_FAULT:return fault;
    default:return 2;
    }
}
void test_io_write(uint32_t address,uint32_t value) {
    if(address==MMIO_GAME_VIDEO+GVID_COMMIT) {
        CHECK(value==SOC_VIDEO_FB0 || value==SOC_VIDEO_FB1);
        CHECK(value!=active);
        ++commits;queued=1;target=value;committed_at=tick;published_before=published;
        error=error_on_commit;fault=fault_on_commit;
    }
}
uint64_t test_cycles(void){return (uint64_t)tick*100000u;}
void test_barrier(void){}
static void reset(uint32_t initial_active) {
    tick=committed_at=0;published=0xffffffffu;active=initial_active;
    commits=queued=error=fault=error_on_commit=fault_on_commit=0;
    publication_delay=2;active_delay=8;soc_video_init();
}
static void normal(int reverse,uint32_t initial_active) {
    reset(initial_active);
    publication_delay=reverse?8:2;active_delay=reverse?2:8;
    for(unsigned n=0;n<8;n++) {
        uint32_t old_active=active;
        uint16_t *back=soc_video_back();
        CHECK((uintptr_t)back!=active);
        unsigned before=tick;
        CHECK(soc_video_publish()==0);
        CHECK(tick-before<8); /* Queueing must return before publication. */
        CHECK(soc_video_completed()==n);
        CHECK(soc_video_publish()==-1 && commits==n+1);
        CHECK((uintptr_t)soc_video_back()==old_active);
        CHECK(tick-committed_at>=8); /* Both completion conditions matter. */
        CHECK(active==(uintptr_t)back && soc_video_completed()==n+1);
        CHECK((uintptr_t)soc_video_back()==old_active);
        CHECK(soc_video_completed()==n+1); /* No duplicate completion. */
    }
}
static void timeout(int missing_publication,int wrap_ms) {
    reset(SOC_VIDEO_FB0);
    if(wrap_ms)tick=0xffffffe0u;
    publication_delay=missing_publication?-1:2;
    active_delay=missing_publication?2:-1;
    CHECK(soc_video_publish()==0);
    CHECK(soc_video_back()==NULL);
    CHECK(tick-committed_at>120 && tick-committed_at<130);
    CHECK(soc_video_completed()==0);
    CHECK(soc_video_publish()==-1 && commits==1);
}
int main(void) {
    normal(0,SOC_VIDEO_FB0);normal(1,SOC_VIDEO_FB1);
    timeout(0,0);timeout(1,0);timeout(0,1);
    reset(SOC_VIDEO_FB0);error_on_commit=1;
    CHECK(soc_video_publish()==-1);
    CHECK(soc_video_back()==NULL); /* Accepted request remains protected. */
    CHECK(soc_video_completed()==0 && soc_video_publish()==-1 && commits==1);
    reset(SOC_VIDEO_FB1);fault_on_commit=1;
    CHECK(soc_video_publish()==0);
    CHECK(soc_video_back()==NULL);
    CHECK(soc_video_completed()==0 && soc_video_publish()==-1 && commits==1);
    puts("VIDEO_QUEUE_PASS: delayed publication/address, double queue, counter wrap, timeouts, millisecond wrap, accepted-error and scanout-fault");
    return 0;
}
