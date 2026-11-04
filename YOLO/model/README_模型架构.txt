本目录是上次实板 YOLO 的部署模型与可检查架构数据。

best_raw_heads_int8.onnx 为本机找到的原部署导出图，SHA256 与 canonical_model/palm/package/manifest.json 完全一致：
97da0db6ca09dfc726b6bb41e93cc9a5c7f0f4690f46502d43eb467f803b8a52
文件大小 1841302 字节；本次没有重新训练、导出或量化。

输入：320x320x3 有符号 INT8，部署张量使用 HWC；原 ONNX 逻辑输入 images。
输入 scale：0.007874015718698502。
三尺度检测头：40x40、20x20、10x10，stride 8、16、32。
类别：fist / one / peace / three / four / palm。
部署参数：score_threshold_q15=8192（0.25），iou_threshold_q15=16384（0.5），候选上限512，结果上限64。

144 个语义算子展开为204个执行描述符：Conv60、Requant60、LUT57、Concat15、Pool3、Upsample2、Add7。
静态卷积运算量：518732800 MAC/帧，来自60个真实部署描述符。
Conv60_形状与计算量.csv 给出每个卷积的输入尺寸、通道数、卷积核、输出尺寸与MAC数。
reports/MODEL_ARCHITECTURE.json 给出模型和NPU的机器可读架构摘要。

canonical_model/ 中保留常量、描述符、参考图像和原始兼容元数据。
实板上传的317项常量不包含当前摄像头输入帧，共1856488字节。
包内历史 firmware_build_id=eb1fbf30aa8f08e1 是转换包兼容标识，当前实板固件身份由nonce握手确认是ed37c7c631dc7896。
参考元数据中的旧绝对路径保留为来源记录；实际验证工具使用包内文件。

模型清单中的 activation_peak_bytes=819200、accum_bytes=1638400、scratch_bytes=147456、ddr_high_watermark=5836800 仅描述模型部署分配范围，不能当作包括原始摄像头与预览缓冲的全部DDR占用。
