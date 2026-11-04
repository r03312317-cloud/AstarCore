// SPDX-License-Identifier: GPL-2.0-only
/* Generic RV32 RGB565 scanout control. Requires integrated scan DMA.
 * Memory is reserved/no-map in DT, but Sv32 without Svpbmt has no uncached PTE.
 * This platform therefore uses explicit ownership transfer in fb_pan_display:
 * RV32-specific FENCE.I cleans the entire D-cache; the following MMIO request
 * is stalled by the cache until maintenance has completed. This is a custom
 * RTL contract, NOT a portable meaning of architectural FENCE.I. Applications
 * must draw only into the non-active buffer then pan; raw mmap alone is not
 * coherent. DTS stays disabled until scanout is integrated and verified.
 */
#include <linux/fb.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of_address.h>
#include <linux/platform_device.h>
#include <linux/iopoll.h>
#define W 640
#define H 360
#define FRAME (W*H*2)
struct astfb { void __iomem *regs; u32 palette[16]; };
// 只接受本平台支持的 640 乘 360 RGB565 双页几何与合法页偏移。
static int astfb_check(struct fb_var_screeninfo *v, struct fb_info *info) {
 if(v->xres!=W||v->yres!=H||v->xres_virtual!=W||v->yres_virtual!=H*2||v->bits_per_pixel!=16||v->xoffset|| (v->yoffset!=0&&v->yoffset!=H))return -EINVAL;
 return 0;
}
// 先等待前次提交完成，执行本平台 cache 清理契约，再提交并检查活动帧地址。
static int astfb_pan(struct fb_var_screeninfo *v,struct fb_info *info) {
 struct astfb *p=info->par;u32 status;int ret;
 if(v->xoffset||(v->yoffset!=0&&v->yoffset!=H))return -EINVAL;
 // 有界轮询硬件状态，超时直接回报调用者，避免永久等待被误记为完成。
 ret=readl_poll_timeout(p->regs+8,status,!(status&1),100,100000);
 if(ret)return ret;
 /* Custom RV32 full-D-clean contract; next MMIO waits for completion. */
 // 此处使用 RV32 自定义全 D-cache 清理契约，不能把它当作通用 RISC V FENCE I 的保证。
 asm volatile("fence.i" ::: "memory");
 wmb();writel(info->fix.smem_start+v->yoffset*W*2,p->regs);
 writel(1,p->regs+4);writel(1,p->regs+8);
 ret=readl_poll_timeout(p->regs+8,status,!(status&1),100,100000);
 if(ret)return ret;
 return readl(p->regs+0xc)==info->fix.smem_start+v->yoffset*W*2 ? 0 : -EIO;
}
// 按 RGB565 位域构造伪调色板值，调色板索引必须小于 16。
static int astfb_setcol(unsigned reg,unsigned red,unsigned green,unsigned blue,unsigned transp,struct fb_info *info) {
 struct astfb *p=info->par;if(reg>=16)return -EINVAL;
 p->palette[reg]=((red>>11)<<11)|((green>>10)<<5)|(blue>>11);return 0;
}
static const struct fb_ops astfb_ops={.owner=THIS_MODULE,FB_DEFAULT_IOMEM_OPS,
 .fb_check_var=astfb_check,.fb_pan_display=astfb_pan,.fb_setcolreg=astfb_setcol};
// 从设备树取得寄存器和保留显存，检查硬件几何后注册 /dev/fb0。
static int astfb_probe(struct platform_device *pdev) {
 struct device_node *mem;struct resource r;struct fb_info *info;struct astfb *p;int ret;
 mem=of_parse_phandle(pdev->dev.of_node,"memory-region",0);if(!mem)return -EINVAL;
 ret=of_address_to_resource(mem,0,&r);of_node_put(mem);if(ret)return ret;
 if(resource_size(&r)<2*FRAME||r.start>U32_MAX)return -EINVAL;
 info=framebuffer_alloc(sizeof(*p),&pdev->dev);if(!info)return -ENOMEM;p=info->par;
 p->regs=devm_platform_ioremap_resource(pdev,0);if(IS_ERR(p->regs)){ret=PTR_ERR(p->regs);goto release;}
 if(readl(p->regs+0x20)!=W||readl(p->regs+0x24)!=H||readl(p->regs+0x28)!=W*2){ret=-ENODEV;goto release;}
 info->screen_base=ioremap(r.start,2*FRAME);if(!info->screen_base){ret=-ENOMEM;goto release;}
 info->screen_size=2*FRAME;info->fix=(struct fb_fix_screeninfo){.id="rv32-rgb565",.smem_start=r.start,.smem_len=2*FRAME,.type=FB_TYPE_PACKED_PIXELS,.visual=FB_VISUAL_TRUECOLOR,.line_length=W*2,.ypanstep=H};
 info->var=(struct fb_var_screeninfo){.xres=W,.yres=H,.xres_virtual=W,.yres_virtual=H*2,.bits_per_pixel=16,.red={11,5,0},.green={5,6,0},.blue={0,5,0},.width=-1,.height=-1,.activate=FB_ACTIVATE_NOW};
 info->fbops=&astfb_ops;info->pseudo_palette=p->palette;info->flags=0;
 memset_io(info->screen_base,0,2*FRAME);ret=astfb_pan(&info->var,info);if(ret)goto unmap;
 // 注册成功后用户空间才可通过 /dev/fb0 访问这一显示设备。
 ret=register_framebuffer(info);if(ret)goto unmap;
 platform_set_drvdata(pdev,info);return 0;
 unmap:iounmap(info->screen_base);
 release:framebuffer_release(info);return ret;
}
// 注销 framebuffer 并关闭显示，释放本驱动映射及分配的资源。
static void astfb_remove(struct platform_device *pdev) {
 struct fb_info *info=platform_get_drvdata(pdev);struct astfb *p=info->par;
 unregister_framebuffer(info);writel(0,p->regs+4);writel(1,p->regs+8);
 iounmap(info->screen_base);framebuffer_release(info);
}
static const struct of_device_id astfb_match[]={{.compatible="rv32,framebuffer-v1"},{}};
MODULE_DEVICE_TABLE(of,astfb_match);
static struct platform_driver astfb_driver={.probe=astfb_probe,.remove=astfb_remove,.driver={.name="rv32-fb",.of_match_table=astfb_match}};
module_platform_driver(astfb_driver);MODULE_LICENSE("GPL");MODULE_DESCRIPTION("RV32 vblank RGB565 framebuffer");
