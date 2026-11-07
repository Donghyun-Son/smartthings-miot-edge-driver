# 개인 포크 변경 사항

[wonjj6768/smartthings-miot-edge-driver](https://github.com/wonjj6768/smartthings-miot-edge-driver)를 포크해 두 드라이버만 고쳐서 개인 채널로 배포합니다. 원본은 `upstream` 리모트, 작업은 `custom` 브랜치입니다.

## 바꾼 것

| 드라이버 | 문제 | 수정 |
|---|---|---|
| `miot/xiaomi-humidifier-p800` | 수위가 표시되지 않음 | 수위(`siid 2 / piid 13`, 0–100%)를 폴링해서 `tigerautumn15768.waterLevel`로 표시. 상세 화면과 자동화 조건에 추가 |
| `miot/xiaomi-humidifier-p800` | 과습 방지·필터 자동 건조 설정이 없음 | 과습 방지(`piid 10`)는 `tigerautumn15768.overwetProtect` (샤오미 앱처럼 상세 화면에는 강풍 모드일 때만 표시), 필터 자동 건조(`piid 11`)는 `tigerautumn15768.filterAutoDry`, 남은 건조 시간(`piid 12`, 초)은 `tigerautumn15768.dryRemainingTime`으로 추가. 한 capability에 상세 항목을 두 개 넣으면 앱에 첫 항목만 보여서 나눔. 남은 건조 시간은 상세 화면에서 수위 바로 다음에 두고, 0초일 때 숨김 (아래 "P800 화면 구성" 참고). 상세 화면 맨 아래와 자동화 조건·동작 끝에 배치 |
| `miIo/zhimi-air-purifier-v7` | 자동화(루틴)에서 모드를 바꿀 수 없음 | 원본 모드 capability는 루틴 선택지 이름이 번역되지 않는 키(`___PO_CODE_…`)로 되어 있음. 선택지 이름을 한글로 바로 쓰는 `tigerautumn15768.airPurifierMode`로 교체 (자동/수면/즐겨찾기) |

표준 capability로 바꾸거나 추가한 것:

| 드라이버 | 기능 | 표준 capability |
|---|---|---|
| P800 | 부저 (원본 커스텀에서 교체) | `audioMute` — 켜짐 = 음소거 해제 |
| P800 | 필터 수명, 필터 초기화 (추가) | `filterState` |
| P800 | 고장 감지 (추가) | `hardwareFault` — 고장 코드 1~4만 감지, 5(물 부족)는 제외 |
| V7 | PM2.5 등급 (추가) | `fineDustHealthConcern` — 15/35/75 기준, PV28-CW 드라이버와 같은 구분 |

나머지 capability(`concertmirror08464.*`)는 원작자 것을 그대로 씁니다. 원작자가 그 capability를 지우면 이 드라이버도 영향을 받습니다. 맞는 표준이 없는 것(P800 모드·목표 습도·LED 밝기, 자녀 보호 잠금, V7 표시등·즐겨찾기 단계)만 남아 있습니다.

새 커스텀 capability 정의와 한국어 번역은 [capabilities/](capabilities/)에 있습니다.

## 배포 정보

- 채널: `Xiaomi MIoT Custom` (`5b5b62d7-2ee7-43d4-b041-590239718a05`)
- 허브: `810a5073-1033-4984-83a3-6a3d965761a5`
- P800 드라이버: `da6e5252-437b-4d31-ba47-c8d665804984`
- V7 드라이버: `5385fe4d-c4e4-47aa-8412-e0899ec7102c`

## 다시 배포하기

```bash
smartthings edge:drivers:package miot/xiaomi-humidifier-p800 --channel 5b5b62d7-2ee7-43d4-b041-590239718a05 --hub 810a5073-1033-4984-83a3-6a3d965761a5
```

```bash
smartthings edge:drivers:package miIo/zhimi-air-purifier-v7 --channel 5b5b62d7-2ee7-43d4-b041-590239718a05 --hub 810a5073-1033-4984-83a3-6a3d965761a5
```

## P800 화면 구성

P800 프로필은 화면 구성(`deviceConfig`)을 프로필 안에 넣지 않고, 별도로 만든 화면 구성을 `metadata.vid`로 연결합니다. 남은 건조 시간을 0초일 때 숨기는 설정(`visibleCondition`의 `hideOnUnmatch: true`)이 프로필 안에 넣은 구성에서는 무시되기 때문입니다.

화면 구성의 원본은 [miot/xiaomi-humidifier-p800/device-config.json](miot/xiaomi-humidifier-p800/device-config.json)입니다. P800에 항목을 추가하거나 순서를 바꿀 때는:

1. `device-config.json`을 고칩니다.
2. 새 화면 구성을 만듭니다. 결과에 나오는 `vid`를 확인합니다.

   ```bash
   smartthings presentation:device-config:create -i miot/xiaomi-humidifier-p800/device-config.json -j
   ```

3. 프로필 `profiles/xiaomi-humidifier-p800.yaml`의 `metadata.vid`를 새 값으로 바꾸고 다시 배포합니다.

## 원본 업데이트 반영

```bash
git fetch upstream && git merge upstream/main
```

## 원본 드라이버로 되돌리기

```bash
smartthings edge:drivers:switch --hub 810a5073-1033-4984-83a3-6a3d965761a5 --driver 30e39b66-4cd7-4ccc-9a72-19f583e236f8 3cf07411-f8cb-4244-af6b-1e8bbca72b4b
```

```bash
smartthings edge:drivers:switch --hub 810a5073-1033-4984-83a3-6a3d965761a5 --driver d615c091-c8f4-4117-9076-d438e4c5f03d d4b30226-4ea7-4df3-90a1-d4b40fbc9660
```

첫 줄이 P800, 둘째 줄이 V7입니다.
