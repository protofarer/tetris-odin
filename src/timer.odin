package game

import "core:fmt"
import rl "vendor:raylib"

// TODO: timer system
// is_active
// is_loop
// is_done

Timer :: struct {
    id: string, // for debugging
    accum: f32,
    duration: f32,
    state: Timer_State,
    mode: Timer_Mode,
    iterations: int,
    remaining: int,
    on_complete: proc(),
}

Timer_State :: enum {
    Inactive,
    Running,
    Paused,
    Completed,
}

Timer_Mode :: enum {
    One_Shot,
    Loop,
    Countdown,
}

create_timer :: proc(duration: f32, mode: Timer_Mode = .One_Shot, iterations: int = 1, id: string = "") -> Timer {
    timer := Timer{
        id = id,
        duration = duration,
        accum = duration,
        state = .Inactive,
        mode = mode,
        iterations = iterations,
        remaining = iterations,
    }
    return timer
}

start_timer :: proc(timer: ^Timer) {
    if timer.state != .Running {
        timer.state = .Running
        if timer.accum <= 0 {
            timer.accum = timer.duration
        }
    }
}

pause_timer :: proc(timer: ^Timer) {
    if timer.state == .Running {
        timer.state = .Paused
    }
}

resume_timer :: proc(timer: ^Timer) {
    if timer.state == .Paused {
        timer.state = .Running
    }
}


reset_timer :: proc(timer: ^Timer) {
    timer.accum = timer.duration
    timer.remaining = timer.iterations
    timer.state = .Inactive
}

restart_timer :: proc(timer: ^Timer) {
    timer.accum = timer.duration
    timer.state = .Running
}

clear_timer :: proc(timer: ^Timer) {
    timer.accum = 0
    timer.state = .Completed
}

process_timer :: proc(timer: ^Timer) -> bool {
    if timer.state != .Running {
        return false
    }

    timer.accum -= rl.GetFrameTime()

    if timer.accum <= 0 {
        if timer.on_complete != nil {
            timer.on_complete()
        }

        switch timer.mode {
        case .Loop:
            timer.accum = timer.duration + timer.accum

        case .One_Shot:
            timer.state = .Completed

        case .Countdown:
            timer.remaining -= 1
            if timer.remaining <= 0 {
                timer.state = .Completed
            } else {
                timer.accum = timer.duration + timer.accum
            }
        }
        return true
    }
    return false
}

is_timer_done :: proc(timer: Timer) -> bool {
    return timer.state == .Completed
}

get_timer_progress :: proc(timer: Timer) -> f32 {
    if timer.duration <= 0 {
        return 0
    }
    return 1 - (timer.accum / timer.duration)
}

get_time_until_turn :: proc(timer: Timer) -> f32 {
    if timer.state == .Completed || timer.state == .Inactive {
        return 0
    }
    return max(0, timer.accum)
}

set_timer_on_complete :: proc(timer: ^Timer, callback: proc()) {
    timer.on_complete = callback
}

debug_timer :: proc(timer: Timer) {
    id_str := timer.id != "" ? timer.id : "unnamed"
    fmt.printf(
        "Timer %s: %.2f/%.2f (%s)\n",
        id_str, timer.accum, timer.duration, timer.state,
    )
}

is_timer_running :: proc(timer: Timer) -> bool {
    return timer.state == .Running
}
