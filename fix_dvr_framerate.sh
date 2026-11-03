#!/bin/bash
# Create four candidate frame-rate remuxes of one DVR recording.
# Usage: bash fix_dvr_framerate.sh [recording-directory] [filename]

main() {
    local dependency recording_dir file detected_rate duration fps outfile new_duration
    local failures=0
    recording_dir="${1:-.}"
    file="${2:-00000000.dat}"
    for dependency in ffmpeg ffprobe; do
        command -v "$dependency" >/dev/null 2>&1 || {
            printf 'Missing dependency: %s\n' "$dependency" >&2
            return 1
        }
    done
    cd -- "$recording_dir" || return 1
    [[ -f "$file" ]] || {
        printf 'Input file not found: %s\n' "$file" >&2
        return 1
    }
    mkdir -p output_fixed || return 1
    printf 'Analyzing: %s\n' "$file"
    detected_rate=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate \
        -of default=noprint_wrappers=1:nokey=1 "$file") || return 1
    duration=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$file") || return 1
    printf 'Detected frame rate: %s\nDuration: %s seconds\n' "$detected_rate" "$duration"
    printf 'Testing 12.5, 15, 25 and 30 fps. Existing candidates will be overwritten.\n'
    for fps in 12.5 15 25 30; do
        outfile="output_fixed/test_${fps}fps.mp4"
        printf 'Testing %s fps...\n' "$fps"
        if ffmpeg -nostdin -y -hide_banner -loglevel error -r "$fps" -i "$file" -c copy "$outfile"; then
            if new_duration=$(ffprobe -v error -show_entries format=duration \
                -of default=noprint_wrappers=1:nokey=1 "$outfile"); then
                printf '  Result duration: %s seconds\n' "$new_duration"
            else
                printf '  Could not inspect: %s\n' "$outfile" >&2
                failures=$((failures + 1))
            fi
        else
            printf '  Failed: %s\n' "$outfile" >&2
            failures=$((failures + 1))
        fi
    done
    printf 'Candidates are in output_fixed/. Play successful files and compare with known recording timing.\n'
    (( failures == 0 ))
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
