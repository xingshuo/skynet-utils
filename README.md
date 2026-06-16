# skynet-utils
基于skynet框架封装的工具箱

## 运行测试用例
* 将编译后的skynet仓库连接到工程目录下
```bash
# ln -sf $YOUR_SKYNET_PATH skynet
```
* 运行timer测试用例
```bash
# ./skynet/skynet test/timer/config
```
* 运行timer各实现的性能benchmark（对比5种实现 Push/OnTick 在不同量级下的耗时与内存）
```bash
# ./skynet/skynet test/timer/benchmark_config
```