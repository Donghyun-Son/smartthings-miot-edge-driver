-- Xiaomi Humidifier P800 Driver

local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"
local discovery = require "discovery"
local miot = require "miot"

-- 커스텀 Capability 참조

local capFanmodeFanMode = capabilities["concertmirror08464.xiaomiHumP800FanMode"]
local capTargethumidityTargetHumidity = capabilities["concertmirror08464.xiaomiHumP800TargetHumidity"]
local deviceControlsChildLock = capabilities["concertmirror08464.xiaomiHumP800ChildLock"]
local deviceControlsLedBrightness = capabilities["concertmirror08464.xiaomiHumP800LedBrightness"]
local capWaterLevel = capabilities["tigerautumn15768.waterLevel"]
local capOverwetProtect = capabilities["tigerautumn15768.overwetProtect"]
local capFilterAutoDry = capabilities["tigerautumn15768.filterAutoDry"]

-- 상수 정의

local POLLING_TIMER = "polling_timer"
local DEFAULT_POLLING_INTERVAL = 60

-- MIoT 서비스 ID (P800 스펙 기준)
local HUMIDIFIER_SIID = 2       -- 가습기
local ENVIRONMENT_SIID = 3      -- 환경 센서

-- MIoT 속성 ID (가습기 서비스 siid=2)
local POWER_PIID = 1            -- 전원 on/off
local MODE_PIID = 3             -- 모드 (0=Constant, 1=Sleep, 2=Strong)
local TARGET_HUMIDITY_PIID = 6  -- 목표 습도 (40-70%)
local WATER_LEVEL_PIID = 13     -- 수위 (0-100%)
local FAULT_PIID = 2            -- 고장 코드 (0=정상, 1~4=고장, 5=물 부족)
local OVERWET_PROTECT_PIID = 10 -- 과습 방지
local AUTO_DRY_PIID = 11        -- 필터 자동 건조
local DRY_REMAIN_PIID = 12      -- 남은 건조 시간 (초, 0-1000)

-- MIoT 속성 ID (기기 제어 서비스)
local BUZZER_SIID = 5
local BUZZER_PIID = 1
local SCREEN_SIID = 6
local SCREEN_SWITCH_PIID = 1
local SCREEN_BRIGHTNESS_PIID = 2
local CHILD_LOCK_SIID = 7
local CHILD_LOCK_PIID = 1
local FILTER_SIID = 4
local FILTER_LIFE_PIID = 1
local FILTER_RESET_AIID = 1
local LED_BRIGHTNESS_TO_ST = {
    [0] = "dim",
    [1] = "bright"
}
local ST_TO_LED_BRIGHTNESS = {
    dim = 0,
    bright = 1
}

-- MIoT 속성 ID (환경 센서 siid=3)
local HUMIDITY_PIID = 1         -- 상대 습도
local TEMPERATURE_PIID = 2      -- 온도

-- 변환 테이블

-- 모드 변환 (MIoT -> Capability)
local MODE_TO_ST = {
    [0] = "constant",
    [1] = "sleep",
    [2] = "strong"
}

-- 모드 변환 (Capability -> MIoT)
local ST_TO_MODE = {
    constant = 0,
    sleep = 1,
    strong = 2
}

-- 헬퍼 함수

-- 장치 설정 확인 (IP, 토큰)
local function get_device_config(device)
    local ip = device.preferences.ipAddress
    local token = device.preferences.token
    
    if ip and ip ~= "" and token and #token == 32 then
        return ip, token
    end
    return nil, nil
end

-- 폴링 함수

-- 장치 상태 조회
local function poll_device_status(device)
    local ip, token = get_device_config(device)
    if not ip then
        return
    end
    
    -- 조회할 속성 목록
    local properties = {
        {siid = HUMIDIFIER_SIID, piid = POWER_PIID},
        {siid = HUMIDIFIER_SIID, piid = MODE_PIID},
        {siid = HUMIDIFIER_SIID, piid = TARGET_HUMIDITY_PIID},
        {siid = HUMIDIFIER_SIID, piid = WATER_LEVEL_PIID},
        {siid = HUMIDIFIER_SIID, piid = FAULT_PIID},
        {siid = HUMIDIFIER_SIID, piid = OVERWET_PROTECT_PIID},
        {siid = HUMIDIFIER_SIID, piid = AUTO_DRY_PIID},
        {siid = HUMIDIFIER_SIID, piid = DRY_REMAIN_PIID},
        {siid = BUZZER_SIID, piid = BUZZER_PIID},
        {siid = SCREEN_SIID, piid = SCREEN_SWITCH_PIID},
        {siid = SCREEN_SIID, piid = SCREEN_BRIGHTNESS_PIID},
        {siid = CHILD_LOCK_SIID, piid = CHILD_LOCK_PIID},
        {siid = FILTER_SIID, piid = FILTER_LIFE_PIID},
        {siid = ENVIRONMENT_SIID, piid = HUMIDITY_PIID},
        {siid = ENVIRONMENT_SIID, piid = TEMPERATURE_PIID}
    }
    
    -- MIoT로 속성 조회
    local ok, response = pcall(miot.gets, device, ip, token, properties)
    if not ok then
        log.error("폴링 실패: " .. tostring(response))
        return
    end
    
    if not response or not response.result then
        return
    end
    
    -- 응답 처리
    local screen_on = nil
    device:emit_event(capabilities.filterState.supportedFilterCommands({value = {"resetFilter"}}))
    for _, result in ipairs(response.result) do
        if result.code == 0 then
            local siid = result.siid
            local piid = result.piid
            local value = result.value
            
            -- 가습기 데이터
            if siid == HUMIDIFIER_SIID then
                if piid == POWER_PIID then
                    device:emit_event(capabilities.switch.switch(value and "on" or "off"))
                elseif piid == MODE_PIID then
                    local mode = MODE_TO_ST[value] or "constant"
                    device:emit_event(capFanmodeFanMode.fanMode({value = mode}))
                elseif piid == TARGET_HUMIDITY_PIID then
                    device:emit_event(capTargethumidityTargetHumidity.targetHumidity({value = value, unit = "%"}))
                elseif piid == WATER_LEVEL_PIID and type(value) == "number" then
                    local level = math.max(0, math.min(100, math.floor(value)))
                    device:emit_event(capWaterLevel.waterLevel({value = level, unit = "%"}))
                elseif piid == FAULT_PIID and type(value) == "number" then
                    -- 5(물 부족)는 고장이 아니라 수위로 보여준다
                    local detected = value >= 1 and value <= 4
                    device:emit_event(detected and capabilities.hardwareFault.hardwareFault.detected()
                        or capabilities.hardwareFault.hardwareFault.clear())
                elseif piid == OVERWET_PROTECT_PIID and type(value) == "boolean" then
                    device:emit_event(capOverwetProtect.overwetProtect({value = value and "on" or "off"}))
                elseif piid == AUTO_DRY_PIID and type(value) == "boolean" then
                    device:emit_event(capFilterAutoDry.autoDry({value = value and "on" or "off"}))
                elseif piid == DRY_REMAIN_PIID and type(value) == "number" then
                    local remain = math.max(0, math.min(1000, math.floor(value)))
                    device:emit_event(capFilterAutoDry.dryRemainingTime({value = remain}))
                end
            elseif siid == BUZZER_SIID and piid == BUZZER_PIID then
                device:emit_event(value and capabilities.audioMute.mute.unmuted()
                    or capabilities.audioMute.mute.muted())
            elseif siid == SCREEN_SIID and piid == SCREEN_SWITCH_PIID then
                screen_on = value
                if not value then
                    device:emit_event(deviceControlsLedBrightness.ledBrightness({value = "off"}))
                end
            elseif siid == SCREEN_SIID and piid == SCREEN_BRIGHTNESS_PIID then
                local brightness = LED_BRIGHTNESS_TO_ST[value]
                if brightness and screen_on ~= false then
                    device:emit_event(deviceControlsLedBrightness.ledBrightness({value = brightness}))
                end
            elseif siid == CHILD_LOCK_SIID and piid == CHILD_LOCK_PIID then
                device:emit_event(deviceControlsChildLock.childLock({value = value and "on" or "off"}))
            elseif siid == FILTER_SIID and piid == FILTER_LIFE_PIID and type(value) == "number" then
                local life = math.max(0, math.min(100, math.floor(value)))
                device:emit_event(capabilities.filterState.filterLifeRemaining({value = life, unit = "%"}))
            -- 환경 센서 데이터
            elseif siid == ENVIRONMENT_SIID then
                if piid == HUMIDITY_PIID then
                    device:emit_event(capabilities.relativeHumidityMeasurement.humidity(value))
                elseif piid == TEMPERATURE_PIID then
                    device:emit_event(capabilities.temperatureMeasurement.temperature({value = value, unit = "C"}))
                end
            end
        end
    end
end

-- 폴링 타이머 시작
local function start_polling_timer(device)
    local interval = device.preferences.pollingInterval or DEFAULT_POLLING_INTERVAL
    local timer = device.thread:call_on_schedule(interval, function()
        pcall(poll_device_status, device)
    end, "Polling")
    device:set_field(POLLING_TIMER, timer)
end

-- 폴링 타이머 중지
local function stop_polling_timer(device)
    local timer = device:get_field(POLLING_TIMER)
    if timer then
        device.thread:cancel_timer(timer)
        device:set_field(POLLING_TIMER, nil)
    end
end

-- 명령 핸들러

-- 전원 켜기
local function switch_on_handler(_, device, _)
    local ip, token = get_device_config(device)
    if not ip then return end
    
    local ok, _ = pcall(miot.set, device, ip, token, HUMIDIFIER_SIID, POWER_PIID, true)
    if ok then
        device:emit_event(capabilities.switch.switch.on())
        -- 상태 갱신
        device.thread:call_with_delay(1, function()
            pcall(poll_device_status, device)
        end)
    end
end

-- 전원 끄기
local function switch_off_handler(_, device, _)
    local ip, token = get_device_config(device)
    if not ip then return end
    
    local ok, _ = pcall(miot.set, device, ip, token, HUMIDIFIER_SIID, POWER_PIID, false)
    if ok then
        device:emit_event(capabilities.switch.switch.off())
    end
end

-- 모드 설정
local function set_mode_handler(_, device, command)
    local ip, token = get_device_config(device)
    if not ip then return end
    
    local mode = command.args.mode
    local mode_value = ST_TO_MODE[mode]
    if mode_value == nil then return end
    
    -- 전원이 꺼져있으면 먼저 켜기
    pcall(miot.set, device, ip, token, HUMIDIFIER_SIID, POWER_PIID, true)
    
    local ok, _ = pcall(miot.set, device, ip, token, HUMIDIFIER_SIID, MODE_PIID, mode_value)
    if ok then
        device:emit_event(capabilities.switch.switch.on())
        device:emit_event(capFanmodeFanMode.fanMode({value = mode}))
    end
end

-- 모드 단축 명령
local function set_constant_handler(_, device, _)
    local ip, token = get_device_config(device)
    if not ip then return end
    
    pcall(miot.set, device, ip, token, HUMIDIFIER_SIID, POWER_PIID, true)
    local ok, _ = pcall(miot.set, device, ip, token, HUMIDIFIER_SIID, MODE_PIID, 0)
    if ok then
        device:emit_event(capabilities.switch.switch.on())
        device:emit_event(capFanmodeFanMode.fanMode({value = "constant"}))
    end
end

local function set_sleep_handler(_, device, _)
    local ip, token = get_device_config(device)
    if not ip then return end
    
    pcall(miot.set, device, ip, token, HUMIDIFIER_SIID, POWER_PIID, true)
    local ok, _ = pcall(miot.set, device, ip, token, HUMIDIFIER_SIID, MODE_PIID, 1)
    if ok then
        device:emit_event(capabilities.switch.switch.on())
        device:emit_event(capFanmodeFanMode.fanMode({value = "sleep"}))
    end
end

local function set_strong_handler(_, device, _)
    local ip, token = get_device_config(device)
    if not ip then return end
    
    pcall(miot.set, device, ip, token, HUMIDIFIER_SIID, POWER_PIID, true)
    local ok, _ = pcall(miot.set, device, ip, token, HUMIDIFIER_SIID, MODE_PIID, 2)
    if ok then
        device:emit_event(capabilities.switch.switch.on())
        device:emit_event(capFanmodeFanMode.fanMode({value = "strong"}))
    end
end

-- 목표 습도 설정
local function set_target_humidity_handler(_, device, command)
    local ip, token = get_device_config(device)
    if not ip then return end
    
    local humidity = command.args.humidity
    -- P800 스펙에서 40-70% 범위 제한
    humidity = math.max(40, math.min(70, humidity))
    
    local ok, _ = pcall(miot.set, device, ip, token, HUMIDIFIER_SIID, TARGET_HUMIDITY_PIID, humidity)
    if ok then
        device:emit_event(capTargethumidityTargetHumidity.targetHumidity({value = humidity, unit = "%"}))
    end
end

local function set_led_brightness_handler(_, device, command)
    local ip, token = get_device_config(device)
    if not ip then return end

    local brightness = command.args.brightness
    if brightness == "off" then
        local ok = pcall(miot.set, device, ip, token, SCREEN_SIID, SCREEN_SWITCH_PIID, false)
        if ok then
            device:emit_event(deviceControlsLedBrightness.ledBrightness({value = "off"}))
        end
        return
    end

    local value = ST_TO_LED_BRIGHTNESS[brightness]
    if value == nil then return end

    pcall(miot.set, device, ip, token, SCREEN_SIID, SCREEN_SWITCH_PIID, true)
    local ok = pcall(miot.set, device, ip, token, SCREEN_SIID, SCREEN_BRIGHTNESS_PIID, value)
    if ok then
        device:emit_event(deviceControlsLedBrightness.ledBrightness({value = brightness}))
    end
end

-- 부저: 켜짐 = 음소거 해제, 꺼짐 = 음소거
local function set_buzzer(device, enabled)
    local ip, token = get_device_config(device)
    if not ip then return end

    local ok = pcall(miot.set, device, ip, token, BUZZER_SIID, BUZZER_PIID, enabled)
    if ok then
        device:emit_event(enabled and capabilities.audioMute.mute.unmuted()
            or capabilities.audioMute.mute.muted())
    end
end

local function set_mute_handler(_, device, command)
    set_buzzer(device, command.args.state == "unmuted")
end

local function mute_handler(_, device, _)
    set_buzzer(device, false)
end

local function unmute_handler(_, device, _)
    set_buzzer(device, true)
end

-- 과습 방지 / 필터 자동 건조 (가습기 서비스의 on/off 속성)
local function set_humidifier_toggle(device, piid, enabled, emit)
    local ip, token = get_device_config(device)
    if not ip then return end

    local ok = pcall(miot.set, device, ip, token, HUMIDIFIER_SIID, piid, enabled)
    if ok then
        emit(enabled and "on" or "off")
    end
end

local function set_overwet_protect_handler(_, device, command)
    set_humidifier_toggle(device, OVERWET_PROTECT_PIID, command.args.overwetProtect == "on", function(state)
        device:emit_event(capOverwetProtect.overwetProtect({value = state}))
    end)
end

local function set_auto_dry_handler(_, device, command)
    set_humidifier_toggle(device, AUTO_DRY_PIID, command.args.autoDry == "on", function(state)
        device:emit_event(capFilterAutoDry.autoDry({value = state}))
    end)
end

-- 필터 수명 초기화
local function reset_filter_handler(_, device, _)
    local ip, token = get_device_config(device)
    if not ip then return end

    local ok, err = pcall(miot.action, device, ip, token, FILTER_SIID, FILTER_RESET_AIID)
    if not ok then
        log.error("필터 초기화 실패: " .. tostring(err))
        return
    end
    device.thread:call_with_delay(1, function()
        pcall(poll_device_status, device)
    end)
end

local function set_child_lock_handler(_, device, command)
    local ip, token = get_device_config(device)
    if not ip then return end

    local value = command.args.childLock == "on"
    local ok = pcall(miot.set, device, ip, token, CHILD_LOCK_SIID, CHILD_LOCK_PIID, value)
    if ok then
        device:emit_event(deviceControlsChildLock.childLock({value = command.args.childLock}))
    end
end

-- 새로고침
local function refresh_handler(_, device, _)
    pcall(poll_device_status, device)
end

-- 라이프사이클 핸들러

-- 장치 추가됨
local function ensure_profile(device)
    if not device:supports_capability_by_id(capFanmodeFanMode.ID, "main")
        or not device:supports_capability_by_id(capWaterLevel.ID, "main")
        or not device:supports_capability_by_id(capabilities.audioMute.ID, "main")
        or not device:supports_capability_by_id(capabilities.filterState.ID, "main")
        or not device:supports_capability_by_id(capabilities.hardwareFault.ID, "main")
        or not device:supports_capability_by_id(capOverwetProtect.ID, "main")
        or not device:supports_capability_by_id(capFilterAutoDry.ID, "main") then
        device:try_update_metadata({profile = "xiaomi-humidifier-p800"})
    end
end

local function device_added(_, device)
    ensure_profile(device)
    -- 초기값 설정
    device:emit_event(capabilities.switch.switch.off())
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = 0, unit = "C"}))
    device:emit_event(capabilities.relativeHumidityMeasurement.humidity(0))
    device:emit_event(capFanmodeFanMode.fanMode({value = "constant"}))
    device:emit_event(capTargethumidityTargetHumidity.targetHumidity({value = 50, unit = "%"}))
    device:emit_event(deviceControlsLedBrightness.ledBrightness({value = "bright"}))
    device:emit_event(deviceControlsChildLock.childLock({value = "off"}))
end

-- 장치 초기화
local function device_init(_, device)
    ensure_profile(device)
    device:online()
    
    local ip, token = get_device_config(device)
    if ip then
        start_polling_timer(device)
        pcall(poll_device_status, device)
    end
end

-- 장치 제거됨
local function device_removed(_, device)
    stop_polling_timer(device)
end

-- 설정 변경됨
local function device_info_changed(driver, device, _, args)
    if not args.old_st_store or not args.old_st_store.preferences then
        return
    end
    
    local old = args.old_st_store.preferences
    local new = device.preferences
    
    -- 새 장치 생성 요청
    if old.createDev == false and new.createDev == true then
        discovery.create_device(driver)
    end
    
    -- 설정이 변경되면 폴링 재시작
    if old.ipAddress ~= new.ipAddress or old.token ~= new.token or old.pollingInterval ~= new.pollingInterval then
        stop_polling_timer(device)
        
        local ip, token = get_device_config(device)
        if ip then
            start_polling_timer(device)
            pcall(poll_device_status, device)
        end
    end
end

-- 드라이버 실행

local driver = Driver("miot-humidifier-p800", {
    discovery = discovery.handle_discovery,
    lifecycle_handlers = {
        added = device_added,
        init = device_init,
        removed = device_removed,
        infoChanged = device_info_changed
    },
    capability_handlers = {
        [capabilities.switch.ID] = {
            [capabilities.switch.commands.on.NAME] = switch_on_handler,
            [capabilities.switch.commands.off.NAME] = switch_off_handler
        },
        [capFanmodeFanMode.ID] = {
            [capFanmodeFanMode.commands.setFanMode.NAME] = set_mode_handler,
            [capFanmodeFanMode.commands.setConstant.NAME] = set_constant_handler,
            [capFanmodeFanMode.commands.setSleep.NAME] = set_sleep_handler,
            [capFanmodeFanMode.commands.setStrong.NAME] = set_strong_handler
        },
        [capTargethumidityTargetHumidity.ID] = {
            [capTargethumidityTargetHumidity.commands.setTargetHumidity.NAME] = set_target_humidity_handler
        },
        [deviceControlsLedBrightness.ID] = {
            [deviceControlsLedBrightness.commands.setLedBrightness.NAME] = set_led_brightness_handler
        },
        [capabilities.audioMute.ID] = {
            [capabilities.audioMute.commands.setMute.NAME] = set_mute_handler,
            [capabilities.audioMute.commands.mute.NAME] = mute_handler,
            [capabilities.audioMute.commands.unmute.NAME] = unmute_handler
        },
        [capabilities.filterState.ID] = {
            [capabilities.filterState.commands.resetFilter.NAME] = reset_filter_handler
        },
        [capOverwetProtect.ID] = {
            [capOverwetProtect.commands.setOverwetProtect.NAME] = set_overwet_protect_handler
        },
        [capFilterAutoDry.ID] = {
            [capFilterAutoDry.commands.setAutoDry.NAME] = set_auto_dry_handler
        },
        [deviceControlsChildLock.ID] = {
            [deviceControlsChildLock.commands.setChildLock.NAME] = set_child_lock_handler
        },
        [capabilities.refresh.ID] = {
            [capabilities.refresh.commands.refresh.NAME] = refresh_handler
        }
    }
})

driver:run()
