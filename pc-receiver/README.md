# Brokenithm LAN

**[下载 Windows 独立运行包](https://github.com/MAK1MAAaa/Brokenithm-iOS-clientWLAN/releases/latest/download/Brokenithm-LAN-portable.zip)** · [查看最新 Release 与更新说明](https://github.com/MAK1MAAaa/Brokenithm-iOS-clientWLAN/releases/latest)

Windows 接收端，将 [Brokenithm-SwiftUI](https://github.com/OWCramer/Brokenithm-SwiftUI) 的 iPhone/iPad 触摸输入通过局域网转发到兼容的 CHUNITHM I/O 驱动，并回传灯光数据。

默认自动发现设备、静默等待，仅在握手成功后显示连接成功信息。支持手动 IP、自动重连、关闭灯光和按需诊断日志。

## 环境要求

- Windows，安装 .NET Framework 4.7.2 或更高版本。
- 使用启动、构建或打包脚本时，需要 Windows PowerShell 5.1 或更高版本。
- iPad/iPhone 已安装兼容的 Brokenithm-SwiftUI，并与 PC 位于可互访的同一局域网。
- 游戏已能正常运行，并加载支持 Brokenithm 共享内存协议的 ChuniIO；使用刷卡功能时还需兼容的 AimeIO。

PC 接收端不依赖 iTunes、Apple USB 驱动、Bonjour 安装包或旧版 USB 接收程序。源码构建没有 NuGet 或 .NET SDK 依赖。

## 快速开始

1. 将完整运行包解压到任意可访问的目录，保持包内文件在一起。
2. 打开 iPad 应用，允许“本地网络”权限，保持应用前台和屏幕解锁；需要 AIR 时打开应用的 Air Input。
3. 双击 `Start-LAN.cmd`。程序默认使用约 3 秒的发现窗口，没有找到设备时会静默重试。
4. 出现 `已连接 iPad：设备名称（IP）` 后启动游戏，并在游戏测试菜单核对输入。
5. 使用 Ctrl+C 停止接收端。断线后会释放输入并重新连接，重新握手成功时再次显示提示。

如 Windows 防火墙询问网络权限，在受信任的局域网允许“专用网络”。PC 可以使用网线，iPad 使用同一路由器的 Wi-Fi。

直接使用 Git 源码目录时，`Start-LAN.cmd` 会在首次运行缺少 EXE 时调用本目录的 `build.ps1`。源码和运行包均不需要父目录中的文件。

| 入口 | 行为 |
| --- | --- |
| `Start-LAN.cmd` | 自动发现，仅显示连接成功提示，不生成日志 |
| `Start-LAN-NoLED.cmd` | 相同行为，额外关闭灯光回传 |
| `Start-LAN-Diagnostics.cmd` | 自动发现，显示并保存详细诊断 |

同一 Windows 登录会话内只运行一个 USB 或 LAN 接收端。游戏与接收端需要处于同一登录会话，并使用兼容的运行权限。参数错误或程序无法启动时仍会显示必要错误。

## 카메라 AIR (추가 기능)

웹캠 영상을 브라우저의 MediaPipe 손 인식 AI로 분석해서, 손이 지나가는 높이의 IR 빔 6개를 AIR 입력으로 보냅니다. iPad의 터치 AIR와 OR로 합쳐지기 때문에 둘을 같이 써도 서로 덮어쓰지 않습니다.

1. `Start-LAN-Camera.cmd`를 실행합니다. 처음 실행할 때 `Brokenithm-LAN.exe`를 자동으로 빌드합니다.
2. `Start-Camera-Browser.cmd`를 실행합니다. 게임 창에 가려져도 멈추지 않도록 별도 프로필의 Chrome/Edge로 `http://localhost:8090/`을 엽니다.
3. 카메라 권한을 허용하고, 빨간 선(빔 1)과 파란 선(빔 6)을 끌어서 높이를 맞춥니다. 노란 세로선 두 개 밖에 있는 손은 무시합니다.
4. 테스트 메뉴의 入力テスト에서 サイドデバイス 入力1~6이 켜지는지 확인합니다.

- **120fps:** "프레임"을 120으로 두면 카메라에 120fps를 요청합니다. 대부분의 웹캠은 640×480이나 320×240에서만 120fps를 지원하니 해상도도 낮추세요. 실제로 적용된 값은 "카메라 설정" 줄에 나옵니다. 프레임은 `MediaStreamTrackProcessor`로 직접 받아서, 모니터가 60Hz여도 120fps를 전부 처리합니다(Chrome·Edge).
- **빠른 모드:** AI를 쓰지 않고, 빔 선 위의 픽셀을 미리 저장한 빈 배경과 비교해서 판정합니다. 프레임당 1ms도 걸리지 않아 120fps를 따라갑니다. 손을 치운 상태에서 "배경 저장"을 누르고, 조명이 바뀌거나 카메라가 움직였으면 다시 저장하세요. 사람이나 물건이 빔 선 뒤로 지나가도 반응하니 배경이 고정된 곳에 두세요.
- **옆모습 손 / 두 손:**
  - **인식 범위 확대(기본 켬):** 노란 인식 범위만 가로로 잘라 최대 2배로 키워서 AI에 넣습니다. 약간 옆으로 선 손(폭 55%)의 인식률이 39%에서 100%로 올랐습니다. 노란 범위를 손이 움직이는 곳에 맞게 좁힐수록 효과가 큽니다.
  - **팔까지 인식(기본 1.0배):** 손목에서 팔 방향으로 판정 범위를 늘립니다. 실기체 적외선 센서처럼, 손을 올려도 팔이 아래 빔을 계속 가립니다.
  - **추적 유지 신뢰도(기본 0.3):** 한 번 찾은 손은 각도가 바뀌어도 덜 놓칩니다.
  - **손 놓침 유지(기본 3프레임):** AI가 잠깐 손을 놓쳐도 예상 위치로 유지합니다.
- **인식 범위 자르기:** 주황 점선 사각형의 네 변(좌·우·위·아래)을 끌어서 화면을 자릅니다. 사각형 밖은 판정에서 빠지고, AI에는 사각형만 잘라 확대해서 넣습니다. "인식 범위 자르기 해제" 버튼을 누르면 화면 전체로 돌아갑니다.
- **AI 범위와 배경 범위 따로 정하기:** "배경 비교 범위를 AI 범위와 같게"를 끄면, 배경 비교(빠른 모드, 하이브리드)용 빨간 사각형을 따로 정할 수 있습니다. "AI 범위 편집 / 배경 범위 편집" 버튼으로 끌어서 바꿀 사각형을 고릅니다.
- **하이브리드 모드:** AI와 배경 비교를 함께 씁니다. 완전히 옆으로 선 손처럼 AI가 못 찾는 경우도 실루엣으로 잡습니다. 벤치마크의 빠른 움직임 이벤트 인식률은 밝음 100%, 어두움 100%, 아주 어두움 71%로 세 모드 중 가장 좋습니다. 손을 치운 상태에서 "배경 저장"이 필요합니다.
- **손 개수:** 최대 4개(두 사람)까지 인식합니다. "최대 손 개수"로 1~4개 중에 고를 수 있습니다. 손이 많을수록 AI 처리 시간이 늘어나니, 혼자 할 때는 2로 두는 편이 빠릅니다.
- **빔 높이:** 빔 선 6개를 하나씩 끌어서 옮길 수 있고, 버튼으로 전체 위아래 이동, 간격 넓히기·좁히기, 균등 배치를 할 수 있습니다.
- **보간:** 카메라 프레임 사이의 손 위치를 채워서 판정합니다. 기본값은 `부드럽게`입니다. 츄니즘 에어 판정은 노트 시점부터 +200ms까지가 JUSTICE CRITICAL이고, 일찍 들어오면 FAST JUSTICE입니다. 그래서 입력을 앞당기는 `예측`보다 약간 늦는 `부드럽게`가 유리합니다.
- **ERROR 3202 (サイドデバイスセンサー):** 게임이 부팅할 때 AIR가 가려져 있으면 납니다. 부팅이 끝날 때까지 "에어 입력 보내기"를 끄거나, 인식 범위 안에 손이나 물건이 없게 해 주세요.

- 기본값에서는 웹서버가 루프백(127.0.0.1, ::1)에서만 열립니다. 포트는 `-CameraPort`나 `--camera-port`로 바꿀 수 있습니다.

### 다른 기기(폰, 태블릿) 카메라 쓰기

브라우저는 localhost가 아닌 주소에서는 HTTPS일 때만 카메라를 열어 줍니다. 그래서 인증서가 필요합니다.

1. `Make-Camera-Cert.cmd`를 한 번 실행합니다. 같은 폴더에 `camera-cert.pfx`와 `camera-cert.cer`가 생깁니다. PC IP가 바뀌면 다시 실행하세요.
2. `Start-LAN-Camera-External.cmd`를 실행하면 `Camera AIR (other devices): https://192.168.x.x:8090/` 주소가 표시됩니다.
3. Windows 방화벽이 물어보면 **개인 네트워크**만 허용합니다.
4. 폰에서 그 주소를 엽니다. 인증서 경고가 뜨면 "고급 → 계속 진행"을 누릅니다.
   - iPhone/iPad Safari에서 경고 화면을 넘겨도 연결이 안 되면, `camera-cert.cer`를 기기로 보내서 설치한 뒤 설정 → 일반 → 정보 → 인증서 신뢰 설정에서 신뢰를 켜세요.
5. 직접 실행할 때 쓰는 옵션: `Brokenithm-LAN.exe --camera-lan --camera-cert camera-cert.pfx --camera-cert-password brokenithm`

LAN 모드에서는 같은 네트워크의 누구나 이 페이지를 열어 AIR 입력을 보낼 수 있습니다. 집처럼 믿을 수 있는 네트워크에서만 쓰세요. `camera-cert.pfx`에는 개인 키가 들어 있으니 공유하지 마세요.
- AI 모델과 런타임은 CDN(jsdelivr, storage.googleapis.com)에서 받으므로 인터넷 연결이 필요합니다.
- 페이지가 300 ms 동안 새 프레임을 처리하지 못하거나 서버가 500 ms 동안 메시지를 받지 못하면, AIR가 켜진 채로 남지 않도록 자동으로 해제합니다.
- WebSocket 메시지 형식: 텍스트 6글자(`0` 또는 `1`)이고, 빔 1(가장 낮음)부터 빔 6(가장 높음) 순서입니다.

## 游戏侧接入

接收端独立运行，通过 `Local\BROKENITHM_SHARED_BUFFER` 与游戏侧驱动交换数据。运行包不包含游戏、游戏数据或第三方 I/O DLL；这些驱动应放在游戏要求的位置，而不是接收端目录。

如果现有游戏配置已经通过 mux 加载兼容的 Brokenithm 驱动，沿用该配置即可。单 DLL 的常见配置形式如下，实际文件名以驱动说明为准：

```ini
[chuniio]
path=brokenithm.dll
```

使用提供 x86/x64 两个 DLL 的驱动及支持它们的加载器时，可能采用以下形式：

```ini
[chuniio]
path32=brokenithm_x86.dll
path64=brokenithm_x64.dll
```

按游戏与驱动的说明选择一种配置方式，不添加重复段落或同时保留冲突的生效路径。Tap Card 还需要游戏侧启用相应 AimeIO。本项目不会自动修改游戏配置或卡号文件。

## 手动连接与选项

IP 填写 iPad 的地址；自动发现模式使用设备公布的端口。

```powershell
.\Brokenithm-LAN.exe --ip 192.168.1.50
.\Brokenithm-LAN.exe --device "Living Room iPad"
.\Brokenithm-LAN.exe --no-led
.\Brokenithm-LAN.exe --diagnostics
.\Brokenithm-LAN.exe --help
```

启动脚本也接受参数，例如：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-LAN.ps1 -IP 192.168.1.50 -NoLed
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--ip` | 自动发现 | 直接连接指定 IPv4/IPv6 地址，跳过发现 |
| `--device` | 不筛选 | 按设备名或完整服务实例名筛选，与 `--ip` 互斥 |
| `--port` | 24864 | 手动 IP 模式的 TCP 端口 |
| `--no-led` | 关闭 | 传入此开关后停止灯光回传，继续处理输入 |
| `--diagnostics` | 关闭 | 输出并保存详细诊断 |
| `--log-dir` | 未指定 | 指定日志目录，同时启用诊断 |
| `--discover-timeout-ms` | 3000 | 每轮发现窗口，500–60000 毫秒 |
| `--connect-timeout-ms` | 3000 | TCP 建连超时，100–60000 毫秒 |
| `--handshake-timeout-ms` | 5000 | WEL 握手总超时，100–60000 毫秒 |
| `--retry-ms` | 1000 | 重连间隔，100–60000 毫秒 |

## 构建、验证与打包

在项目根目录运行：

```powershell
# 编译到项目根目录
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1

# 编译并执行测试
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Tests

# 编译并生成独立运行包
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Package
```

打包输出为 `dist\Brokenithm-LAN-portable.zip`。ZIP 包含 EXE、运行配置、启动脚本和说明文档，不包含源码、测试产物或本地日志，可单独复制到其他目录运行。

`build.ps1` 使用 .NET Framework 自带的 C# 编译器。也可用安装了 .NET Framework 4.7.2 targeting pack 的 Visual Studio/MSBuild 打开 `Brokenithm-LAN.csproj`。

测试使用回环 TCP、独立临时共享内存和模拟 mDNS，不连接真实 iPad 或启动游戏。覆盖分帧、输入、LED、重连、异常恢复、DNS-SD、安静模式和异步日志。已通过 11 组测试；实机日志确认过 iPad 与接收端握手及触摸输入，游戏内行为仍需对应环境验证。

## 项目结构

```text
src/                         接收端源码和 App.config
tests/                       自包含协议与集成测试
docs/PROTOCOL.md             网络协议与共享内存
docs/TROUBLESHOOTING.md      网络、日志和 iPad 限制
Brokenithm-LAN.csproj        .NET Framework 项目
build.ps1                   构建、测试与运行包生成
Start-LAN*.cmd               启动入口
Start-LAN.ps1                启动参数与源码首次构建
```

Git 仅跟踪源码、测试、脚本与文档；生成的 EXE/config、`bin/`、`dist/`、临时文件和个人日志由 `.gitignore` 排除。运行包可作为单独的发布附件分发。

排障见 [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)，实现细节见 [PROTOCOL.md](docs/PROTOCOL.md)。

## 相关项目

- [OWCramer/Brokenithm-SwiftUI](https://github.com/OWCramer/Brokenithm-SwiftUI)：兼容的 iOS/iPadOS 应用。
- [esterTion/Brokenithm-iOS](https://github.com/esterTion/Brokenithm-iOS)：原始 iOS/USB 桥接实现与协议参考。
- [Brokenithm-Evolved](https://gitea.tendokyu.moe/Dniel97/Brokenithm-Evolved)：兼容共享内存布局的 I/O 驱动参考。
