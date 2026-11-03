#!/bin/bash
# Batch-remux DVR .dat files, or crop a four-quadrant composite video.
# Run from the folder containing the recordings. See README.md.

process_file() {
    local file="$1" relative outfile
    relative="${file#./}"
    outfile="output/converted/${relative%.dat}.mp4"
    mkdir -p -- "$(dirname -- "$outfile")" || return 1
    if [[ -e "$outfile" || -L "$outfile" ]]; then
        printf 'Output already exists: %s\n' "$outfile" >&2
        return 1
    fi
    if ffmpeg -nostdin -n -hide_banner -loglevel error -i "$file" -c copy "$outfile"; then
        printf 'Converted: %s\n' "$file"
    else
        printf 'Failed (or output exists): %s\n' "$file" >&2
        return 1
    fi
}

extract_cameras() {
    local file="$1" relative base_path camera
    relative="${file#./}"
    base_path="output/extracted_cameras/${relative%.dat}"
    mkdir -p -- "$(dirname -- "$base_path")" || return 1
    for camera in 1 2 3 4; do
        if [[ -e "${base_path}_cam${camera}.mp4" || -L "${base_path}_cam${camera}.mp4" ]]; then
            printf 'Output already exists: %s_cam%s.mp4\n' "$base_path" "$camera" >&2
            return 1
        fi
    done
    if ffmpeg -nostdin -n -hide_banner -loglevel error -i "$file" \
        -filter_complex "[0:v:0]split=4[s1][s2][s3][s4]; \
            [s1]crop=iw/2:ih/2:0:0[c1]; \
            [s2]crop=iw/2:ih/2:iw/2:0[c2]; \
            [s3]crop=iw/2:ih/2:0:ih/2[c3]; \
            [s4]crop=iw/2:ih/2:iw/2:ih/2[c4]" \
        -map "[c1]" "${base_path}_cam1.mp4" \
        -map "[c2]" "${base_path}_cam2.mp4" \
        -map "[c3]" "${base_path}_cam3.mp4" \
        -map "[c4]" "${base_path}_cam4.mp4"; then
        printf 'Extracted: %s\n' "$file"
    else
        printf 'Extraction failed (or output exists): %s\n' "$file" >&2
        return 1
    fi
}

# Define functions before exporting them to GNU Parallel's Bash workers.
export -f process_file extract_cameras

main() {
    set -o pipefail
    local dependency mode jobs worker
    mode="${MODE:-convert}"
    jobs="${PARALLEL_JOBS:-4}"
    for dependency in ffmpeg parallel find bash; do
        command -v "$dependency" >/dev/null 2>&1 || {
            printf 'Missing dependency: %s\n' "$dependency" >&2
            return 1
        }
    done
    [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || {
        printf 'PARALLEL_JOBS must be a positive integer.\n' >&2
        return 1
    }
    case "$mode" in
        convert) worker=process_file ;;
        extract) worker=extract_cameras ;;
        *) printf 'MODE must be convert or extract.\n' >&2; return 1 ;;
    esac
    mkdir -p output/converted output/extracted_cameras || return 1
    printf 'Mode: %s; parallel jobs: %s\n' "$mode" "$jobs"
    # Null delimiters preserve filenames with spaces, quotes, and newlines.
    # Exclude generated outputs, and explicitly use Bash for exported functions.
    if find . -path ./output -prune -o -type f -name '*.dat' -print0 |
        SHELL="$(command -v bash)" parallel -0 --no-run-if-empty -j "$jobs" "$worker" {}; then
        printf 'Processing finished. If no .dat files were found, no jobs ran.\n'
    else
        printf 'Processing finished with errors. Check the messages above.\n' >&2
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
