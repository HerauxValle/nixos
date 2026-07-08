#!/usr/bin/env bash
# modules/toggle.sh — enable / disable / toggle global float mode
# Requires: WINDOW_GAP, STATE_FILE (resolved by main.sh from config)

_hyprctl_windowrule() {
    if [[ "${HF_LANG_MODE:-false}" == "true" ]]; then
        hyprctl keyword windowrule "$1" >/dev/null 2>&1
    else
        local action="$1"
        if [[ "$action" == float\ on* ]]; then
            hyprctl eval 'hl.window_rule({ match = { class = ".*" }, float = true })' >/dev/null 2>&1
        elif [[ "$action" == float\ off* ]]; then
            hyprctl eval 'hl.window_rule({ match = { class = ".*" }, float = false })' >/dev/null 2>&1
        elif [[ "$action" == center\ on* ]]; then
            hyprctl eval 'hl.window_rule({ match = { class = ".*" }, center = true })' >/dev/null 2>&1
        elif [[ "$action" == center\ off* ]]; then
            hyprctl eval 'hl.window_rule({ match = { class = ".*" }, center = false })' >/dev/null 2>&1
        fi
    fi
}

_float_enable() {
    if [[ "${HF_LANG_MODE:-false}" == "true" ]]; then
        hyprctl keyword windowrule "float on, match:class (.*)" >/dev/null 2>&1
        hyprctl keyword windowrule "center on, match:class (.*)" >/dev/null 2>&1
    else
        hyprctl eval 'hl.window_rule({ match = { class = ".*" }, float = true, center = true })' >/dev/null 2>&1
    fi
    touch "$STATE_FILE"
    notify_user "Hyprfloat" "Floating mode ON"
}

_float_disable() {
    if [[ "${HF_LANG_MODE:-false}" == "true" ]]; then
        hyprctl keyword windowrule "float off, match:class (.*)" >/dev/null 2>&1
        hyprctl keyword windowrule "center off, match:class (.*)" >/dev/null 2>&1
    else
        hyprctl eval 'hl.window_rule({ match = { class = ".*" }, float = false, center = false })' >/dev/null 2>&1
    fi
    rm -f "$STATE_FILE"
    notify_user "Hyprfloat" "Floating mode OFF"
}

float_enable() {
    if [ -f "$STATE_FILE" ]; then
        notify_user "Hyprfloat" "Already ON — no change" "low"
        return 0
    fi
    _float_enable
}

float_disable() {
    if [ ! -f "$STATE_FILE" ]; then
        notify_user "Hyprfloat" "Already OFF — no change" "low"
        return 0
    fi
    _float_disable
}

float_toggle() {
    if [ -f "$STATE_FILE" ]; then
        _float_disable
    else
        _float_enable
    fi
}