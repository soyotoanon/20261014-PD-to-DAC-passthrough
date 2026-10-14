# 20261014PD到DAC直通测试

2026-10-14 实物上机验证：光功率 → PD → AD9248(ADC) → FPGA 直通 → AD9767(DAC) 全链路首次跑通。

## 结论

```
CH2(DAC输出) = 1.10 × CH1(PD直出) + 45 mV，R² ≈ 0.9999（两轮共 1243 点复测一致）
```

- 斜率 1.10：电压跟随比接近 1:1（两端模拟前端增益之积，属电路常数）
- 截距 45 mV：ADC 前端零点偏置，固定常数，标定时减除
- 全量程（24~136 mV 输入）分段斜率一致，无非线性、无削顶、无乱跳

## 硬件

- FPGA：正点原子达芬奇 ATK-DF7A35 V2.1（XC7A35T-2FGG484）
- ADC：AD9248模块 V1.0（14bit@65MSPS，硬连线补码输出，前端反相）
- DAC：ACM9767 V1.3（AD9767 双通道 14bit，±5V，0.61 mV/码）
- 示波器：RIGOL DS1102Z-E（USBTMC 远程读取）

## 目录

| 路径 | 内容 |
|---|---|
| `rtl/` | 直通固件顶层（5 MHz 采样，两路复用） |
| `constraints/` | 引脚约束（达芬奇 J2 飞线分配） |
| `bitstream/` | 当天实际烧录的 bit（SHA-256 `96EB88A3…82570D`，2026-10-14 20:30 编译，WNS=+17.26 ns） |
| `scripts/` | Vivado 2023.2 批处理编译脚本 |
| `scope_monitor/` | 示波器实时测试器（pyvisa）+ 当天实测数据与拟合图 |

## 固件的两个关键修正（当天排查出的硬件特性）

```verilog
wire [13:0] adc_d_ob  = adc_d ^ 14'h2000;             // 模块硬连线补码 → 偏移二进制
wire [13:0] adc_d_fmt = INVERT_POLARITY ? ~adc_d_ob : adc_d_ob;  // 模块前端反相 → 同相
```

- 未翻 MSB 时：小信号码落在 0x3Fxx 区，DAC 钉死在 +5.25 V（当日主要故障现象）
- 通道映射：INA → 候选通道0（串口监测固件实测确认）
- 注意：Vivado 批处理脚本在 MSYS/Git Bash 下会因缺 `PROCESSOR_ARCHITECTURE` 静默退出，必须用 cmd / PowerShell 编译

## 测试器用法

```bash
pip install pyvisa   # 需已装 NI-VISA 或 IVI VISA
python scope_monitor/scope_monitor.py 150   # 采集 150 秒
```

实时读取示波器 CH1/CH2 均值电压，左图画电压-时间曲线，右图画 CH2 对 CH1 散点并拟合斜率；
结束自动保存 CSV 和 PNG。

## 测试方法

示波器 CH1 接 PD 直出（经三通并接 ADC 的 INA），CH2 接 DAC CH1 输出；
遮光 / 环境光 / 手电照各保持 2~3 秒，软件自动拟合两路关系。
