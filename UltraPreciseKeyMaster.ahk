; -----------------------------------------------------------------------------
; UltraPreciseKeyMaster v1.1.0
; Copyright (C) 2025 SIGMAT3CH
;
; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program. If not, see <https://www.gnu.org/licenses/>.
; -----------------------------------------------------------------------------

; Ultra-Precise Keypress Script - Maximum Timing Accuracy
#SingleInstance Force
#NoEnv
SetWorkingDir %A_ScriptDir%
#KeyHistory 0
Process, Priority,, Realtime
Thread, Priority, 100
SetBatchLines, -1
SetKeyDelay, -1, -1, -1
SendMode, Input
SetDefaultMouseSpeed, 0
#MaxThreadsPerHotkey 2

global isActive := false
global holdTime := 344.44
global isHolding := false
global timingDiagnostics := false

global freq := 0
global systemOverhead := 0
global targetTime := holdTime
global adjustment := 0
global timingSamples := []
global lastCalibrationTime := 0

global calibrationIterations := 50
global outlierThreshold := 0.2
global movingAvgWindow := 15
global calibrationInterval := 120000
global spinlockThreshold := 0.005
global adaptiveOverhead := true

InitializeScript() {
    DllCall("Winmm\timeBeginPeriod", "UInt", 1)
    DllCall("QueryPerformanceFrequency", "Int64*", freq)
    SetCPUAffinity()
    ShowPopup("Performing ultra-precise calibration...")
    systemOverhead := CalibrateOverhead()
    ShowPopup("Calibration complete. Overhead: " . Round(systemOverhead, 4) . "ms")
    DllCall("QueryPerformanceCounter", "Int64*", lastCalibrationTime)
    PerformWarmup()
}

SetCPUAffinity() {
    ProcessID := DllCall("GetCurrentProcessId")
    hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", false, "UInt", ProcessID, "Ptr")
    DllCall("SetProcessAffinityMask", "Ptr", hProcess, "UInt", 1)
    DllCall("CloseHandle", "Ptr", hProcess)
}

CalibrateOverhead() {
    iterations := calibrationIterations
    validSamples := []
    if (!freq)
        DllCall("QueryPerformanceFrequency", "Int64*", freq)
    Loop, %iterations% {
        DllCall("QueryPerformanceCounter", "Int64*", startTime)
        SendInput, {Numpad0 down}{Numpad0 up}
        DllCall("QueryPerformanceCounter", "Int64*", endTime)
        overhead := (endTime - startTime) * 1000 / freq
        validSamples.Push(overhead)
        Sleep, 10
    }
    tempArray := validSamples.Clone()
    Sort(tempArray)
    median := tempArray[Floor(tempArray.Length() / 2)]
    filteredSamples := []
    for i, sample in validSamples {
        if (Abs(sample - median) < outlierThreshold)
            filteredSamples.Push(sample)
    }
    if (filteredSamples.Length() < iterations * 0.5) {
        Sort(validSamples)
        trimCount := Floor(validSamples.Length() * 0.2)
        trimmedSamples := []
        for i, sample in validSamples {
            if (i > trimCount && i <= validSamples.Length() - trimCount)
                trimmedSamples.Push(sample)
        }
        filteredSamples := trimmedSamples
    }
    totalOverhead := 0
    for i, overhead in filteredSamples
        totalOverhead += overhead
    calculatedOverhead := filteredSamples.Length() > 0 
        ? totalOverhead / filteredSamples.Length() 
        : median
    return calculatedOverhead + 0.02
}

Sort(arr) {
    n := arr.Length()
    Loop, % n - 1 {
        swapped := false
        Loop, % n - A_Index {
            if (arr[A_Index] > arr[A_Index + 1]) {
                temp := arr[A_Index]
                arr[A_Index] := arr[A_Index + 1]
                arr[A_Index + 1] := temp
                swapped := true
            }
        }
        if (!swapped)
            break
    }
    return arr
}

UltraPreciseSleep(ms) {
    if (!freq)
        DllCall("QueryPerformanceFrequency", "Int64*", freq)
    ticksPerMs := freq / 1000
    targetTicks := ms * ticksPerMs
    DllCall("QueryPerformanceCounter", "Int64*", startTime)
    endTime := startTime + targetTicks
    Loop {
        DllCall("QueryPerformanceCounter", "Int64*", currentTime)
        if (currentTime >= endTime)
            break
    }
}

ShowPopup(message) {
    MouseGetPos, xpos, ypos
    ToolTip, %message%, xpos + 20, ypos + 20
    SetTimer, RemoveToolTip, -1000
}

RemoveToolTip() {
    ToolTip
}

CalculateAdjustment(samples) {
    if (samples.Length() < 3)
        return 0
    tempArray := []
    for i, sample in samples
        tempArray.Push(sample)
    Sort(tempArray)
    trimCount := Floor(tempArray.Length() * 0.15)
    if (trimCount > 0) {
        Loop, %trimCount% {
            tempArray.RemoveAt(1)
            tempArray.RemoveAt(tempArray.Length())
        }
    }
    total := 0
    for i, sample in tempArray
        total += sample
    avgTime := total / tempArray.Length()
    varianceSum := 0
    for i, sample in tempArray
        varianceSum += (sample - avgTime) ** 2
    variance := varianceSum / tempArray.Length()
    dynamicFactor := variance > 0.5 ? 0.3 : (variance > 0.2 ? 0.5 : 0.7)
    rawAdjustment := targetTime - avgTime
    maxAdjustment := holdTime * 0.1
    if (maxAdjustment < 0.05)
        maxAdjustment := 0.05
    if (maxAdjustment > 5)
        maxAdjustment := 5
    if (rawAdjustment > maxAdjustment)
        rawAdjustment := maxAdjustment
    else if (rawAdjustment < -maxAdjustment)
        rawAdjustment := -maxAdjustment
    return rawAdjustment * dynamicFactor
}

PerformWarmup() {
    ShowPopup("Performing ultra-precise warmup...")
    Loop, 20 {
        SendInput, {Numpad0 down}
        UltraPreciseSleep(3)
        SendInput, {Numpad0 up}
        Sleep, 10
    }
    ShowPopup("Warmup complete")
}

CheckPeriodicRecalibration() {
    DllCall("QueryPerformanceCounter", "Int64*", currentTime)
    timeSinceLastCal := (currentTime - lastCalibrationTime) * 1000 / freq
    if (timeSinceLastCal > calibrationInterval) {
        if (!isHolding && !GetKeyState("e", "P")) {
            ShowPopup("Performing precision recalibration...")
            systemOverhead := CalibrateOverhead()
            lastCalibrationTime := currentTime
            ShowPopup("Recalibration complete. Overhead: " . Round(systemOverhead, 4) . "ms")
        }
    }
}

F1::
    isActive := !isActive
    ShowPopup(isActive ? "🟢 Ultra-Precise ON" : "🔴 Ultra-Precise OFF")
    SoundBeep, % (isActive ? 800 : 500), 150
    if (isActive) {
        timingSamples := []
        adjustment := 0
        Hotkey, *e, CustomE, On
        Hotkey, *e Up, CustomE_Up, On
    } else {
        Hotkey, *e, Off
        Hotkey, *e Up, Off
    }
return

^Up:: holdTime += 0.01, holdTime := Round(holdTime, 2), targetTime := holdTime, ShowPopup("Hold Time: " . holdTime . "ms")
^+Up:: holdTime += 0.1, holdTime := Round(holdTime, 2), targetTime := holdTime, ShowPopup("Hold Time: " . holdTime . "ms")
^Down:: holdTime := Max(0.01, holdTime - 0.01), holdTime := Round(holdTime, 2), targetTime := holdTime, ShowPopup("Hold Time: " . holdTime . "ms")
^+Down:: holdTime := Max(0.01, holdTime - 0.1), holdTime := Round(holdTime, 2), targetTime := holdTime, ShowPopup("Hold Time: " . holdTime . "ms")

^e::
    InputBox, newValue, Set Hold Time, Enter precise hold time in ms:, , 200, 130, , , , , %holdTime%
    if (!ErrorLevel && newValue is number) {
        holdTime := newValue
        targetTime := holdTime
        adjustment := 0
        timingSamples := []
        ShowPopup("Hold Time set to: " . holdTime . "ms")
    }
return

!t::
    timingDiagnostics := !timingDiagnostics
    ShowPopup(timingDiagnostics ? "Timing Diagnostics ON" : "Timing Diagnostics OFF")
    timingSamples := []
return

CustomE:
    if (!isActive || isHolding)
        return
    isHolding := true
    CheckPeriodicRecalibration()
    while (GetKeyState("e", "P") && isActive) {
        if (timingDiagnostics && !freq)
            DllCall("QueryPerformanceFrequency", "Int64*", freq)
        if (timingDiagnostics)
            DllCall("QueryPerformanceCounter", "Int64*", pressStartTime)
        adjustedHoldTime := holdTime
        if (timingSamples.Length() >= 3)
            adjustedHoldTime += adjustment
        adjustedHoldTime -= systemOverhead
        if (adjustedHoldTime < 0.005)
            adjustedHoldTime := 0.005
        SendInput, {e down}
        UltraPreciseSleep(adjustedHoldTime)
        SendInput, {e up}
        if (timingDiagnostics) {
            DllCall("QueryPerformanceCounter", "Int64*", pressEndTime)
            actualTime := (pressEndTime - pressStartTime) * 1000 / freq
            if (actualTime > 0 && actualTime < holdTime * 3) {
                timingSamples.Push(actualTime)
                if (timingSamples.Length() > movingAvgWindow)
                    timingSamples.RemoveAt(1)
                adjustment := CalculateAdjustment(timingSamples)
                ShowPopup("Target: " . holdTime . "ms | Actual: " . Round(actualTime, 3) . "ms | Adj: " . Round(adjustment, 3) . "ms")
            }
        }
        if (adaptiveOverhead && Mod(A_TickCount, 2000) < 50)
            systemOverhead := CalibrateOverhead()
        Sleep, 1
    }
    isHolding := false
    SendInput, {e up}
return

CustomE_Up:
    isHolding := false
return

Max(a, b) {
    return (a > b) ? a : b
}

^Esc::
    DllCall("Winmm\timeEndPeriod", "UInt", 1)
    ExitApp
return

InitializeScript()
